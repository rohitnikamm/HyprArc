import CoreGraphics
import Testing
@testable import HyprArc

private let screenRect = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let zeroGaps = GapConfig.zero

// MARK: - Insert / Remove

@Suite("AccordionLayout - Insert/Remove")
struct AccordionInsertRemoveTests {

    @Test("insertWindow appends when no focused")
    func insertAppends() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        #expect(layout.order == [1, 2, 3])
    }

    @Test("insertWindow places after focused")
    func insertAfterFocused() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: 1)
        #expect(layout.order == [1, 3, 2])
    }

    @Test("insertWindow ignores duplicates")
    func insertDedups() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(1, afterFocused: nil)
        #expect(layout.order == [1])
    }

    @Test("removeWindow drops from order")
    func removeDrops() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        layout.removeWindow(2)
        #expect(layout.order == [1, 3])
    }
}

// MARK: - calculateFrames

@Suite("AccordionLayout - calculateFrames")
struct AccordionFramesTests {

    @Test("Single window fills container")
    func singleWindowFillsContainer() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)
        #expect(result.frames[1] == screenRect)
    }

    @Test("Two windows: first has right-peek, last has left-peek (horizontal)")
    func twoWindowsHorizontal() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.setFocused(2)   // mru=last

        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)

        // First child: (lPad, rPad) = (0, padding)
        #expect(result.frames[1]?.minX == 0)
        #expect(result.frames[1]?.width == 1000 - 30)
        // Last child: (padding, 0)
        #expect(result.frames[2]?.minX == 30)
        #expect(result.frames[2]?.width == 1000 - 30)
        // Full height in horizontal
        #expect(result.frames[1]?.height == 800)
        #expect(result.frames[2]?.height == 800)
    }

    @Test("Three windows with middle focused: neighbors get 2×padding")
    func threeWindowsMiddleFocused() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        layout.setFocused(2)  // mruIndex = 1

        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)

        // index 0 is first AND mruIndex-1 → first case wins (0, padding)
        #expect(result.frames[1]?.minX == 0)
        #expect(result.frames[1]?.width == 970)
        // index 1 is focused: default (padding, padding)
        #expect(result.frames[2]?.minX == 30)
        #expect(result.frames[2]?.width == 1000 - 60)
        // index 2 is last AND mruIndex+1 → last case wins (padding, 0)
        #expect(result.frames[3]?.minX == 30)
        #expect(result.frames[3]?.width == 970)
    }

    @Test("Four windows with focus at index 1: neighbor at 2 gets 2×padding on left")
    func fourWindowsNeighborDoublePadding() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        layout.insertWindow(4, afterFocused: nil)
        layout.setFocused(2)  // mruIndex = 1

        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)

        // index 2 is mruIndex+1: (2*padding, 0)
        #expect(result.frames[3]?.minX == 60)
        #expect(result.frames[3]?.width == 940)
    }

    @Test("Vertical orientation applies padding to y/height")
    func verticalOrientation() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.orientation = .vertical
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.setFocused(2)

        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)

        // First: (0, padding) on y-axis
        #expect(result.frames[1]?.minY == 0)
        #expect(result.frames[1]?.height == 770)
        #expect(result.frames[1]?.width == 1000)
        // Last: (padding, 0) on y-axis
        #expect(result.frames[2]?.minY == 30)
        #expect(result.frames[2]?.height == 770)
        #expect(result.frames[2]?.width == 1000)
    }

    @Test("No focused defaults to last child as MRU")
    func noFocusedDefaultsToLast() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        // no setFocused → mruIndex = order.count - 1 = 2

        let result = layout.calculateFrames(in: screenRect, gaps: zeroGaps)

        // index 1 is mruIndex-1: (0, 2*padding)
        #expect(result.frames[2]?.minX == 0)
        #expect(result.frames[2]?.width == 1000 - 60)
    }
}

// MARK: - Neighbor / Swap / Resize

@Suite("AccordionLayout - Navigation")
struct AccordionNavigationTests {

    @Test("neighbor cycles forward on right (horizontal)")
    func neighborRightCycles() {
        var layout = AccordionLayout()
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        let frames = layout.calculateFrames(in: screenRect, gaps: zeroGaps)
        #expect(layout.neighbor(of: 1, direction: .right, frames: frames) == 2)
        #expect(layout.neighbor(of: 2, direction: .right, frames: frames) == 3)
        #expect(layout.neighbor(of: 3, direction: .right, frames: frames) == 1)  // wrap
    }

    @Test("neighbor cycles backward on left (horizontal)")
    func neighborLeftCycles() {
        var layout = AccordionLayout()
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        let frames = layout.calculateFrames(in: screenRect, gaps: zeroGaps)
        #expect(layout.neighbor(of: 1, direction: .left, frames: frames) == 3)   // wrap
        #expect(layout.neighbor(of: 2, direction: .left, frames: frames) == 1)
    }

    @Test("off-axis direction returns nil in horizontal")
    func neighborOffAxisNil() {
        var layout = AccordionLayout()
        layout.orientation = .horizontal
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        let frames = layout.calculateFrames(in: screenRect, gaps: zeroGaps)
        #expect(layout.neighbor(of: 1, direction: .up, frames: frames) == nil)
        #expect(layout.neighbor(of: 1, direction: .down, frames: frames) == nil)
    }

    @Test("swapWindows swaps positions")
    func swapSwapsPositions() {
        var layout = AccordionLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)
        layout.swapWindows(1, 3)
        #expect(layout.order == [3, 2, 1])
    }

    @Test("resizeSplit is a no-op (padding unchanged)")
    func resizeIsNoOp() {
        var layout = AccordionLayout()
        layout.padding = 30
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.resizeSplit(at: 1, delta: 0.1, axis: .horizontal, in: screenRect, gaps: zeroGaps)
        #expect(layout.padding == 30)
    }
}
