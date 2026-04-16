import CoreGraphics

/// Orientation of accordion peek strips.
enum AccordionOrientation: Sendable, CaseIterable {
    case horizontal  // peek on left/right
    case vertical    // peek on top/bottom

    init(string: String) {
        self = string == "vertical" ? .vertical : .horizontal
    }

    var stringValue: String {
        self == .vertical ? "vertical" : "horizontal"
    }
}

/// Accordion layout — all windows sit at near-full container size, stacked
/// with a configurable peek-strip padding exposing the edges of adjacent
/// windows. The focused (MRU) window appears on top via macOS native z-order
/// (same AXRaise path used by every focus change). Matches AeroSpace's
/// `layoutAccordion` — see AeroSpace/Sources/AppBundle/layout/layoutRecursive.swift:142.
struct AccordionLayout: TilingEngine {
    var padding: CGFloat = 30
    var orientation: AccordionOrientation = .horizontal

    private(set) var order: [WindowID] = []
    private var focusedID: WindowID?

    nonisolated init() {}

    var windowIDs: [WindowID] { order }

    // MARK: - Insert / Remove

    mutating func insertWindow(_ id: WindowID, afterFocused focusedID: WindowID?) {
        guard !order.contains(id) else { return }
        if let focusedID, let idx = order.firstIndex(of: focusedID) {
            order.insert(id, at: idx + 1)
        } else {
            order.append(id)
        }
    }

    mutating func removeWindow(_ id: WindowID) {
        order.removeAll { $0 == id }
        if focusedID == id { focusedID = nil }
    }

    // MARK: - Focus

    mutating func setFocused(_ id: WindowID?) {
        focusedID = id
    }

    // MARK: - Calculate Frames

    func calculateFrames(in rect: CGRect, gaps: GapConfig) -> LayoutResult {
        guard !order.isEmpty else { return LayoutResult(frames: [:]) }
        let container = rect.insetBy(dx: gaps.outer, dy: gaps.outer)
        if order.count == 1 {
            return LayoutResult(frames: [order[0]: container])
        }

        let mruIndex = focusedID.flatMap { order.firstIndex(of: $0) } ?? order.count - 1
        let lastIndex = order.count - 1
        var frames: [WindowID: CGRect] = [:]

        for (i, id) in order.enumerated() {
            let lPad: CGFloat
            let rPad: CGFloat
            switch i {
            case 0:
                (lPad, rPad) = (0, padding)
            case lastIndex:
                (lPad, rPad) = (padding, 0)
            case mruIndex - 1:
                (lPad, rPad) = (0, 2 * padding)
            case mruIndex + 1:
                (lPad, rPad) = (2 * padding, 0)
            default:
                (lPad, rPad) = (padding, padding)
            }

            switch orientation {
            case .horizontal:
                frames[id] = CGRect(
                    x: container.minX + lPad,
                    y: container.minY,
                    width: max(0, container.width - lPad - rPad),
                    height: container.height
                )
            case .vertical:
                frames[id] = CGRect(
                    x: container.minX,
                    y: container.minY + lPad,
                    width: container.width,
                    height: max(0, container.height - lPad - rPad)
                )
            }
        }

        return LayoutResult(frames: frames)
    }

    // MARK: - Swap

    mutating func swapWindows(_ a: WindowID, _ b: WindowID) {
        guard let ia = order.firstIndex(of: a), let ib = order.firstIndex(of: b) else { return }
        order.swapAt(ia, ib)
    }

    // MARK: - Neighbor (index cycling — all windows overlap, geometric fails)

    func neighbor(of id: WindowID, direction: Direction, frames: LayoutResult) -> WindowID? {
        guard order.count > 1, let idx = order.firstIndex(of: id) else { return nil }
        let forward: Bool
        switch (orientation, direction) {
        case (.horizontal, .right), (.vertical, .down):
            forward = true
        case (.horizontal, .left), (.vertical, .up):
            forward = false
        default:
            return nil  // off-axis keys do nothing
        }
        let next = forward
            ? (idx + 1) % order.count
            : (idx - 1 + order.count) % order.count
        return order[next]
    }

    // MARK: - Resize (no-op: padding only changes via Settings/config)

    mutating func resizeSplit(at id: WindowID, delta: CGFloat, axis: SplitDirection?, in rect: CGRect, gaps: GapConfig) {
        // Intentional no-op. AeroSpace parity: accordion padding is a config
        // value, not an interactive resize target.
    }
}
