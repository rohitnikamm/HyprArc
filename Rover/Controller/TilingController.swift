import AppKit
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
    let configLoader: ConfigLoader
    private let windowTracker: WindowTracker
    private var cancellables: Set<AnyCancellable> = []
    private var retileWorkItem: DispatchWorkItem?
    private var lastAppliedFrames: [WindowID: CGRect] = [:]

    private let logger = Logger(subsystem: "rohit.Rover", category: "TilingController")

    /// Current gap config from the config file.
    var currentGaps: GapConfig {
        configLoader.config.gapConfig
    }

    init(windowTracker: WindowTracker, configLoader: ConfigLoader) {
        self.windowTracker = windowTracker
        self.configLoader = configLoader
        self.workspaceManager = WorkspaceManager(
            windowTracker: windowTracker,
            defaultEngine: Self.makeEngine(from: configLoader.config)
        )
        self.layoutName = configLoader.config.general.defaultLayout == "master-stack"
            ? "Master-Stack" : "Dwindle"
    }

    /// Build a layout engine from the current config.
    private static func makeEngine(from config: RoverConfig) -> any TilingEngine {
        if config.general.defaultLayout == "master-stack" {
            var engine = MasterStackLayout()
            engine.masterRatio = config.masterStack.masterRatio
            engine.orientation = MasterOrientation(string: config.masterStack.orientation)
            return engine
        } else {
            var engine = DwindleLayout()
            engine.defaultSplitRatio = config.dwindle.defaultSplitRatio
            return engine
        }
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

        // Reload on config changes
        configLoader.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                self?.applyConfigChanges(config)
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

    // MARK: - Config Application

    /// Apply layout and engine settings from config to all workspaces.
    private func applyConfigChanges(_ config: RoverConfig) {
        let wantsMasterStack = config.general.defaultLayout == "master-stack"
        let currentIsMasterStack = workspaceManager.activeWorkspace.engine is MasterStackLayout

        // Switch layout if the configured default changed
        if wantsMasterStack != currentIsMasterStack {
            for i in workspaceManager.workspaces.indices {
                let currentWindows = workspaceManager.workspaces[i].engine.windowIDs
                workspaceManager.workspaces[i].engine = Self.makeEngine(from: config)
                for id in currentWindows {
                    workspaceManager.workspaces[i].engine.insertWindow(id, afterFocused: nil)
                }
            }
            layoutName = wantsMasterStack ? "Master-Stack" : "Dwindle"
        }

        // Update engine-specific settings on all workspaces
        for i in workspaceManager.workspaces.indices {
            if var dwindle = workspaceManager.workspaces[i].engine as? DwindleLayout {
                dwindle.defaultSplitRatio = config.dwindle.defaultSplitRatio
                workspaceManager.workspaces[i].engine = dwindle
            } else if var master = workspaceManager.workspaces[i].engine as? MasterStackLayout {
                master.masterRatio = config.masterStack.masterRatio
                master.orientation = MasterOrientation(string: config.masterStack.orientation)
                workspaceManager.workspaces[i].engine = master
            }
        }

        // Move existing windows to their assigned workspaces (handles rule changes for running apps)
        for i in workspaceManager.workspaces.indices {
            let wsID = i + 1
            let allWindowIDs = workspaceManager.workspaces[i].windowIDs
                .union(workspaceManager.workspaces[i].floatingWindowIDs)
            for windowID in allWindowIDs {
                let bundleID = windowTracker.trackedWindows[windowID]?.bundleID
                guard let targetID = assignedWorkspace(bundleID: bundleID),
                      targetID != wsID else { continue }

                // Remove from current workspace
                let isFloating = workspaceManager.workspaces[i].floatingWindowIDs.contains(windowID)
                if isFloating {
                    workspaceManager.workspaces[i].floatingWindowIDs.remove(windowID)
                } else {
                    workspaceManager.workspaces[i].engine.removeWindow(windowID)
                    workspaceManager.workspaces[i].windowIDs.remove(windowID)
                }

                // Add to target workspace
                let targetFloat = shouldFloat(bundleID: bundleID)
                let targetIndex = targetID - 1
                if targetFloat {
                    workspaceManager.workspaces[targetIndex].floatingWindowIDs.insert(windowID)
                } else {
                    workspaceManager.workspaces[targetIndex].engine.insertWindow(windowID, afterFocused: nil)
                    workspaceManager.workspaces[targetIndex].windowIDs.insert(windowID)
                }

                // Hide offscreen if target workspace is not active
                if targetID != workspaceManager.activeWorkspaceID {
                    if let info = windowTracker.trackedWindows[windowID] {
                        info.axElement.setPosition(WorkspaceManager.offscreenPoint)
                    }
                }

                logger.debug("Reassigned window \(windowID) from workspace \(wsID) to \(targetID) (config change)")
            }
        }
    }

    /// Check if a window should be auto-floated based on window rules.
    private func shouldFloat(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return configLoader.config.windowRules.contains { rule in
            rule.action == "float" && rule.appID == bundleID
        }
    }

    /// Check if a window should be assigned to a specific workspace based on window rules.
    private func assignedWorkspace(bundleID: String?) -> Int? {
        guard let bundleID else { return nil }
        return configLoader.config.windowRules.first { rule in
            rule.appID == bundleID && rule.workspace != nil
        }?.workspace
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

        // Prune windows with invalid AX elements (destroyed but not yet removed
        // due to async notification timing)
        let invalidIDs = windowTracker.trackedWindows.values
            .filter { $0.axElement.role == nil }
            .map { $0.windowID }
        for wid in invalidIDs {
            windowTracker.trackedWindows.removeValue(forKey: wid)
            logger.debug("Pruned invalid window \(wid)")
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
            let bundleID = windowTracker.trackedWindows[windowID]?.bundleID
            let isFloat = shouldFloat(bundleID: bundleID)
            let targetWorkspaceID = assignedWorkspace(bundleID: bundleID)

            if let targetID = targetWorkspaceID, targetID != workspaceManager.activeWorkspaceID {
                // Assign to a different workspace
                let wsIndex = targetID - 1
                if isFloat {
                    workspaceManager.workspaces[wsIndex].floatingWindowIDs.insert(windowID)
                    logger.debug("Auto-floated window \(windowID) on workspace \(targetID) (window rule)")
                } else {
                    workspaceManager.workspaces[wsIndex].engine.insertWindow(windowID, afterFocused: nil)
                    workspaceManager.workspaces[wsIndex].windowIDs.insert(windowID)
                    logger.debug("Assigned window \(windowID) to workspace \(targetID) (window rule)")
                }
                // Hide offscreen since it's on an inactive workspace
                if let info = windowTracker.trackedWindows[windowID] {
                    info.axElement.setPosition(WorkspaceManager.offscreenPoint)
                }
            } else {
                // Insert into active workspace (existing behavior)
                if isFloat {
                    workspaceManager.activeWorkspace.floatingWindowIDs.insert(windowID)
                    logger.debug("Auto-floated window \(windowID) (window rule)")
                } else {
                    workspaceManager.activeWorkspace.engine.insertWindow(
                        windowID, afterFocused: windowTracker.focusedWindowID)
                    workspaceManager.activeWorkspace.windowIDs.insert(windowID)
                    logger.debug("Inserted window \(windowID) into workspace \(self.workspaceManager.activeWorkspaceID)")
                }
            }
        }

        // Remove gone windows from whichever workspace owns them
        let goneWindows = allManaged.subtracting(currentTileable)
        for windowID in goneWindows {
            workspaceManager.removeWindowFromAnyWorkspace(windowID)
            logger.debug("Removed gone window \(windowID)")
        }

        retile()

        // Notify observers (MenuBarView) that workspace content changed
        objectWillChange.send()
    }

    /// Calculate frames for the active workspace and apply them via AX.
    /// Constraint-aware: adjusts split ratios for windows with minimum size constraints.
    private func retile() {
        let ws = workspaceManager.activeWorkspace
        guard isEnabled, !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = currentGaps

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
            in: screenRect, gaps: currentGaps)

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
            in: screenRect, gaps: currentGaps)

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
            in: screenRect, gaps: currentGaps)

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

        let ws = workspaceManager.activeWorkspace
        guard isEnabled, !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: currentGaps)

        // Pass 1: Resize only windows that need it (while still offscreen).
        // Windows that kept their size have content already rendered — no re-render needed.
        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            let currentSize = windowInfo.axElement.size
            if currentSize == nil
                || abs(currentSize!.width - frame.size.width) > 1
                || abs(currentSize!.height - frame.size.height) > 1 {
                windowInfo.axElement.setSize(frame.size)
            }
        }

        // Pass 2: Move all to correct positions (instant appear with content intact)
        lastAppliedFrames.removeAll()
        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            windowInfo.axElement.setPosition(frame.origin)
            lastAppliedFrames[windowID] = frame
        }
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
            in: screenRect, gaps: currentGaps)
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
            in: screenRect, gaps: currentGaps)
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
            in: screenRect, gaps: currentGaps)
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
        // Don't resize when our own windows (Settings) are focused
        guard NSApp.keyWindow == nil else { return }
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
        // Don't swap when our own windows (Settings) are focused
        guard NSApp.keyWindow == nil else { return }
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
                in: screenRect, gaps: currentGaps)
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
