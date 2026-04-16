import SwiftUI

/// Small SwiftUI-only visual of a tiling layout. No assets — pure rectangles.
struct LayoutPreviewCard: View {
    let kind: Kind
    let isSelected: Bool

    enum Kind {
        case dwindle, masterStack, accordion
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch kind {
                case .dwindle:     dwindleLayout(in: geo.size)
                case .masterStack: masterStackLayout(in: geo.size)
                case .accordion:   accordionLayout(in: geo.size)
                }
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Layout shapes

    private func dwindleLayout(in size: CGSize) -> some View {
        let g: CGFloat = 3
        let w = size.width, h = size.height
        let leftW = w * 0.5 - g / 2
        let rightW = w * 0.5 - g / 2
        let topH = h * 0.5 - g / 2
        let botH = h * 0.5 - g / 2
        return ZStack {
            tile(x: 0,            y: 0, w: leftW,  h: h)
            tile(x: leftW + g,    y: 0, w: rightW, h: topH)
            tile(x: leftW + g,    y: topH + g, w: rightW * 0.55 - g / 2, h: botH)
            tile(x: leftW + g + rightW * 0.55 + g / 2, y: topH + g, w: rightW * 0.45 - g / 2, h: botH)
        }
        .frame(width: w, height: h)
    }

    private func masterStackLayout(in size: CGSize) -> some View {
        let g: CGFloat = 3
        let w = size.width, h = size.height
        let masterW = w * 0.6 - g / 2
        let stackW = w * 0.4 - g / 2
        let each = (h - 2 * g) / 3
        return ZStack {
            tile(x: 0, y: 0, w: masterW, h: h)
            tile(x: masterW + g, y: 0,                  w: stackW, h: each)
            tile(x: masterW + g, y: each + g,           w: stackW, h: each)
            tile(x: masterW + g, y: 2 * (each + g),     w: stackW, h: each)
        }
        .frame(width: w, height: h)
    }

    private func accordionLayout(in size: CGSize) -> some View {
        let p: CGFloat = 8
        let w = size.width, h = size.height
        return ZStack {
            // Back card (peek from left), middle (peek both), front (peek from right)
            tile(x: 0,            y: 0, w: w - p * 2, h: h)
                .opacity(0.35)
            tile(x: p,            y: 0, w: w - p * 3, h: h)
                .opacity(0.55)
            tile(x: p * 2,        y: 0, w: w - p * 2, h: h)
        }
        .frame(width: w, height: h)
    }

    private func tile(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.18))
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }
}
