import CoreGraphics

/// Orientation of the master area relative to the stack.
enum MasterOrientation: Sendable, CaseIterable {
    case left, right, top, bottom

    init(string: String) {
        switch string {
        case "right": self = .right
        case "top": self = .top
        case "bottom": self = .bottom
        default: self = .left
        }
    }
}

/// Master-stack layout algorithm.
///
/// Divides the screen into two regions: a master area (default 55%) and a
/// stack area. The first window becomes the master; subsequent windows stack
/// in the remaining space. Supports promote/demote to move windows between
/// master and stack.
struct MasterStackLayout: TilingEngine {
    var masterRatio: CGFloat = 0.55
    var orientation: MasterOrientation = .left

    private(set) var masterWindows: [WindowID] = []
    private(set) var stackWindows: [WindowID] = []

    var windowIDs: [WindowID] {
        masterWindows + stackWindows
    }

    // MARK: - Insert

    mutating func insertWindow(_ id: WindowID, afterFocused focusedID: WindowID?) {
        if masterWindows.isEmpty {
            masterWindows.append(id)
        } else {
            stackWindows.append(id)
        }
    }

    // MARK: - Remove

    mutating func removeWindow(_ id: WindowID) {
        if let idx = masterWindows.firstIndex(of: id) {
            masterWindows.remove(at: idx)
            // Auto-promote first stack window if master is now empty
            if masterWindows.isEmpty, !stackWindows.isEmpty {
                masterWindows.append(stackWindows.removeFirst())
            }
        } else if let idx = stackWindows.firstIndex(of: id) {
            stackWindows.remove(at: idx)
        }
    }

    // MARK: - Promote / Demote

    /// Move a window from stack to master.
    mutating func promote(_ id: WindowID) {
        guard let idx = stackWindows.firstIndex(of: id) else { return }
        stackWindows.remove(at: idx)
        masterWindows.append(id)
    }

    /// Move a window from master to stack.
    mutating func demote(_ id: WindowID) {
        guard let idx = masterWindows.firstIndex(of: id) else { return }
        masterWindows.remove(at: idx)
        stackWindows.insert(id, at: 0)
        // Ensure at least one master
        if masterWindows.isEmpty, !stackWindows.isEmpty {
            masterWindows.append(stackWindows.removeFirst())
        }
    }

    // MARK: - Calculate Frames

    func calculateFrames(in rect: CGRect, gaps: GapConfig) -> LayoutResult {
        let allWindows = windowIDs
        guard !allWindows.isEmpty else { return LayoutResult(frames: [:]) }

        var frames: [WindowID: CGRect] = [:]

        // Single window: fills the screen
        if allWindows.count == 1 {
            frames[allWindows[0]] = rect.insetBy(dx: gaps.outer, dy: gaps.outer)
            return LayoutResult(frames: frames)
        }

        // Only master windows, no stack
        if stackWindows.isEmpty {
            let masterFrames = distributeEqually(
                masterWindows, in: rect.insetBy(dx: gaps.outer, dy: gaps.outer),
                along: stackAxis, gaps: gaps
            )
            for (id, frame) in masterFrames { frames[id] = frame }
            return LayoutResult(frames: frames)
        }

        // Split into master and stack areas
        let (masterRect, stackRect) = splitForMasterStack(rect, gaps: gaps)

        // Distribute master windows equally within master area
        let masterFrames = distributeEqually(
            masterWindows, in: masterRect, along: stackAxis, gaps: gaps
        )
        for (id, frame) in masterFrames { frames[id] = frame }

        // Distribute stack windows equally within stack area
        let stackFrames = distributeEqually(
            stackWindows, in: stackRect, along: stackAxis, gaps: gaps
        )
        for (id, frame) in stackFrames { frames[id] = frame }

        return LayoutResult(frames: frames)
    }

    /// The axis along which windows within master/stack are stacked.
    /// If master is on left/right, stack windows vertically. If top/bottom, horizontally.
    private var stackAxis: SplitDirection {
        switch orientation {
        case .left, .right: return .vertical
        case .top, .bottom: return .horizontal
        }
    }

    /// Split the screen rect into master and stack areas based on orientation and ratio.
    private func splitForMasterStack(
        _ rect: CGRect, gaps: GapConfig
    ) -> (master: CGRect, stack: CGRect) {
        let outer = gaps.outer
        let halfInner = gaps.inner / 2

        switch orientation {
        case .left:
            let availW = rect.width - 2 * outer - gaps.inner
            let masterW = availW * masterRatio
            let stackW = availW - masterW
            let y = rect.minY + outer
            let h = rect.height - 2 * outer
            let master = CGRect(x: rect.minX + outer, y: y, width: masterW, height: h)
            let stack = CGRect(x: rect.minX + outer + masterW + gaps.inner, y: y, width: stackW, height: h)
            return (master, stack)

        case .right:
            let availW = rect.width - 2 * outer - gaps.inner
            let masterW = availW * masterRatio
            let stackW = availW - masterW
            let y = rect.minY + outer
            let h = rect.height - 2 * outer
            let stack = CGRect(x: rect.minX + outer, y: y, width: stackW, height: h)
            let master = CGRect(x: rect.minX + outer + stackW + gaps.inner, y: y, width: masterW, height: h)
            return (master, stack)

        case .top:
            let availH = rect.height - 2 * outer - gaps.inner
            let masterH = availH * masterRatio
            let stackH = availH - masterH
            let x = rect.minX + outer
            let w = rect.width - 2 * outer
            let master = CGRect(x: x, y: rect.minY + outer, width: w, height: masterH)
            let stack = CGRect(x: x, y: rect.minY + outer + masterH + gaps.inner, width: w, height: stackH)
            return (master, stack)

        case .bottom:
            let availH = rect.height - 2 * outer - gaps.inner
            let masterH = availH * masterRatio
            let stackH = availH - masterH
            let x = rect.minX + outer
            let w = rect.width - 2 * outer
            let stack = CGRect(x: x, y: rect.minY + outer, width: w, height: stackH)
            let master = CGRect(x: x, y: rect.minY + outer + stackH + gaps.inner, width: w, height: masterH)
            return (master, stack)
        }
    }

    /// Distribute windows equally within a rect along the given axis.
    private func distributeEqually(
        _ windows: [WindowID], in rect: CGRect,
        along axis: SplitDirection, gaps: GapConfig
    ) -> [(WindowID, CGRect)] {
        guard !windows.isEmpty else { return [] }
        if windows.count == 1 {
            return [(windows[0], rect)]
        }

        let count = CGFloat(windows.count)
        let totalGaps = gaps.inner * (count - 1)

        switch axis {
        case .vertical:
            let itemHeight = (rect.height - totalGaps) / count
            return windows.enumerated().map { (i, id) in
                let y = rect.minY + CGFloat(i) * (itemHeight + gaps.inner)
                return (id, CGRect(x: rect.minX, y: y, width: rect.width, height: itemHeight))
            }

        case .horizontal:
            let itemWidth = (rect.width - totalGaps) / count
            return windows.enumerated().map { (i, id) in
                let x = rect.minX + CGFloat(i) * (itemWidth + gaps.inner)
                return (id, CGRect(x: x, y: rect.minY, width: itemWidth, height: rect.height))
            }
        }
    }

    // MARK: - Swap

    mutating func swapWindows(_ a: WindowID, _ b: WindowID) {
        // Swap within master
        if let idxA = masterWindows.firstIndex(of: a),
           let idxB = masterWindows.firstIndex(of: b) {
            masterWindows.swapAt(idxA, idxB)
            return
        }
        // Swap within stack
        if let idxA = stackWindows.firstIndex(of: a),
           let idxB = stackWindows.firstIndex(of: b) {
            stackWindows.swapAt(idxA, idxB)
            return
        }
        // Swap between master and stack (promote/demote)
        if let idxA = masterWindows.firstIndex(of: a),
           let idxB = stackWindows.firstIndex(of: b) {
            masterWindows[idxA] = b
            stackWindows[idxB] = a
            return
        }
        if let idxA = stackWindows.firstIndex(of: a),
           let idxB = masterWindows.firstIndex(of: b) {
            stackWindows[idxA] = b
            masterWindows[idxB] = a
        }
    }

    // MARK: - Resize

    mutating func resizeSplit(at id: WindowID, delta: CGFloat) {
        // In master-stack, resize adjusts the master ratio
        if masterWindows.contains(id) {
            masterRatio = min(max(masterRatio + delta, 0.1), 0.9)
        } else if stackWindows.contains(id) {
            masterRatio = min(max(masterRatio - delta, 0.1), 0.9)
        }
    }

    // MARK: - Neighbor (geometric)

    func neighbor(of id: WindowID, direction: Direction, frames: LayoutResult) -> WindowID? {
        geometricNeighbor(of: id, direction: direction, frames: frames)
    }
}
