import CoreGraphics

/// A unique identifier for a window within the tiling engine.
/// Maps to CGWindowID. The engine never touches AXUIElement.
typealias WindowID = UInt32

/// The result of a layout calculation.
struct LayoutResult {
    /// Maps each managed window to its calculated frame.
    var frames: [WindowID: CGRect]
}

/// Direction for focus/swap navigation.
enum Direction: CaseIterable, Sendable {
    case left, right, up, down
}

/// Split direction for binary tree nodes.
enum SplitDirection: Sendable {
    case horizontal  // Children side by side (left | right)
    case vertical    // Children stacked (top / bottom)
}

/// Gap configuration for tiling.
struct GapConfig: Sendable {
    var inner: CGFloat = 5   // Gap between tiled windows
    var outer: CGFloat = 10  // Gap at screen edges

    static let zero = GapConfig(inner: 0, outer: 0)
}

/// Protocol that all tiling layout algorithms conform to.
/// Operates on pure geometry — no AX dependency.
protocol TilingEngine: Sendable {
    /// Insert a new window into the layout.
    /// `afterFocused` is the currently focused window (insertion point).
    mutating func insertWindow(_ id: WindowID, afterFocused focusedID: WindowID?)

    /// Remove a window from the layout.
    mutating func removeWindow(_ id: WindowID)

    /// Calculate frames for all windows within the given screen rect.
    func calculateFrames(in rect: CGRect, gaps: GapConfig) -> LayoutResult

    /// All window IDs currently managed by this engine.
    var windowIDs: [WindowID] { get }

    /// Find the neighbor of a window in a given direction (geometric).
    func neighbor(of id: WindowID, direction: Direction, frames: LayoutResult) -> WindowID?

    /// Swap two windows' positions in the layout data structure.
    mutating func swapWindows(_ a: WindowID, _ b: WindowID)

    /// Resize the split ratio. When `axis` is provided, targets the nearest ancestor split
    /// matching that axis. When nil, targets the window's immediate parent split.
    /// Rect + gaps are needed to calculate actual split directions (dwindle determines direction
    /// from aspect ratio at each level, not from stored tree data).
    mutating func resizeSplit(at id: WindowID, delta: CGFloat, axis: SplitDirection?, in rect: CGRect, gaps: GapConfig)

    /// Notify the engine which window is currently focused. Engines that depend on
    /// focus state (accordion MRU) override this; others inherit the default no-op.
    mutating func setFocused(_ id: WindowID?)
}

extension TilingEngine {
    mutating func setFocused(_ id: WindowID?) {}
}
