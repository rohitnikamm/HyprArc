import CoreGraphics

/// A node in the dwindle binary tree.
/// Leaf nodes hold a window ID; split nodes divide space between two children.
indirect enum DwindleNode: Sendable {
    case leaf(WindowID)
    case split(SplitNode)
}

/// An internal node that splits space between two children.
struct SplitNode: Sendable {
    var direction: SplitDirection
    var ratio: CGFloat  // 0.0–1.0, portion allocated to `first`
    var first: DwindleNode
    var second: DwindleNode
}

/// Dwindle (binary tree spiral) layout algorithm.
///
/// Each new window recursively splits the focused window's container.
/// Split direction is determined by the container's aspect ratio:
/// width > height → horizontal (side by side), otherwise vertical (stacked).
struct DwindleLayout: TilingEngine {
    private(set) var root: DwindleNode?
    /// Default ratio for new split nodes (0.1–0.9). Configurable via config.
    var defaultSplitRatio: CGFloat = 0.5

    var windowIDs: [WindowID] {
        guard let root else { return [] }
        return collectWindowIDs(root)
    }

    // MARK: - Insert

    mutating func insertWindow(_ id: WindowID, afterFocused focusedID: WindowID?) {
        guard let root else {
            self.root = .leaf(id)
            return
        }

        // If there's a focused window, split at that leaf
        if let focusedID, let _ = findLeaf(focusedID, in: root) {
            self.root = insertAt(focusedID, newWindow: id, in: root)
        } else {
            // No focus or focused not found — split at the last leaf
            let lastID = lastLeafID(in: root)
            self.root = insertAt(lastID, newWindow: id, in: root)
        }
    }

    /// Replace the target leaf with a split node containing the target and the new window.
    /// Split direction is deferred to `calculateFrames` by using a placeholder that will
    /// be resolved based on the container rect's aspect ratio.
    private func insertAt(
        _ targetID: WindowID, newWindow: WindowID, in node: DwindleNode
    ) -> DwindleNode {
        switch node {
        case .leaf(let wid):
            if wid == targetID {
                // Split this leaf: existing becomes first, new becomes second
                return .split(SplitNode(
                    direction: .horizontal,  // Placeholder — recalculated in calculateFrames
                    ratio: defaultSplitRatio,
                    first: .leaf(wid),
                    second: .leaf(newWindow)
                ))
            }
            return node

        case .split(var splitNode):
            splitNode.first = insertAt(targetID, newWindow: newWindow, in: splitNode.first)
            splitNode.second = insertAt(targetID, newWindow: newWindow, in: splitNode.second)
            return .split(splitNode)
        }
    }

    // MARK: - Remove

    mutating func removeWindow(_ id: WindowID) {
        guard let root else { return }
        self.root = remove(id, from: root)
    }

    /// Remove a leaf with the given ID. When removing from a split, replace the
    /// split with the sibling.
    private func remove(_ id: WindowID, from node: DwindleNode) -> DwindleNode? {
        switch node {
        case .leaf(let wid):
            return wid == id ? nil : node

        case .split(var splitNode):
            // Check if either child is the target leaf
            if case .leaf(let firstID) = splitNode.first, firstID == id {
                return splitNode.second
            }
            if case .leaf(let secondID) = splitNode.second, secondID == id {
                return splitNode.first
            }

            // Recurse into children
            if let newFirst = remove(id, from: splitNode.first) {
                splitNode.first = newFirst
            } else {
                return splitNode.second
            }

            if let newSecond = remove(id, from: splitNode.second) {
                splitNode.second = newSecond
            } else {
                return splitNode.first
            }

            return .split(splitNode)
        }
    }

    // MARK: - Calculate Frames

    func calculateFrames(in rect: CGRect, gaps: GapConfig) -> LayoutResult {
        guard let root else { return LayoutResult(frames: [:]) }
        var frames: [WindowID: CGRect] = [:]
        calculateFrames(node: root, rect: rect, gaps: gaps, isRoot: true, frames: &frames)
        return LayoutResult(frames: frames)
    }

    private func calculateFrames(
        node: DwindleNode,
        rect: CGRect,
        gaps: GapConfig,
        isRoot: Bool,
        frames: inout [WindowID: CGRect]
    ) {
        switch node {
        case .leaf(let wid):
            // Apply outer gaps only at screen edges, inner gaps between windows
            let insetRect: CGRect
            if isRoot {
                // Single window: apply outer gaps on all sides
                insetRect = rect.insetBy(dx: gaps.outer, dy: gaps.outer)
            } else {
                insetRect = rect
            }
            frames[wid] = insetRect

        case .split(let splitNode):
            // Determine split direction from container aspect ratio
            let direction: SplitDirection = rect.width > rect.height ? .horizontal : .vertical

            let (firstRect, secondRect) = splitRect(
                rect, direction: direction, ratio: splitNode.ratio, gaps: gaps, isRoot: isRoot
            )

            calculateFrames(node: splitNode.first, rect: firstRect, gaps: gaps, isRoot: false, frames: &frames)
            calculateFrames(node: splitNode.second, rect: secondRect, gaps: gaps, isRoot: false, frames: &frames)
        }
    }

    /// Split a rect into two sub-rects based on direction and ratio.
    private func splitRect(
        _ rect: CGRect,
        direction: SplitDirection,
        ratio: CGFloat,
        gaps: GapConfig,
        isRoot: Bool
    ) -> (CGRect, CGRect) {
        let outerGap = gaps.outer
        let halfInner = gaps.inner / 2

        switch direction {
        case .horizontal:
            let availableWidth = rect.width - (isRoot ? 2 * outerGap : 0)
            let firstWidth = availableWidth * ratio - halfInner
            let secondWidth = availableWidth * (1 - ratio) - halfInner

            let leftX = rect.minX + (isRoot ? outerGap : 0)
            let topY = rect.minY + (isRoot ? outerGap : 0)
            let height = rect.height - (isRoot ? 2 * outerGap : 0)

            let first = CGRect(x: leftX, y: topY, width: firstWidth, height: height)
            let second = CGRect(x: leftX + firstWidth + gaps.inner, y: topY, width: secondWidth, height: height)
            return (first, second)

        case .vertical:
            let availableHeight = rect.height - (isRoot ? 2 * outerGap : 0)
            let firstHeight = availableHeight * ratio - halfInner
            let secondHeight = availableHeight * (1 - ratio) - halfInner

            let leftX = rect.minX + (isRoot ? outerGap : 0)
            let topY = rect.minY + (isRoot ? outerGap : 0)
            let width = rect.width - (isRoot ? 2 * outerGap : 0)

            let first = CGRect(x: leftX, y: topY, width: width, height: firstHeight)
            let second = CGRect(x: leftX, y: topY + firstHeight + gaps.inner, width: width, height: secondHeight)
            return (first, second)
        }
    }

    // MARK: - Swap

    mutating func swapWindows(_ a: WindowID, _ b: WindowID) {
        guard let root else { return }
        self.root = swapInTree(a, b, in: root)
    }

    private func swapInTree(_ a: WindowID, _ b: WindowID, in node: DwindleNode) -> DwindleNode {
        switch node {
        case .leaf(let wid):
            if wid == a { return .leaf(b) }
            if wid == b { return .leaf(a) }
            return node

        case .split(var splitNode):
            splitNode.first = swapInTree(a, b, in: splitNode.first)
            splitNode.second = swapInTree(a, b, in: splitNode.second)
            return .split(splitNode)
        }
    }

    // MARK: - Resize

    mutating func resizeSplit(at id: WindowID, delta: CGFloat) {
        guard let root else { return }
        self.root = resizeInTree(at: id, delta: delta, in: root)
    }

    /// Find the split node that is the parent of the given window and adjust its ratio.
    private func resizeInTree(at id: WindowID, delta: CGFloat, in node: DwindleNode) -> DwindleNode {
        switch node {
        case .leaf:
            return node

        case .split(var splitNode):
            // Check if either direct child is the target leaf
            let firstContains = containsWindow(id, in: splitNode.first)
            let secondContains = containsWindow(id, in: splitNode.second)

            if firstContains && !secondContains {
                // Target is in first child
                if case .leaf(let wid) = splitNode.first, wid == id {
                    // Direct child — adjust this split's ratio
                    splitNode.ratio = clampRatio(splitNode.ratio + delta)
                } else {
                    splitNode.first = resizeInTree(at: id, delta: delta, in: splitNode.first)
                }
            } else if secondContains && !firstContains {
                if case .leaf(let wid) = splitNode.second, wid == id {
                    splitNode.ratio = clampRatio(splitNode.ratio - delta)
                } else {
                    splitNode.second = resizeInTree(at: id, delta: delta, in: splitNode.second)
                }
            }

            return .split(splitNode)
        }
    }

    private func clampRatio(_ ratio: CGFloat) -> CGFloat {
        min(max(ratio, 0.1), 0.9)
    }

    // MARK: - Neighbor (geometric)

    func neighbor(of id: WindowID, direction: Direction, frames: LayoutResult) -> WindowID? {
        // Delegated to GeometricNavigation protocol extension
        geometricNeighbor(of: id, direction: direction, frames: frames)
    }

    // MARK: - Tree Helpers

    private func collectWindowIDs(_ node: DwindleNode) -> [WindowID] {
        switch node {
        case .leaf(let wid):
            return [wid]
        case .split(let splitNode):
            return collectWindowIDs(splitNode.first) + collectWindowIDs(splitNode.second)
        }
    }

    private func findLeaf(_ id: WindowID, in node: DwindleNode) -> WindowID? {
        switch node {
        case .leaf(let wid):
            return wid == id ? wid : nil
        case .split(let splitNode):
            return findLeaf(id, in: splitNode.first) ?? findLeaf(id, in: splitNode.second)
        }
    }

    private func lastLeafID(in node: DwindleNode) -> WindowID {
        switch node {
        case .leaf(let wid):
            return wid
        case .split(let splitNode):
            return lastLeafID(in: splitNode.second)
        }
    }

    private func containsWindow(_ id: WindowID, in node: DwindleNode) -> Bool {
        switch node {
        case .leaf(let wid):
            return wid == id
        case .split(let splitNode):
            return containsWindow(id, in: splitNode.first) || containsWindow(id, in: splitNode.second)
        }
    }
}
