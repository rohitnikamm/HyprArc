import ApplicationServices

enum AccessibilityHelper {
    /// Returns true if HyprArc has Accessibility permission.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Live test: actually tries to use the AX API to bypass TCC cache.
    /// macOS caches `AXIsProcessTrusted()` per process — this tests if AX truly works.
    static func isAXWorking() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        return result == .success
    }

    /// Returns true ONLY if AX is disabled due to permission revocation (.apiDisabled).
    /// Does NOT return true for transient failures (no focused app, timeout, etc.).
    /// Use this for revocation detection; use `isAXWorking()` for grant detection.
    static func isAXDisabled() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        return result == .apiDisabled
    }

    /// Prompts the user with the macOS accessibility permission dialog.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
