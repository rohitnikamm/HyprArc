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
    private let dispatcher: CommandDispatcher
    let tilingController: TilingController
    private var hotkeyContext: HotkeyContext?

    private let logger = Logger(subsystem: "rohit.Rover", category: "HotkeyManager")

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
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.debug("Global hotkeys + mouse events registered")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }
}

// MARK: - Context & Callback

/// Carries the dispatcher and controller through the C callback.
private final class HotkeyContext: @unchecked Sendable {
    let dispatcher: CommandDispatcher
    let tilingController: TilingController
    var lastDragTime: CFAbsoluteTime = 0

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
            if context.tilingController.windowAtTitleBar(point: location) != nil {
                context.tilingController.beginSwap(at: location)
            } else {
                context.tilingController.beginResize(at: location)
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
            if context.tilingController.isResizing {
                context.tilingController.updateResize(to: location)
            } else if context.tilingController.isSwapping {
                context.tilingController.updateSwapOverlay(at: location)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    if type == .leftMouseUp {
        let location = event.location

        DispatchQueue.main.async {
            if context.tilingController.isResizing {
                context.tilingController.endResize()
            }
            if context.tilingController.isSwapping {
                context.tilingController.endSwap(at: location)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    return Unmanaged.passUnretained(event)
}
