import AppKit

/// Centralizes screen rect retrieval and coordinate conversion.
///
/// NSScreen uses bottom-left origin. AXUIElement uses top-left origin.
/// All tiling calculations use AX coordinates (top-left origin).
enum ScreenHelper {
    /// Returns the usable screen rect in AX coordinates (top-left origin).
    /// Excludes menu bar and Dock.
    static func axScreenRect() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }

        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame

        // Convert from NSScreen (bottom-left origin) to AX (top-left origin)
        let axY = fullFrame.height - visibleFrame.maxY

        return CGRect(
            x: visibleFrame.origin.x,
            y: axY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}
