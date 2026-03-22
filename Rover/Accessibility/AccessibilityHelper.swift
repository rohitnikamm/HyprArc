import ApplicationServices

enum AccessibilityHelper {
    /// Returns true if Rover has Accessibility permission.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user with the macOS accessibility permission dialog.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
