import Combine
import CoreGraphics
import os

/// Orchestrates tiling: subscribes to WindowTracker events, feeds the
/// TilingEngine, and applies calculated frames back via AX.
///
/// This is the **only** layer that touches both AX (via WindowTracker)
/// and the pure-geometry engine.
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

    private var engine: any TilingEngine = DwindleLayout()
    private let windowTracker: WindowTracker
    private var managedWindowIDs: Set<WindowID> = []
    private var floatingWindowIDs: Set<WindowID> = []
    private var cancellables: Set<AnyCancellable> = []
    private var retileWorkItem: DispatchWorkItem?

    private let logger = Logger(subsystem: "rohit.Rover", category: "TilingController")

    init(windowTracker: WindowTracker) {
        self.windowTracker = windowTracker
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

    /// Diff tracked windows against managed windows, insert/remove as needed, then retile.
    private func syncAndRetile() {
        guard isEnabled else { return }

        // Refresh window properties before filtering (catches Electron ghost windows
        // that had zero-sized frames at creation time)
        for windowID in windowTracker.trackedWindows.keys {
            windowTracker.trackedWindows[windowID]?.refresh()
        }

        let currentTileable = Set(
            windowTracker.trackedWindows.values
                .filter { $0.isTileable && !$0.isExcluded }
                .map { $0.windowID }
        )

        // Clean up floating windows that are no longer present
        floatingWindowIDs = floatingWindowIDs.intersection(currentTileable)

        // Insert new windows (skip floating ones)
        let newWindows = currentTileable
            .subtracting(managedWindowIDs)
            .subtracting(floatingWindowIDs)
        for windowID in newWindows.sorted() {
            engine.insertWindow(windowID, afterFocused: windowTracker.focusedWindowID)
            managedWindowIDs.insert(windowID)
            logger.debug("Inserted window \(windowID) into engine")
        }

        // Remove gone windows
        let goneWindows = managedWindowIDs.subtracting(currentTileable)
        for windowID in goneWindows {
            engine.removeWindow(windowID)
            managedWindowIDs.remove(windowID)
            logger.debug("Removed window \(windowID) from engine")
        }

        retile()
    }

    /// Calculate frames and apply them to windows via AX.
    /// Constraint-aware: queries each window's minimum size and adjusts
    /// split ratios so every window gets at least its minimum.
    private func retile() {
        guard isEnabled, !managedWindowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = GapConfig()

        // First pass: calculate frames and check for constraint violations
        var result = engine.calculateFrames(in: screenRect, gaps: gaps)
        var adjusted = false

        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            guard let minSize = windowInfo.axElement.minimumSize else { continue }

            let widthViolation = minSize.width > frame.width + 2
            let heightViolation = minSize.height > frame.height + 2

            if widthViolation || heightViolation {
                // Calculate how much more space this window needs as a ratio delta
                if heightViolation && frame.height > 0 {
                    let needed = minSize.height - frame.height
                    let totalHeight = screenRect.height
                    let delta = needed / totalHeight
                    engine.resizeSplit(at: windowID, delta: delta)
                    adjusted = true
                }
                if widthViolation && frame.width > 0 {
                    let needed = minSize.width - frame.width
                    let totalWidth = screenRect.width
                    let delta = needed / totalWidth
                    engine.resizeSplit(at: windowID, delta: delta)
                    adjusted = true
                }
            }
        }

        // Second pass: recalculate with adjusted ratios if needed
        if adjusted {
            result = engine.calculateFrames(in: screenRect, gaps: gaps)
        }

        // Apply frames
        for (windowID, frame) in result.frames {
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }
            windowInfo.axElement.setFrame(frame)
        }
    }

    // MARK: - Focus Navigation

    /// Move focus to the nearest window in the given direction.
    func focusDirection(_ direction: Direction) {
        guard let focused = windowTracker.focusedWindowID,
              managedWindowIDs.contains(focused) else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = engine.calculateFrames(in: screenRect, gaps: GapConfig())

        guard let neighborID = engine.neighbor(of: focused, direction: direction, frames: result) else { return }
        guard let windowInfo = windowTracker.trackedWindows[neighborID] else { return }

        windowInfo.axElement.focusWindow()
    }

    // MARK: - Window Operations

    /// Swap the focused window with its neighbor in the given direction.
    func swapDirection(_ direction: Direction) {
        guard let focused = windowTracker.focusedWindowID,
              managedWindowIDs.contains(focused) else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = engine.calculateFrames(in: screenRect, gaps: GapConfig())

        guard let neighborID = engine.neighbor(of: focused, direction: direction, frames: result) else { return }

        engine.swapWindows(focused, neighborID)
        retile()
    }

    /// Resize the split ratio at the focused window's split point.
    func resizeFocusedSplit(delta: CGFloat) {
        guard let focused = windowTracker.focusedWindowID,
              managedWindowIDs.contains(focused) else { return }

        engine.resizeSplit(at: focused, delta: delta)
        retile()
    }

    /// Toggle floating for the focused window.
    /// Float: remove from engine, window stays at its current position.
    /// Un-float: re-insert into engine at the current focus point.
    func toggleFloat() {
        guard let focused = windowTracker.focusedWindowID else { return }

        if floatingWindowIDs.contains(focused) {
            // Un-float: re-insert into engine
            floatingWindowIDs.remove(focused)
            engine.insertWindow(focused, afterFocused: windowTracker.focusedWindowID)
            managedWindowIDs.insert(focused)
            logger.debug("Un-floated window \(focused)")
            retile()
        } else if managedWindowIDs.contains(focused) {
            // Float: remove from engine
            engine.removeWindow(focused)
            managedWindowIDs.remove(focused)
            floatingWindowIDs.insert(focused)
            logger.debug("Floated window \(focused)")
            retile()
        }
    }

    // MARK: - Layout Switching

    /// Cycle between dwindle and master-stack layouts.
    func cycleLayout() {
        let currentWindows = engine.windowIDs

        if engine is DwindleLayout {
            engine = MasterStackLayout()
            layoutName = "Master-Stack"
        } else {
            engine = DwindleLayout()
            layoutName = "Dwindle"
        }

        // Re-insert all windows into the new engine
        for id in currentWindows {
            engine.insertWindow(id, afterFocused: nil)
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
