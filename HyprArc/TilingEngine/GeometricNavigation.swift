import CoreGraphics

/// Geometric neighbor-finding shared by all TilingEngine implementations.
/// Finds the nearest window in a given direction by center-point distance.
/// This is Hyprland-style navigation (geometry-based, not tree-based).
extension TilingEngine {
    func geometricNeighbor(
        of id: WindowID, direction: Direction, frames: LayoutResult
    ) -> WindowID? {
        guard let sourceFrame = frames.frames[id] else { return nil }
        let sourceCenter = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)

        var bestCandidate: WindowID?
        var bestDistance: CGFloat = .infinity

        for (candidateID, candidateFrame) in frames.frames where candidateID != id {
            let candidateCenter = CGPoint(x: candidateFrame.midX, y: candidateFrame.midY)

            let isInDirection: Bool
            switch direction {
            case .left:  isInDirection = candidateCenter.x < sourceCenter.x
            case .right: isInDirection = candidateCenter.x > sourceCenter.x
            case .up:    isInDirection = candidateCenter.y < sourceCenter.y
            case .down:  isInDirection = candidateCenter.y > sourceCenter.y
            }

            guard isInDirection else { continue }

            let distance = hypot(
                candidateCenter.x - sourceCenter.x,
                candidateCenter.y - sourceCenter.y
            )
            if distance < bestDistance {
                bestDistance = distance
                bestCandidate = candidateID
            }
        }

        return bestCandidate
    }
}
