import AppKit

/// A borderless, translucent overlay window used to highlight the
/// target window during a drag-to-swap operation.
class SwapOverlayWindow: NSWindow {
    static let shared = SwapOverlayWindow()

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.systemOrange.withAlphaComponent(0.2)
        level = .floating
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
    }

    /// Show the overlay at the given frame (in AX/screen coordinates).
    /// Converts from AX top-left origin to NSWindow bottom-left origin.
    func showAt(frame: CGRect) {
        guard let screen = NSScreen.main else { return }

        // Convert from AX coordinates (top-left origin) to NSWindow (bottom-left origin)
        let nsY = screen.frame.height - frame.origin.y - frame.height
        let nsFrame = CGRect(x: frame.origin.x, y: nsY, width: frame.width, height: frame.height)

        setFrame(nsFrame, display: true)
        orderFront(nil)
    }

    /// Hide the overlay.
    func hide() {
        orderOut(nil)
    }
}
