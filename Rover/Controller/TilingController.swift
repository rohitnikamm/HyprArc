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

        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            windowInfo.axElement.setFrame(frame)
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
