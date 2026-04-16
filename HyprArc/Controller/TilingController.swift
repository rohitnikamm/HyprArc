import ApplicationServices
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
    @Published var accessibilityGranted: Bool = AccessibilityHelper.isTrusted()

    let workspaceManager: WorkspaceManager
    let configLoader: ConfigLoader
    private let windowTracker: WindowTracker
    private var cancellables: Set<AnyCancellable> = []
    private var retileWorkItem: DispatchWorkItem?
    private var lastAppliedFrames: [WindowID: CGRect] = [:]

    private let logger = Logger(subsystem: "rohit.HyprArc", category: "TilingController")

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
        self.layoutName = Self.displayName(for: Self.makeEngine(from: configLoader.config))
    }

    /// Build a layout engine from the current config.
    private static func makeEngine(from config: HyprArcConfig) -> any TilingEngine {
        switch config.general.defaultLayout {
        case "master-stack":
            var engine = MasterStackLayout()
            engine.masterRatio = config.masterStack.masterRatio
            engine.orientation = MasterOrientation(string: config.masterStack.orientation)
            return engine
        case "accordion":
            var engine = AccordionLayout()
            engine.padding = config.accordion.padding
            engine.orientation = AccordionOrientation(string: config.accordion.orientation)
            return engine
        default:
            var engine = DwindleLayout()
            engine.defaultSplitRatio = config.dwindle.defaultSplitRatio
            return engine
        }
    }

    /// Friendly display name for a given engine instance.
    private static func displayName(for engine: any TilingEngine) -> String {
        if engine is MasterStackLayout { return "Master-Stack" }
        if engine is AccordionLayout { return "Accordion" }
        return "Dwindle"
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

        // Wire native resize: when AX reports a window moved/resized, back-calculate ratio
        windowTracker.onWindowFrameChanged = { [weak self] wid in
            self?.handleNativeResize(windowID: wid)
        }

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
    private func applyConfigChanges(_ config: HyprArcConfig) {
        guard AXIsProcessTrusted() else { return }
        let wantedKind = config.general.defaultLayout
        let currentKind: String = {
            let engine = workspaceManager.activeWorkspace.engine
            if engine is MasterStackLayout { return "master-stack" }
            if engine is AccordionLayout { return "accordion" }
            return "dwindle"
        }()

        // Switch layout if the configured default changed
        if wantedKind != currentKind {
            for i in workspaceManager.workspaces.indices {
                let currentWindows = workspaceManager.workspaces[i].engine.windowIDs
                workspaceManager.workspaces[i].engine = Self.makeEngine(from: config)
                for id in currentWindows {
                    workspaceManager.workspaces[i].engine.insertWindow(id, afterFocused: nil)
                }
            }
            layoutName = Self.displayName(for: workspaceManager.activeWorkspace.engine)
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
            } else if var accordion = workspaceManager.workspaces[i].engine as? AccordionLayout {
                accordion.padding = config.accordion.padding
                accordion.orientation = AccordionOrientation(string: config.accordion.orientation)
                workspaceManager.workspaces[i].engine = accordion
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
                        AXUIElement.disableAnimations(for: info.ownerPID) {
                            info.axElement.setPosition(WorkspaceManager.offscreenPoint)
                        }
                    }
                }

                logger.debug("Reassigned window \(windowID) from workspace \(wsID) to \(targetID) (config change)")
            }
        }

        // Reconcile float/tile state for all managed windows (handles rule changes)
        for i in workspaceManager.workspaces.indices {
            let tiledIDs = workspaceManager.workspaces[i].windowIDs
            let floatingIDs = workspaceManager.workspaces[i].floatingWindowIDs

            for windowID in tiledIDs {
                let bundleID = windowTracker.trackedWindows[windowID]?.bundleID
                if shouldFloat(bundleID: bundleID) {
                    workspaceManager.workspaces[i].engine.removeWindow(windowID)
                    workspaceManager.workspaces[i].windowIDs.remove(windowID)
                    workspaceManager.workspaces[i].floatingWindowIDs.insert(windowID)
                    logger.debug("Auto-floated window \(windowID) (rule change)")
                }
            }

            for windowID in floatingIDs {
                let bundleID = windowTracker.trackedWindows[windowID]?.bundleID
                if !shouldFloat(bundleID: bundleID) {
                    workspaceManager.workspaces[i].floatingWindowIDs.remove(windowID)
                    workspaceManager.workspaces[i].engine.insertWindow(windowID, afterFocused: nil)
                    workspaceManager.workspaces[i].windowIDs.insert(windowID)
                    logger.debug("Auto-unfloated window \(windowID) (rule change)")
                }
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
    func syncAndRetile() {
        // Suppress sync during active mouse resize/swap to prevent feedback loops
        // (setting frames triggers AXObserver which triggers syncAndRetile)
        guard !isResizing && !isSwapping && !isNativeResizing else { return }
        guard isEnabled, AXIsProcessTrusted(), !AccessibilityHelper.isAXDisabled() else { return }

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
                    AXUIElement.disableAnimations(for: info.ownerPID) {
                        info.axElement.setPosition(WorkspaceManager.offscreenPoint)
                    }
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
        guard isEnabled, AXIsProcessTrusted(), !AccessibilityHelper.isAXDisabled(), !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = currentGaps

        workspaceManager.activeWorkspace.engine.setFocused(windowTracker.focusedWindowID)

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
                    workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta, axis: .vertical, in: screenRect, gaps: gaps)
                    adjusted = true
                }
                if widthViolation && frame.width > 0 {
                    let delta = (minSize.width - frame.width) / screenRect.width
                    workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta, axis: .horizontal, in: screenRect, gaps: gaps)
                    adjusted = true
                }
            }
        }

        if adjusted {
            result = workspaceManager.activeWorkspace.engine.calculateFrames(in: screenRect, gaps: gaps)
        }

        // Collect windows to update
        struct RetileEntry {
            let windowInfo: WindowInfo
            let frame: CGRect
        }
        let entries: [RetileEntry] = result.frames.compactMap { (windowID, frame) in
            guard let windowInfo = windowTracker.trackedWindows[windowID] else { return nil }
            return RetileEntry(windowInfo: windowInfo, frame: frame)
        }

        // Dispatch AX calls concurrently with animation disabled
        lastAppliedFrames.removeAll()
        DispatchQueue.concurrentPerform(iterations: entries.count) { index in
            let entry = entries[index]
            AXUIElement.disableAnimations(for: entry.windowInfo.ownerPID) {
                entry.windowInfo.axElement.setFrame(entry.frame)
            }
        }
        for entry in entries {
            lastAppliedFrames[entry.windowInfo.windowID] = entry.frame
        }
    }

    /// Lightweight retile for interactive drag operations — skips constraint checks,
    /// only applies AX calls for frames that actually changed, disables animations,
    /// and dispatches per-window AX calls concurrently.
    private func retileFast() {
        let ws = workspaceManager.activeWorkspace
        guard isEnabled, AXIsProcessTrusted(), !AccessibilityHelper.isAXDisabled(), !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        workspaceManager.activeWorkspace.engine.setFocused(windowTracker.focusedWindowID)
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: currentGaps)

        // Collect changed windows (frame diffing)
        struct FrameUpdate {
            let windowInfo: WindowInfo
            let frame: CGRect
            let positionChanged: Bool
            let sizeChanged: Bool
            let originMovedOut: Bool
        }

        var updates: [FrameUpdate] = []
        for (windowID, frame) in result.frames {
            let oldFrame = lastAppliedFrames[windowID]

            // Skip entirely if frame hasn't changed (1px threshold)
            if let old = oldFrame, abs(old.origin.x - frame.origin.x) < 1
                && abs(old.origin.y - frame.origin.y) < 1
                && abs(old.width - frame.width) < 1
                && abs(old.height - frame.height) < 1 {
                continue
            }

            guard let windowInfo = windowTracker.trackedWindows[windowID] else { continue }

            let posChanged = oldFrame == nil
                || abs(oldFrame!.origin.x - frame.origin.x) >= 1
                || abs(oldFrame!.origin.y - frame.origin.y) >= 1
            let sizeChanged = oldFrame == nil
                || abs(oldFrame!.width - frame.width) >= 1
                || abs(oldFrame!.height - frame.height) >= 1

            // Pre-compute outside concurrent block (thread safety — lastAppliedFrames
            // must not be read from concurrent threads).
            let movedOut = oldFrame != nil
                && (frame.origin.x > oldFrame!.origin.x + 1
                 || frame.origin.y > oldFrame!.origin.y + 1)

            updates.append(FrameUpdate(
                windowInfo: windowInfo, frame: frame,
                positionChanged: posChanged, sizeChanged: sizeChanged,
                originMovedOut: movedOut))
        }

        guard !updates.isEmpty else { return }

        // Update frame cache BEFORE async dispatch (optimistic — next mouse event
        // uses intended frames for diffing, not stale AX-applied frames).
        for update in updates {
            lastAppliedFrames[update.windowInfo.windowID] = update.frame
        }

        // Fire-and-forget per-window AX dispatch with job cancellation (AeroSpace pattern).
        // Main thread returns immediately — never waits for AX IPC.
        // If a new frame arrives before the old job finishes, the old job is cancelled.
        for update in updates {
            pendingFrameJobs[update.windowInfo.windowID]?.cancel()

            let axElement = update.windowInfo.axElement
            let frame = update.frame
            let originMovedOut = update.originMovedOut
            let sizeChanged = update.sizeChanged
            let positionChanged = update.positionChanged

            var job: DispatchWorkItem!
            job = DispatchWorkItem {
                guard !job.isCancelled else { return }
                if originMovedOut {
                    axElement.setPosition(frame.origin)
                    guard !job.isCancelled else { return }
                    axElement.setSize(frame.size)
                } else {
                    if sizeChanged { axElement.setSize(frame.size) }
                    guard !job.isCancelled else { return }
                    if positionChanged { axElement.setPosition(frame.origin) }
                }
            }
            pendingFrameJobs[update.windowInfo.windowID] = job
            DispatchQueue.global(qos: .userInteractive).async(execute: job)
        }
    }

    // MARK: - Focus Navigation

    func focusDirection(_ direction: Direction) {
        guard AXIsProcessTrusted() else { return }
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

        let screenRect = ScreenHelper.axScreenRect()
        workspaceManager.activeWorkspace.engine.resizeSplit(at: focused, delta: delta, axis: nil, in: screenRect, gaps: currentGaps)
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
        guard AXIsProcessTrusted() else { return }
        guard id != workspaceManager.activeWorkspaceID, (1...9).contains(id) else { return }

        let outgoingIDs = workspaceManager.activeWorkspace.allWindowIDs
        let incomingWS = workspaceManager.workspaces[id - 1]
        let incomingIDs = incomingWS.allWindowIDs

        // Frames for incoming tiled windows
        let screenRect = ScreenHelper.axScreenRect()
        let result = isEnabled
            ? incomingWS.engine.calculateFrames(in: screenRect, gaps: currentGaps)
            : LayoutResult(frames: [:])

        // Collect every pid we're about to touch — disable animations once per app.
        let touchedIDs = outgoingIDs.union(incomingIDs)
        let pids = Set(touchedIDs.compactMap { windowTracker.trackedWindows[$0]?.ownerPID })

        AXUIElement.disableAnimations(forPIDs: pids) {
            // Pass A: unhide + retile incoming (AeroSpace refresh.swift:179-183).
            lastAppliedFrames.removeAll()
            for (windowID, frame) in result.frames {
                guard let info = windowTracker.trackedWindows[windowID] else { continue }
                let currentSize = info.axElement.size
                if currentSize == nil
                    || abs(currentSize!.width - frame.size.width) > 1
                    || abs(currentSize!.height - frame.size.height) > 1 {
                    info.axElement.setSize(frame.size)
                }
                info.axElement.setPosition(frame.origin)
                lastAppliedFrames[windowID] = frame
            }

            // Pass B: hide outgoing (AeroSpace refresh.swift:184-189). Skip any
            // window that also belongs to incoming (shouldn't happen, but be safe).
            for wid in outgoingIDs where !incomingIDs.contains(wid) {
                windowTracker.trackedWindows[wid]?.axElement.setPosition(WorkspaceManager.offscreenPoint)
            }

            // State update inside the block so any observers that react by
            // reading AX frames also benefit from the animation guard.
            workspaceManager.switchToWorkspace(id)
            activeWorkspaceID = workspaceManager.activeWorkspaceID
        }
    }

    func moveWindowToWorkspace(_ targetID: Int) {
        guard AXIsProcessTrusted() else { return }
        guard let focused = windowTracker.focusedWindowID else { return }
        workspaceManager.moveWindowToWorkspace(focused, workspace: targetID)
        retile()
    }

    // MARK: - Layout Switching

    /// Cycle active-workspace layout: Dwindle → Master-Stack → Accordion → Dwindle.
    func cycleLayout() {
        let engine = workspaceManager.activeWorkspace.engine
        let next: any TilingEngine
        if engine is DwindleLayout {
            var e = MasterStackLayout()
            e.masterRatio = configLoader.config.masterStack.masterRatio
            e.orientation = MasterOrientation(string: configLoader.config.masterStack.orientation)
            next = e
        } else if engine is MasterStackLayout {
            var e = AccordionLayout()
            e.padding = configLoader.config.accordion.padding
            e.orientation = AccordionOrientation(string: configLoader.config.accordion.orientation)
            next = e
        } else {
            var e = DwindleLayout()
            e.defaultSplitRatio = configLoader.config.dwindle.defaultSplitRatio
            next = e
        }
        replaceActiveEngine(with: next)
        logger.debug("Switched layout to \(self.layoutName)")
    }

    /// Direct-jump to Dwindle for the active workspace.
    func setLayoutDwindle() {
        if workspaceManager.activeWorkspace.engine is DwindleLayout { return }
        var e = DwindleLayout()
        e.defaultSplitRatio = configLoader.config.dwindle.defaultSplitRatio
        replaceActiveEngine(with: e)
        logger.debug("Set layout to Dwindle")
    }

    /// Direct-jump to Master-Stack for the active workspace.
    func setLayoutMasterStack() {
        if workspaceManager.activeWorkspace.engine is MasterStackLayout { return }
        var e = MasterStackLayout()
        e.masterRatio = configLoader.config.masterStack.masterRatio
        e.orientation = MasterOrientation(string: configLoader.config.masterStack.orientation)
        replaceActiveEngine(with: e)
        logger.debug("Set layout to Master-Stack")
    }

    /// Direct-jump to Accordion for the active workspace.
    func setLayoutAccordion() {
        if workspaceManager.activeWorkspace.engine is AccordionLayout { return }
        var e = AccordionLayout()
        e.padding = configLoader.config.accordion.padding
        e.orientation = AccordionOrientation(string: configLoader.config.accordion.orientation)
        replaceActiveEngine(with: e)
        logger.debug("Set layout to Accordion")
    }

    /// Flip accordion orientation horizontal ↔ vertical for the active workspace.
    /// No-op if the active engine isn't accordion.
    func toggleAccordionOrientation() {
        guard var accordion = workspaceManager.activeWorkspace.engine as? AccordionLayout else { return }
        accordion.orientation = accordion.orientation == .horizontal ? .vertical : .horizontal
        workspaceManager.activeWorkspace.engine = accordion
        retile()
        logger.debug("Toggled accordion orientation to \(accordion.orientation.stringValue)")
    }

    /// Swap the active workspace's engine, preserving windows.
    private func replaceActiveEngine(with newEngine: any TilingEngine) {
        let currentWindows = workspaceManager.activeWorkspace.engine.windowIDs
        var engine = newEngine
        for id in currentWindows {
            engine.insertWindow(id, afterFocused: nil)
        }
        workspaceManager.activeWorkspace.engine = engine
        layoutName = Self.displayName(for: engine)
        retile()
    }

    // MARK: - Mouse Resize & Swap

    private var resizingWindowID: WindowID?
    private var resizeAxis: SplitDirection?
    private var resizeDragOrigin: CGPoint?
    private var pendingFrameJobs: [WindowID: DispatchWorkItem] = [:]
    private var nativeResizingWindowID: WindowID?
    private var nativeResizeBaselineFrame: CGRect?           // Frozen frame at drag start
    private var nativeResizeLastCumulativeDelta: CGFloat = 0  // Last cumulative delta applied
    private var nativeResizeLastAxis: SplitDirection?         // Axis of last delta
    private var nativeResizeDragOrigin: CGPoint?              // Mouse position at drag start
    private var animationDisabledPIDs: Set<pid_t> = []

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

    /// Find if the point is near a split boundary. Returns the window ID and axis.
    /// Always returns the LEFT/TOP window — this ensures the window is in the split's
    /// first child, so `ratio + delta` gives the correct resize direction.
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
                        // Return the LEFT window (first child of horizontal split)
                        let leftID = frameA.minX < frameB.minX ? idA : idB
                        return (leftID, .horizontal)
                    }
                }
                // Check horizontal boundary (frames stacked)
                if abs(frameA.maxY - frameB.minY) < tolerance * 2 {
                    let boundaryY = (frameA.maxY + frameB.minY) / 2
                    let minX = max(frameA.minX, frameB.minX)
                    let maxX = min(frameA.maxX, frameB.maxX)
                    if abs(point.y - boundaryY) < tolerance && point.x >= minX && point.x <= maxX {
                        // Return the TOP window (first child of vertical split)
                        let topID = frameA.minY < frameB.minY ? idA : idB
                        return (topID, .vertical)
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

        workspaceManager.activeWorkspace.engine.resizeSplit(at: windowID, delta: delta, axis: axis, in: screenRect, gaps: currentGaps)
        resizeDragOrigin = point
        retileFast()  // Skip constraint checks during drag for smooth performance
    }

    /// End resize operation. Cancels pending AX jobs and runs full retile with constraint checks.
    func endResize() {
        let wasResizing = resizingWindowID != nil
        resizingWindowID = nil
        resizeAxis = nil
        resizeDragOrigin = nil

        // Cancel all pending async AX jobs from the drag session
        for (_, job) in pendingFrameJobs { job.cancel() }
        pendingFrameJobs.removeAll()

        if wasResizing {
            retile()  // Full retile with constraint checks on release
            logger.debug("End resize")
        }
    }

    // MARK: - Native Resize (AeroSpace-style: macOS handles drag, we adjust siblings)

    var isNativeResizing: Bool { nativeResizingWindowID != nil }

    /// Begin native resize: let macOS handle the window drag at 120fps.
    /// We disable animations and track which window is being dragged.
    func beginNativeResize(at point: CGPoint) {
        guard NSApp.keyWindow == nil else { return }
        guard let windowID = windowAt(point: point) else { return }
        nativeResizingWindowID = windowID

        // Snapshot the window's frame at drag start (frozen baseline for cumulative deltas)
        nativeResizeBaselineFrame = lastAppliedFrames[windowID]
            ?? windowTracker.trackedWindows[windowID]?.frame
        nativeResizeLastCumulativeDelta = 0
        nativeResizeLastAxis = nil
        nativeResizeDragOrigin = point

        // Disable animations for all tiled apps for the duration of the drag
        let pids = Set(windowTracker.trackedWindows.values.map { $0.ownerPID })
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        animationDisabledPIDs = pids
        logger.debug("Begin native resize for window \(windowID)")
    }

    /// End native resize: restore animations and full retile for perfect alignment.
    func endNativeResize() {
        let wasResizing = nativeResizingWindowID != nil
        let resizingID = nativeResizingWindowID

        // Final ratio adjustment: capture any remaining delta that slipped through thresholds
        if wasResizing, let windowID = resizingID,
           let baselineFrame = nativeResizeBaselineFrame,
           let windowInfo = windowTracker.trackedWindows[windowID] {
            let finalFrame = windowInfo.axElement.frame ?? windowInfo.frame
            let screenRect = ScreenHelper.axScreenRect()
            let gaps = currentGaps

            let totalWidthDelta = (finalFrame.width - baselineFrame.width) / screenRect.width
            let totalHeightDelta = (finalFrame.height - baselineFrame.height) / screenRect.height
            let finalDelta: CGFloat
            let finalAxis: SplitDirection

            if abs(totalWidthDelta) > abs(totalHeightDelta) {
                finalDelta = totalWidthDelta
                finalAxis = .horizontal
            } else {
                finalDelta = totalHeightDelta
                finalAxis = .vertical
            }

            // Apply remaining delta (total - already applied)
            let remainingDelta = finalDelta - nativeResizeLastCumulativeDelta
            if abs(remainingDelta) > 0.0005 {
                workspaceManager.activeWorkspace.engine.resizeSplit(
                    at: windowID, delta: remainingDelta, axis: finalAxis,
                    in: screenRect, gaps: gaps)
            }
        }

        nativeResizingWindowID = nil
        nativeResizeBaselineFrame = nil
        nativeResizeLastCumulativeDelta = 0
        nativeResizeLastAxis = nil
        nativeResizeDragOrigin = nil

        // Cancel pending async jobs
        for (_, job) in pendingFrameJobs { job.cancel() }
        pendingFrameJobs.removeAll()

        // Restore animations
        for pid in animationDisabledPIDs {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        animationDisabledPIDs.removeAll()

        if wasResizing {
            retile()
            logger.debug("End native resize")
        }
    }

    /// Called from WindowTracker when a window's frame changes via AX notification.
    /// During native resize, back-calculates the ratio delta and relayouts siblings.
    func handleNativeResize(windowID: WindowID) {
        guard nativeResizingWindowID == windowID else { return }
        guard !isResizing && !isSwapping else { return }
        guard let windowInfo = windowTracker.trackedWindows[windowID] else { return }
        let newFrame = windowInfo.frame
        guard let baselineFrame = nativeResizeBaselineFrame else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = currentGaps

        // Compute CUMULATIVE delta from frozen baseline (not incremental from last engine frame)
        let cumulativeWidthDelta = (newFrame.width - baselineFrame.width) / screenRect.width
        let cumulativeHeightDelta = (newFrame.height - baselineFrame.height) / screenRect.height

        // Determine dominant axis
        let cumulativeDelta: CGFloat
        let axis: SplitDirection
        if abs(cumulativeWidthDelta) > abs(cumulativeHeightDelta) {
            cumulativeDelta = cumulativeWidthDelta
            axis = .horizontal
        } else {
            cumulativeDelta = cumulativeHeightDelta
            axis = .vertical
        }

        guard abs(cumulativeDelta) > 0.002 else { return }

        // Convert cumulative to incremental: undo previous, apply new
        if let lastAxis = nativeResizeLastAxis, lastAxis != axis {
            // Axis changed mid-drag: undo old axis, apply new from scratch
            workspaceManager.activeWorkspace.engine.resizeSplit(
                at: windowID, delta: -nativeResizeLastCumulativeDelta, axis: lastAxis,
                in: screenRect, gaps: gaps)
            workspaceManager.activeWorkspace.engine.resizeSplit(
                at: windowID, delta: cumulativeDelta, axis: axis,
                in: screenRect, gaps: gaps)
        } else {
            let incrementalDelta = cumulativeDelta - nativeResizeLastCumulativeDelta
            guard abs(incrementalDelta) > 0.001 else { return }
            workspaceManager.activeWorkspace.engine.resizeSplit(
                at: windowID, delta: incrementalDelta, axis: axis,
                in: screenRect, gaps: gaps)
        }

        nativeResizeLastCumulativeDelta = cumulativeDelta
        nativeResizeLastAxis = axis

        retileSiblings(excluding: windowID)
    }

    /// Manual drag resize: compute cumulative delta from mouse position (not AX frame).
    /// Works in the gap between windows where macOS native resize doesn't trigger.
    func updateNativeResize(to point: CGPoint) {
        guard let windowID = nativeResizingWindowID else { return }
        guard let dragOrigin = nativeResizeDragOrigin else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let gaps = currentGaps

        // Delta from mouse movement (not window frame which may lag)
        let dx = (point.x - dragOrigin.x) / screenRect.width
        let dy = (point.y - dragOrigin.y) / screenRect.height

        let cumulativeDelta: CGFloat
        let axis: SplitDirection
        if let lockedAxis = nativeResizeLastAxis {
            // Once axis is determined, lock it for the drag session
            axis = lockedAxis
            cumulativeDelta = (axis == .horizontal) ? dx : dy
        } else if abs(dx) > abs(dy) && abs(dx) > 0.002 {
            axis = .horizontal
            cumulativeDelta = dx
        } else if abs(dy) > 0.002 {
            axis = .vertical
            cumulativeDelta = dy
        } else {
            return
        }

        let incrementalDelta = cumulativeDelta - nativeResizeLastCumulativeDelta
        guard abs(incrementalDelta) > 0.001 else { return }

        workspaceManager.activeWorkspace.engine.resizeSplit(
            at: windowID, delta: incrementalDelta, axis: axis,
            in: screenRect, gaps: gaps)

        nativeResizeLastCumulativeDelta = cumulativeDelta
        nativeResizeLastAxis = axis

        retileSiblings(excluding: windowID)
        retileDraggedWindow(windowID)
    }

    /// Apply the engine's calculated frame to the dragged window.
    /// Called during manual drag (not during native resize where macOS handles it).
    private func retileDraggedWindow(_ windowID: WindowID) {
        let screenRect = ScreenHelper.axScreenRect()
        let result = workspaceManager.activeWorkspace.engine.calculateFrames(
            in: screenRect, gaps: currentGaps)
        guard let frame = result.frames[windowID],
              let axElement = windowTracker.trackedWindows[windowID]?.axElement else { return }

        axElement.setPosition(frame.origin)
        axElement.setSize(frame.size)
    }

    /// Retile all windows EXCEPT the one being natively dragged.
    /// Uses async fire-and-forget dispatch with job cancellation.
    private func retileSiblings(excluding skipID: WindowID) {
        let ws = workspaceManager.activeWorkspace
        guard isEnabled, !ws.windowIDs.isEmpty else { return }

        let screenRect = ScreenHelper.axScreenRect()
        let result = ws.engine.calculateFrames(in: screenRect, gaps: currentGaps)

        for (windowID, frame) in result.frames {
            if windowID == skipID {
                // Don't cache the engine's frame for the dragged window —
                // the baseline frame is the correct reference during drag
                continue
            }

            let oldFrame = lastAppliedFrames[windowID]
            guard oldFrame == nil
                || abs(oldFrame!.origin.x - frame.origin.x) >= 1
                || abs(oldFrame!.origin.y - frame.origin.y) >= 1
                || abs(oldFrame!.width - frame.width) >= 1
                || abs(oldFrame!.height - frame.height) >= 1
            else { continue }

            lastAppliedFrames[windowID] = frame

            guard let axElement = windowTracker.trackedWindows[windowID]?.axElement else { continue }

            pendingFrameJobs[windowID]?.cancel()
            var job: DispatchWorkItem!
            job = DispatchWorkItem {
                guard !job.isCancelled else { return }
                axElement.setPosition(frame.origin)
                guard !job.isCancelled else { return }
                axElement.setSize(frame.size)
            }
            pendingFrameJobs[windowID] = job
            DispatchQueue.global(qos: .userInteractive).async(execute: job)
        }
    }

    // MARK: - Mouse Swap

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
