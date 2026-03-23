import ApplicationServices
import AppKit

/// Bridges AXUIElement details into a value type the controller can work with.
/// The TilingEngine never sees this — it only knows WindowID (UInt32).
struct WindowInfo {
    let windowID: CGWindowID
    let axElement: AXUIElement
    let ownerPID: pid_t
    let bundleID: String?
    var frame: CGRect
    var title: String
    var isMinimized: Bool
    var isFullscreen: Bool
    var role: String?
    var subrole: String?
    var hasCloseButton: Bool

    /// Whether this window should be tiled (standard window, not a dialog/sheet/panel).
    /// Filters out ghost/helper windows from Electron apps (VSCode, Slack, etc.)
    /// by requiring a close button — real windows have one, Electron helpers don't.
    var isTileable: Bool {
        role == kAXWindowRole as String
            && (subrole == kAXStandardWindowSubrole as String
                || subrole == nil
                || subrole?.isEmpty == true)
            && hasCloseButton
            && !isMinimized
            && !isFullscreen
    }

    /// Apps that should never be tiled.
    private static let excludedBundleIDs: Set<String> = [
        "rohit.HyprArc",
        "com.apple.SecurityAgent",
    ]

    var isExcluded: Bool {
        guard let bundleID else { return false }
        return Self.excludedBundleIDs.contains(bundleID)
    }

    /// Create a WindowInfo by reading properties from an AXUIElement.
    /// Returns nil if the element doesn't have a valid window ID.
    static func from(element: AXUIElement, pid: pid_t, bundleID: String?) -> WindowInfo? {
        guard let windowID = element.windowID else { return nil }

        return WindowInfo(
            windowID: windowID,
            axElement: element,
            ownerPID: pid,
            bundleID: bundleID,
            frame: element.frame ?? .zero,
            title: element.title ?? "",
            isMinimized: element.isMinimized,
            isFullscreen: element.isFullscreen,
            role: element.role,
            subrole: element.subrole,
            hasCloseButton: element.hasCloseButton
        )
    }

    /// Refresh mutable properties from the AXUIElement.
    mutating func refresh() {
        frame = axElement.frame ?? frame
        title = axElement.title ?? title
        isMinimized = axElement.isMinimized
        isFullscreen = axElement.isFullscreen
    }
}
