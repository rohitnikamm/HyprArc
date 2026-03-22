import Combine
import CoreGraphics
import os

/// Orchestrates tiling: subscribes to WindowTracker events, feeds the
/// active workspace's TilingEngine, and applies calculated frames via AX.
///
/// This is the **only** layer that touches both AX (via WindowTracker)
/// and the pure-geometry engine (via WorkspaceManager).
@MainActor
class TilingController: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                syncAndRetile()
            }
        }
    }
    @Published var layoutName: String = "Dwindle"
    @Published var activeWorkspaceID: Int = 1

    let workspaceManager: WorkspaceManager
    private let windowTracker: WindowTracker
    private var cancellables: Set<AnyCancellable> = []
    private var retileWorkItem: DispatchWorkItem?
    private var lastAppliedFrames: [WindowID: CGRect] = [:]

    private let logger = Logger(subsystem: "rohit.Rover", category: "TilingController")

    init(windowTracker: WindowTracker) {
        self.windowTracker = windowTracker
        self.workspaceManager = WorkspaceManager(windowTracker: windowTracker)
    }

    // MARK: - Lifecycle

    func start() {
        windowTracker.$trackedWindows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &cancellables)

        windowTracker.$focusedWindowID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSync()
            }
            .store(in: &cancellables)

        // Forward workspace ID changes to our @Published property for SwiftUI
        workspaceManager.$activeWorkspaceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                self?.activeWorkspaceID = id
            }
            .store(in: &cancellables)

        // Initial sync after a short delay to let the tracker enumerate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncAndRetile()
        }
    }

    func stop() {
        cancellables.removeAll()
        retileWorkItem?.cancel()
    }

    // MARK: - Sync & Retile

    /// Diff tracked windows against active workspace, insert/remove as needed, then retile.
    private func syncAndRetile() {
        // Suppress sync during active mouse resize/swap to prevent feedback loops
        // (setting frames triggers AXObserver which triggers syncAndRetile)
        guard !isResizing && !isSwapping else { return }
        guard isEnabled else { return }

        // Refresh window properties before filtering
        for windowID in windowTracker.trackedWindows.keys {
            windowTracker.trackedWindows[windowID]?.refresh()
        }

        let currentTileable = Set(
            windowTracker.trackedWindows.values
                .filter { $0.isTileable && !$0.isExcluded }
                .map { $0.windowID }
        )

        let activeWS = workspaceManager.activeWorkspace

        // Clean up floating windows that are no longer present
        workspaceManager.activeWorkspace.floatingWindowIDs =
            activeWS.floatingWindowIDs.intersection(currentTileable)

        // Insert new windows into active workspace (skip floating, skip windows owned by other workspaces)
        let allManaged = workspaceManager.allManagedWindowIDs
        let newWindows = currentTileable
            .subtracting(allManaged)
        for windowID in newWindows.sorted() {
            workspaceManager.activeWorkspace.engine.insertWindow(
                windowID, afterFocused: windowTracker.focusedWindowID)
            workspaceManager.activeWorkspace.windowIDs.insert(windowID)
            logger.debug("Inserted window \(windowID) into workspace \(self.workspaceManager.activeWorkspaceID)")
        }

        // Remove gone windows from whichever workspace owns them
        let goneWindows = allManaged.subtracting(currentTileable)
        for windowID in goneWindows {
            workspaceManager.removeWindowFromAnyWorkspace(windowID)
            logger.debug("Removed gone window \(windowID)")
        }

        retile()
    }

    /// Calculate frames for the active workspace and apply them via AX.
    /// Constraint-aware: adjusts split ratios for windows with minimum size constraints.
    private func retile() {
        let ws = workspaceManager.activeWorkspace
        guard isEnabled, !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = GapConfig()

        // First pass: calculate frames and check for constraint violations
        var result = workspaceManager.activeWorkspace.engine.calculateFrames(in: screenRect, gaps: gaps)
        var adjusted = false

        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            guard let minSize = windowInfo.axElement.minimumSize else { continue }

            let widthViolation = minSize.width > frame.width + 2
            let heightViolation = minSize.height > frame.height + 2

            if widthViolation || heightViolation {
                if heightViolation && frame.height > 0 {
                    let delta = (minSize.height - frame.height) / screenRect.height
                    workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta)
                    adjusted = true
                }
                if widthViolation && frame.width > 0 {
                    let delta = (minSize.width - frame.width) / screenRect.width
                    workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta)
                    adjusted = true
                }
            }
        }

        if adjusted {
            result = workspaceManager.activeWorkspace.engine.calculateFrames(in: screenRect, gaps: gaps)
        }

        lastAppliedFrames.removeAll()
        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            windowInfo.axElement.setFrame(frame)
            lastAppliedFrames[windowID] = frame
        }
    }

    /// Lightweight retile for interactive drag operations — skips constraint checks
    /// and only applies AX calls for frames that actually changed.
    private func retileFast() {
        let ws = workspaceManager.activeWorkspace
        guard isEnabled, !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())

        for (windowID, frame) in result.frames {
            let oldFrame = lastAppliedFrames[windowID]

            // Skip entirely if frame hasn't changed
            if let old = oldFrame, abs(old.origin.x - frame.origin.x) < 1
                && abs(old.origin.y - frame.origin.y) < 1
                && abs(old.width - frame.width) < 1
                && abs(old.height - frame.height) < 1 {
                continue
            }

            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }

            // Only set position if it changed
            if oldFrame == nil || abs(oldFrame!.origin.x - frame.origin.x) >= 1
                || abs(oldFrame!.origin.y - frame.origin.y) >= 1 {
                windowInfo.axElement.setPosition(frame.origin)
            }

            // Only set size if it changed
            if oldFrame == nil || abs(oldFrame!.width - frame.width) >= 1
                || abs(oldFrame!.height - frame.height) >= 1 {
                windowInfo.axElement.setSize(frame.size)
            }

            lastAppliedFrames[windowID] = frame
        }
    }

    // MARK: - Focus Navigation

    func focusDirection(_ direction: Direction) {
        guard let focused = windowTracker.focusedWindowID,
              workspaceManager.activeWorkspace.windowIDs.contains(focused) else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())

        guard let neighborID = workspaceManager.activeWorkspace.engine.neighbor(
            of: focused, direction: direction, frames: result) else { return }
        guard let windowInfo = windowTracker.trackedWindows[neighborID] else { return }

        windowInfo.axElement.focusWindow()
    }

    // MARK: - Window Operations

    func swapDirection(_ direction: Direction) {
        guard let focused = windowTracker.focusedWindowID,
              workspaceManager.activeWorkspace.windowIDs.contains(focused) else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())

        guard let neighborID = workspaceManager.activeWorkspace.engine.neighbor(
            of: focused, direction: direction, frames: result) else { return }

        workspaceManager.activeWorkspace.engine.swapWindows(focused, neighborID)
        retile()
    }

    func resizeFocusedSplit(delta: CGFloat) {
        guard let focused = windowTracker.focusedWindowID,
              workspaceManager.activeWorkspace.windowIDs.contains(focused) else { return }

        workspaceManager.activeWorkspace.engine.resizeSplit(at: focused, delta: delta)
        retile()
    }

    func toggleFloat() {
        guard let focused = windowTracker.focusedWindowID else { return }

        if workspaceManager.activeWorkspace.floatingWindowIDs.contains(focused) {
            // Un-float
            workspaceManager.activeWorkspace.floatingWindowIDs.remove(focused)
            workspaceManager.activeWorkspace.engine.insertWindow(
                focused, afterFocused: windowTracker.focusedWindowID)
            workspaceManager.activeWorkspace.windowIDs.insert(focused)
            logger.debug("Un-floated window \(focused)")
            retile()
        } else if workspaceManager.activeWorkspace.windowIDs.contains(focused) {
            // Float
            workspaceManager.activeWorkspace.engine.removeWindow(focused)
            workspaceManager.activeWorkspace.windowIDs.remove(focused)
            workspaceManager.activeWorkspace.floatingWindowIDs.insert(focused)
            logger.debug("Floated window \(focused)")
            retile()
        }
    }

    // MARK: - Workspace Operations

    func switchToWorkspace(_ id: Int) {
        workspaceManager.switchToWorkspace(id)
        activeWorkspaceID = workspaceManager.activeWorkspaceID
        retile()
    }

    func moveWindowToWorkspace(_ targetID: Int) {
        guard let focused = windowTracker.focusedWindowID else { return }
        workspaceManager.moveWindowToWorkspace(focused, workspace: targetID)
        retile()
    }

    // MARK: - Layout Switching

    func cycleLayout() {
        let currentWindows = workspaceManager.activeWorkspace.engine.windowIDs

        if workspaceManager.activeWorkspace.engine is DwindleLayout {
            workspaceManager.activeWorkspace.engine = MasterStackLayout()
            layoutName = "Master-Stack"
        } else {
            workspaceManager.activeWorkspace.engine = DwindleLayout()
            layoutName = "Dwindle"
        }

        for id in currentWindows {
            workspaceManager.activeWorkspace.engine.insertWindow(id, afterFocused: nil)
        }

        retile()
        logger.debug("Switched layout to \(self.layoutName)")
    }

    // MARK: - Mouse Resize & Swap

    private var resizingWindowID: WindowID?
    private var resizeAxis: SplitDirection?
    private var resizeDragOrigin: CGPoint?

    private var swapSourceWindowID: WindowID?

    /// Find which tiled window contains the given screen point.
    func windowAt(point: CGPoint) -> WindowID? {
        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())
        for (windowID, frame) in result.frames {
            if frame.contains(point) {
                return windowID
            }
        }
        return nil
    }

    /// Find which tiled window's title bar contains the given point.
    /// Title bar is the top ~30px of the window frame.
    func windowAtTitleBar(point: CGPoint) -> WindowID? {
        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())
        for (windowID, frame) in result.frames {
            let titleBarRect = CGRect(
                x: frame.minX, y: frame.minY,
                width: frame.width, height: 30
            )
            if titleBarRect.contains(point) {
                return windowID
            }
        }
        return nil
    }

    /// Find if the point is near a split boundary. Returns the window ID whose
    /// split should be resized, and the axis of the boundary.
    func splitBoundaryAt(point: CGPoint, tolerance: CGFloat = 10) -> (WindowID, SplitDirection)? {
        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: GapConfig())
        let frames = result.frames

        for (idA, frameA) in frames {
            for (idB, frameB) in frames where idA != idB {
                // Check vertical boundary (frames side by side)
                if abs(frameA.maxX - frameB.minX) < tolerance * 2 {
                    let boundaryX = (frameA.maxX + frameB.minX) / 2
                    let minY = max(frameA.minY, frameB.minY)
                    let maxY = min(frameA.maxY, frameB.maxY)
                    if abs(point.x - boundaryX) < tolerance && point.y >= minY && point.y <= maxY {
                        return (idA, .horizontal)
                    }
                }
                // Check horizontal boundary (frames stacked)
                if abs(frameA.maxY - frameB.minY) < tolerance * 2 {
                    let boundaryY = (frameA.maxY + frameB.minY) / 2
                    let minX = max(frameA.minX, frameB.minX)
                    let maxX = min(frameA.maxX, frameB.maxX)
                    if abs(point.y - boundaryY) < tolerance && point.x >= minX && point.x <= maxX {
                        return (idA, .vertical)
                    }
                }
            }
        }
        return nil
    }

    /// Begin a mouse resize operation.
    func beginResize(at point: CGPoint) {
        guard let (windowID, axis) = splitBoundaryAt(point: point) else { return }
        resizingWindowID = windowID
        resizeAxis = axis
        resizeDragOrigin = point
        logger.debug("Begin resize at boundary near window \(windowID)")
    }

    /// Update resize during drag.
    func updateResize(to point: CGPoint) {
        guard let windowID = resizingWindowID,
              let axis = resizeAxis,
              let origin = resizeDragOrigin else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let delta: CGFloat
        switch axis {
        case .horizontal:
            delta = (point.x - origin.x) / screenRect.width
        case .vertical:
            delta = (point.y - origin.y) / screenRect.height
        }

        // Only apply if delta is significant
        guard abs(delta) > 0.005 else { return }

        workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta)
        resizeDragOrigin = point
        retileFast()  // Skip constraint checks during drag for smooth performance
    }

    /// End resize operation. Runs full retile with constraint checks.
    func endResize() {
        let wasResizing = resizingWindowID != nil
        resizingWindowID = nil
        resizeAxis = nil
        resizeDragOrigin = nil
        if wasResizing {
            retile()  // Full retile with constraint checks on release
            logger.debug("End resize")
        }
    }

    /// Begin a mouse swap operation (triggered by clicking on a window's title bar).
    func beginSwap(at point: CGPoint) {
        guard let windowID = windowAtTitleBar(point: point) else { return }
        swapSourceWindowID = windowID
        logger.debug("Begin swap from window \(windowID)")
    }

    /// Update swap overlay during drag — highlight the window under the mouse.
    func updateSwapOverlay(at point: CGPoint) {
        guard swapSourceWindowID != nil else { return }

        if let targetID = windowAt(point: point), targetID != swapSourceWindowID {
            // Show overlay on the target window
            let screenRect = ScreenHelper.axScreenRect()
            let result = workspaceManager.activeWorkspace.engine.calculateFrames(
                in: screenRect, gaps: GapConfig())
            if let targetFrame = result.frames[targetID] {
                SwapOverlayWindow.shared.showAt(frame: targetFrame)
            }
        } else {
            SwapOverlayWindow.shared.hide()
        }
    }

    /// End swap — swap source with whatever window is under the mouse.
    func endSwap(at point: CGPoint) {
        SwapOverlayWindow.shared.hide()

        guard let sourceID = swapSourceWindowID else { return }
        swapSourceWindowID = nil

        guard let targetID = windowAt(point: point),
              targetID != sourceID else {
            logger.debug("Swap cancelled — same or no target window")
            return
        }

        workspaceManager.activeWorkspace.engine.swapWindows(sourceID, targetID)
        retile()
        logger.debug("Swapped window \(sourceID) with \(targetID)")
    }

    var isResizing: Bool { resizingWindowID != nil }
    var isSwapping: Bool { swapSourceWindowID != nil }

    // MARK: - Debounce

    private func scheduleSync() {
        retileWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.syncAndRetile()
        }
        retileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
}
