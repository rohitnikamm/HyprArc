import ApplicationServices
import AppKit

extension AXUIElement {

    // MARK: - Generic Attribute Access

    func getAttribute<T>(_ attribute: String) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? T
    }

    func setAttribute(_ attribute: String, value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
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

    var pid: pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(self, &pid)
        return result == .success ? pid : nil
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
        setPosition(rect.origin)
        setSize(rect.size)
    }

    // MARK: - Window List

    var windows: [AXUIElement] {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return array
    }

    // MARK: - Focus

    func focusWindow() {
        _ = setAttribute(kAXMainAttribute, value: kCFBooleanTrue)
        _ = setAttribute(kAXFocusedAttribute, value: kCFBooleanTrue)

        if let pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
}
