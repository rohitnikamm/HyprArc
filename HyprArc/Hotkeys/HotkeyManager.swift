import ApplicationServices
import CoreGraphics
import os

/// Flag checked by the CGEvent callback to pass through keys during recording.
/// Set by KeyCaptureNSView when recording a keybinding in Settings.
nonisolated(unsafe) var isRecordingKeybinding = false

/// Manages a CGEvent tap for intercepting global keyboard shortcuts
/// and mouse events (Opt+drag for resize, Opt+Shift+drag for swap).
@MainActor
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private nonisolated(unsafe) var tapRunLoop: CFRunLoop?
    private var watchdogTimer: DispatchSourceTimer?
    private let dispatcher: CommandDispatcher
    let tilingController: TilingController
    private var hotkeyContext: HotkeyContext?

    private let logger = Logger(subsystem: "rohit.HyprArc", category: "HotkeyManager")

    init(dispatcher: CommandDispatcher, tilingController: TilingController) {
        self.dispatcher = dispatcher
        self.tilingController = tilingController
    }

    func start() {
        let context = HotkeyContext(
            dispatcher: dispatcher,
            tilingController: tilingController
        )
        hotkeyContext = context

        // Subscribe to binding changes from CommandDispatcher
        dispatcher.onBindingsChanged = { [weak context] bindings in
            context?.registeredBindings = Array(bindings)
        }

        // Seed current bindings into the new context (onBindingsChanged only fires
        // on config change — after wake/restart, config hasn't changed so the
        // callback never fires and registeredBindings would stay empty).
        context.registeredBindings = Array(dispatcher.currentBindings)

        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: contextPtr
        ) else {
            Unmanaged<HotkeyContext>.fromOpaque(contextPtr).release()
            logger.error("Failed to create CGEvent tap — check Accessibility permissions")
            return
        }

        eventTap = tap
        context.eventTapPort = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source

        // Run the tap on a dedicated background thread with its own run loop.
        // This prevents system-wide input freeze if main thread blocks on a
        // hanging AX call (e.g. when permission is revoked mid-session).
        var capturedRunLoop: CFRunLoop?
        let semaphore = DispatchSemaphore(value: 0)

        let thread = Thread {
            capturedRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            semaphore.signal()
            CFRunLoopRun()
        }
        thread.name = "HyprArc.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()

        _ = semaphore.wait(timeout: .now() + 2)
        tapRunLoop = capturedRunLoop
        tapThread = thread

        startWatchdog()
        logger.debug("Global hotkeys + mouse events registered")
    }

    /// Background watchdog: detects AX permission revocation.
    /// Uses dummy CGEvent.tapCreate() probe — the most reliable detection method:
    /// - `AXIsProcessTrusted()` returns stale `true` due to per-process TCC caching
    /// - `AXUIElementCopyAttributeValue` can hang indefinitely when permission is revoked
    /// - `CGEvent.tapCreate()` returns nil immediately when permission is revoked, never hangs
    /// On detection: disables tap + exit(0) immediately (Deskflow pattern).
    private func startWatchdog() {
        guard let tap = eventTap else { return }
        let tapRL = tapRunLoop
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            if !Self.isEventTapPermitted() {
                // Permission revoked — disable tap immediately to stop event swallowing
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
                if let tapRL { CFRunLoopStop(tapRL) }
                self?.watchdogTimer?.cancel()
                // exit(0) is safest: any AX call on main may hang,
                // graceful degradation risks blocking. Fresh launch gets clean TCC state.
                exit(0)
            }
        }
        timer.resume()
        watchdogTimer = timer
    }

    /// Reliable permission check: tries to create a dummy event tap.
    /// Returns false when permission is revoked. Fast, never hangs,
    /// not affected by TCC per-process caching.
    nonisolated static func isEventTapPermitted() -> Bool {
        let dummyTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        guard let tap = dummyTap else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    func stop() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl = tapRunLoop {
            CFRunLoopStop(rl)
        }
        tapThread?.cancel()
        tapThread = nil
        tapRunLoop = nil
        eventTap = nil
        runLoopSource = nil
    }
}

// MARK: - Context & Callback

/// Carries the dispatcher and controller through the C callback.
private final class HotkeyContext: @unchecked Sendable {
    let dispatcher: CommandDispatcher
    let tilingController: TilingController
    nonisolated(unsafe) var lastDragTime: CFAbsoluteTime = 0
    nonisolated(unsafe) var eventTapPort: CFMachPort?

    /// Dynamic list of registered keybindings, updated when config changes.
    /// Array (not Set) to avoid Hashable conformance in nonisolated context.
    nonisolated(unsafe) var registeredBindings: [KeyBinding] = []

    init(dispatcher: CommandDispatcher, tilingController: TilingController) {
        self.dispatcher = dispatcher
        self.tilingController = tilingController
    }
}

/// C-compatible callback for CGEvent tap. Must be nonisolated.
nonisolated private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap disabled by system
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Use dummy tapCreate probe — reliable, never hangs, bypasses TCC cache
        if !HotkeyManager.isEventTapPermitted() {
            // Permission revoked — disable tap, watchdog will exit(0)
            if let userInfo {
                let context = Unmanaged<HotkeyContext>.fromOpaque(userInfo).takeUnretainedValue()
                if let tap = context.eventTapPort {
                    CGEvent.tapEnable(tap: tap, enable: false)
                    CFMachPortInvalidate(tap)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        // Normal timeout (slow callback) — re-enable tap
        if let userInfo {
            let context = Unmanaged<HotkeyContext>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = context.eventTapPort {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<HotkeyContext>.fromOpaque(userInfo).takeUnretainedValue()
    let flags = event.flags

    // MARK: - Keyboard Events

    if type == .keyDown {
        // Pass through all keys during keybinding recording in Settings
        if isRecordingKeybinding {
            return Unmanaged.passUnretained(event)
        }

        // Fast guard: at least one modifier must be pressed to match any binding
        let hasAnyModifier = flags.contains(.maskAlternate)
            || flags.contains(.maskShift)
            || flags.contains(.maskCommand)
            || flags.contains(.maskControl)
        guard hasAnyModifier else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Check if this key+modifier matches any registered binding
        var shouldSwallow = false
        for binding in context.registeredBindings {
            if binding.matches(keyCode: keyCode, flags: flags) {
                shouldSwallow = true
                break
            }
        }

        if shouldSwallow {
            Task { @MainActor in
                _ = context.dispatcher.dispatch(keyCode: keyCode, flags: flags)
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Mouse Events

    if type == .leftMouseDown {
        let location = event.location

        DispatchQueue.main.async {
            // Check split boundary FIRST — consume event for manual drag tracking
            if context.tilingController.splitBoundaryAt(point: location) != nil {
                context.tilingController.beginNativeResize(at: location)
            } else if context.tilingController.windowAtTitleBar(point: location) != nil {
                context.tilingController.beginSwap(at: location)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseDragged {
        // Throttle to ~60fps
        let now = CFAbsoluteTimeGetCurrent()
        guard now - context.lastDragTime >= 0.016 else {
            return Unmanaged.passUnretained(event)
        }
        context.lastDragTime = now

        let location = event.location

        DispatchQueue.main.async {
            if context.tilingController.isNativeResizing {
                context.tilingController.updateNativeResize(to: location)
            } else if context.tilingController.isSwapping {
                context.tilingController.updateSwapOverlay(at: location)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseUp {
        let location = event.location

        DispatchQueue.main.async {
            if context.tilingController.isNativeResizing {
                context.tilingController.endNativeResize()
            }
            if context.tilingController.isSwapping {
                context.tilingController.endSwap(at: location)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    return Unmanaged.passUnretained(event)
}
