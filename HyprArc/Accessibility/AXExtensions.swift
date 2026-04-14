import ApplicationServices
import AppKit

extension AXUIElement {

    // MARK: - Generic Attribute Access

    func getAttribute<T>(_ attribute: String) -> T? {
        guard AXIsProcessTrusted() else { return nil }
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    func setAttribute(_ attribute: String, value: CFTypeRef) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    // MARK: - Window ID

    var windowID: CGWindowID? {
        var wid: CGWindowID = 0
        let result = _AXUIElementGetWindow(self, &wid)
        return result == .success ? wid : nil
    }

    // MARK: - Common Properties

    var role: String? {
        getAttribute(kAXRoleAttribute)
    }

    var subrole: String? {
        getAttribute(kAXSubroleAttribute)
    }

    var title: String? {
        getAttribute(kAXTitleAttribute)
    }

    var isMinimized: Bool {
        getAttribute(kAXMinimizedAttribute) ?? false
    }

    var isFullscreen: Bool {
        getAttribute("AXFullScreen") ?? false
    }

    /// True if the window has a close button — real user windows do,
    /// Electron helper/browser windows don't.
    var hasCloseButton: Bool {
        let value: AnyObject? = getAttribute(kAXCloseButtonAttribute)
        return value != nil
    }

    var pid: pid_t? {
        guard AXIsProcessTrusted() else { return nil }
        var pid: pid_t = 0
        let result = AXUIElementGetPid(self, &pid)
        return result == .success ? pid : nil
    }

    /// The minimum size the app allows for this window, if declared.
    var minimumSize: CGSize? {
        guard let value: AnyObject = getAttribute("AXMinimumSize") else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    // MARK: - Frame (Position + Size)

    var position: CGPoint? {
        guard let value: AnyObject = getAttribute(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    var size: CGSize? {
        guard let value: AnyObject = getAttribute(kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    var frame: CGRect? {
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        _ = setAttribute(kAXPositionAttribute, value: value)
    }

    func setSize(_ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        _ = setAttribute(kAXSizeAttribute, value: value)
    }

    func setFrame(_ rect: CGRect) {
        // Size → Position → Size ordering (from AeroSpace/yabai).
        // First setSize establishes the anchor, setPosition moves with correct size,
        // second setSize corrects any drift from the position change.
        setSize(rect.size)
        setPosition(rect.origin)
        setSize(rect.size)
    }

    // MARK: - Animation Control

    /// Temporarily disables macOS window resize/move animations for this app element.
    /// Used by AeroSpace, yabai, and Rectangle ("undocumented magic").
    /// `kAXEnhancedUserInterfaceAttribute` controls whether the app animates AX-driven
    /// frame changes — disabling it makes setPosition/setSize return faster.
    static func disableAnimations(for pid: pid_t, _ body: () -> Void) {
        guard AXIsProcessTrusted() else { body(); return }
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let wasEnabled: Bool
        if AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value) == .success {
            wasEnabled = (value as? Bool) ?? false
        } else {
            wasEnabled = false
        }
        if wasEnabled {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        body()
        if wasEnabled {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// Batch variant: toggle AXEnhancedUserInterface off on every pid once,
    /// run body, then restore. Used by workspace switch which writes frames
    /// across many apps in a single burst.
    static func disableAnimations(forPIDs pids: Set<pid_t>, _ body: () -> Void) {
        guard AXIsProcessTrusted() else { body(); return }
        var wasEnabled: [pid_t: Bool] = [:]
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            var value: AnyObject?
            let enabled = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value) == .success
                && ((value as? Bool) ?? false)
            wasEnabled[pid] = enabled
            if enabled {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
        }
        body()
        for (pid, enabled) in wasEnabled where enabled {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    // MARK: - Window List

    var windows: [AXUIElement] {
        guard AXIsProcessTrusted() else { return [] }
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    // MARK: - Focus

    func focusWindow() {
        guard AXIsProcessTrusted() else { return }
        // Activate the owning app FIRST so it comes to front,
        // then raise the window and set AX focus attributes.
        if let pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }

        _ = AXUIElementPerformAction(self, kAXRaiseAction as CFString)
        _ = setAttribute(kAXMainAttribute, value: kCFBooleanTrue)
        _ = setAttribute(kAXFocusedAttribute, value: kCFBooleanTrue)
    }
}
