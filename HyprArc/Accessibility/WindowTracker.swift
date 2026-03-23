import ApplicationServices
import AppKit
import Combine
import os

/// Enumerates all windows on screen, tracks creation/destruction/focus
/// changes via AXObserver, and publishes state for the UI and controller.
@MainActor
class WindowTracker: ObservableObject {
    @Published var trackedWindows: [CGWindowID: WindowInfo] = [:]
    @Published var focusedWindowID: CGWindowID?

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [Any] = []
    private var debounceWorkItem: DispatchWorkItem?

    private let logger = Logger(subsystem: "rohit.HyprArc", category: "WindowTracker")

    private var isStarted = false

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        guard AccessibilityHelper.isTrusted() else {
            logger.warning("Accessibility not granted — cannot track windows")
            return
        }
        isStarted = true
        enumerateExistingWindows()
        observeAppLifecycle()
    }

    func stop() {
        for (_, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observers.removeAll()

        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()

        trackedWindows.removeAll()
        focusedWindowID = nil
        isStarted = false
    }

    // MARK: - Full Enumeration

    private func enumerateExistingWindows() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }

        for app in apps {
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier
            let appElement = AXUIElementCreateApplication(pid)

            for window in appElement.windows {
                addWindowIfNeeded(window, pid: pid, bundleID: bundleID)
            }

            installObserver(for: pid, bundleID: bundleID)
        }

        updateFocusedWindow()
    }

    // MARK: - App Lifecycle

    private func observeAppLifecycle() {
        let center = NSWorkspace.shared.notificationCenter

        let launchToken = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            guard let tracker = self else { return }
            Task { @MainActor in
                tracker.handleAppLaunched(app)
            }
        }
        workspaceObservers.append(launchToken)

        let terminateToken = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            guard let tracker = self else { return }
            Task { @MainActor in
                tracker.handleAppTerminated(app)
            }
        }
        workspaceObservers.append(terminateToken)

        let activateToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let tracker = self else { return }
            Task { @MainActor in
                tracker.updateFocusedWindow()
            }
        }
        workspaceObservers.append(activateToken)
    }

    private func handleAppLaunched(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        for window in appElement.windows {
            addWindowIfNeeded(window, pid: pid, bundleID: bundleID)
        }

        installObserver(for: pid, bundleID: bundleID)
    }

    private func handleAppTerminated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier

        // Remove all windows for this app
        let windowsToRemove = trackedWindows.values.filter { $0.ownerPID == pid }
        for window in windowsToRemove {
            trackedWindows.removeValue(forKey: window.windowID)
        }

        // Remove observer
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }

        if let focused = focusedWindowID, trackedWindows[focused] == nil {
            updateFocusedWindow()
        }

        scheduleUpdate()
    }

    // MARK: - AXObserver

    private func installObserver(for pid: pid_t, bundleID: String?) {
        guard observers[pid] == nil else { return }

        let context = ObserverContext(tracker: self, pid: pid, bundleID: bundleID)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer else {
            Unmanaged<ObserverContext>.fromOpaque(contextPtr).release()
            logger.debug("Failed to create AXObserver for pid \(pid)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)

        let appNotifications: [String] = [
            kAXCreatedNotification,
            kAXFocusedWindowChangedNotification,
        ]

        for notification in appNotifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, contextPtr)
        }

        // Observe per-window notifications on existing windows
        for window in appElement.windows {
            addPerWindowObservations(observer: observer, window: window, context: contextPtr)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        observers[pid] = observer
    }

    private func addPerWindowObservations(
        observer: AXObserver, window: AXUIElement, context: UnsafeMutableRawPointer
    ) {
        let windowNotifications: [String] = [
            kAXUIElementDestroyedNotification,
            kAXWindowMovedNotification,
            kAXWindowResizedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ]

        for notification in windowNotifications {
            AXObserverAddNotification(observer, window, notification as CFString, context)
        }
    }

    // MARK: - Window Management

    private func addWindowIfNeeded(
        _ element: AXUIElement, pid: pid_t, bundleID: String?
    ) {
        guard let info = WindowInfo.from(element: element, pid: pid, bundleID: bundleID) else {
            return
        }
        guard !info.isExcluded else { return }
        guard trackedWindows[info.windowID] == nil else { return }

        trackedWindows[info.windowID] = info
        logger.debug("Tracked window: \(info.title) [\(info.windowID)]")
    }

    private func removeWindow(element: AXUIElement) {
        guard let wid = element.windowID else { return }
        removeWindow(windowID: wid)
    }

    private func removeWindow(windowID wid: CGWindowID) {
        if let info = trackedWindows.removeValue(forKey: wid) {
            logger.debug("Untracked window: \(info.title) [\(wid)]")
        }
        if focusedWindowID == wid {
            updateFocusedWindow()
        }
    }

    private func updateFocusedWindow() {
        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard result == .success else { return }

        let focusedElement = focusedValue as! AXUIElement
        if let wid = focusedElement.windowID {
            focusedWindowID = wid
        }
    }

    // MARK: - AX Notification Handling

    nonisolated func handleAXNotification(
        _ notification: String, element: AXUIElement, pid: pid_t, bundleID: String?,
        windowID: CGWindowID? = nil
    ) {
        Task { @MainActor in
            self._handleAXNotification(notification, element: element, pid: pid, bundleID: bundleID, windowID: windowID)
        }
    }

    private func _handleAXNotification(
        _ notification: String, element: AXUIElement, pid: pid_t, bundleID: String?,
        windowID: CGWindowID? = nil
    ) {
        switch notification {
        case kAXCreatedNotification:
            addWindowIfNeeded(element, pid: pid, bundleID: bundleID)
            // Add per-window observations for the new window
            if let observer = observers[pid] {
                let context = ObserverContext(tracker: self, pid: pid, bundleID: bundleID)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()
                addPerWindowObservations(observer: observer, window: element, context: contextPtr)
            }

        case kAXUIElementDestroyedNotification:
            // Use pre-extracted windowID (extracted synchronously in C callback
            // before async dispatch, since element may be invalid by now)
            if let wid = windowID ?? element.windowID {
                removeWindow(windowID: wid)
            }

        case kAXFocusedWindowChangedNotification:
            updateFocusedWindow()

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if let wid = element.windowID {
                trackedWindows[wid]?.refresh()
            }

        case kAXWindowMiniaturizedNotification:
            if let wid = element.windowID {
                trackedWindows[wid]?.isMinimized = true
            }

        case kAXWindowDeminiaturizedNotification:
            if let wid = element.windowID {
                trackedWindows[wid]?.isMinimized = false
            }

        default:
            break
        }

        scheduleUpdate()
    }

    // MARK: - Debounce

    private func scheduleUpdate() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
}

// MARK: - Observer Context & Callback

/// Carries tracker reference + app metadata through the C callback.
private final class ObserverContext: @unchecked Sendable {
    nonisolated(unsafe) weak var tracker: WindowTracker?
    let pid: pid_t
    let bundleID: String?

    init(tracker: WindowTracker, pid: pid_t, bundleID: String?) {
        self.tracker = tracker
        self.pid = pid
        self.bundleID = bundleID
    }
}

/// C-compatible callback for AXObserver. Must be nonisolated to form a C function pointer.
nonisolated private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let context = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()

    // Extract windowID synchronously for destruction notifications —
    // the element may become invalid after async dispatch to MainActor
    var extractedWindowID: CGWindowID?
    if (notification as String) == kAXUIElementDestroyedNotification {
        var wid: CGWindowID = 0
        if _AXUIElementGetWindow(element, &wid) == .success {
            extractedWindowID = wid
        }
    }

    context.tracker?.handleAXNotification(
        notification as String,
        element: element,
        pid: context.pid,
        bundleID: context.bundleID,
        windowID: extractedWindowID
    )
}
