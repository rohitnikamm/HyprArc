import CoreGraphics
import Testing
@testable import HyprArc

/// Standard landscape screen rect for testing (1920x1080).
private let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

// MARK: - Insert Tests

@Suite("DwindleLayout - Insert")
struct DwindleInsertTests {

    @Test("Insert single window — root is a leaf")
    func insertSingleWindow() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)

        #expect(layout.windowIDs == [1])
    }

    @Test("Insert two windows — root is a split")
    func insertTwoWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        #expect(layout.windowIDs.count == 2)
        #expect(layout.windowIDs.contains(1))
        #expect(layout.windowIDs.contains(2))
    }

    @Test("Insert three windows — dwindle spiral")
    func insertThreeWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)
        layout.insertWindow(3, afterFocused: 2)

        #expect(layout.windowIDs.count == 3)
    }

    @Test("Insert four windows")
    func insertFourWindows() {
        var layout = DwindleLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: id > 1 ? id - 1 : nil)
        }

        #expect(layout.windowIDs.count == 4)
        for id: WindowID in 1...4 {
            #expect(layout.windowIDs.contains(id))
        }
    }

    @Test("Insert with nil focus — appends at last leaf")
    func insertWithNilFocus() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        #expect(layout.windowIDs.count == 2)
    }

    @Test("Insert with non-existent focus — falls back to last leaf")
    func insertWithBadFocus() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 999)

        #expect(layout.windowIDs.count == 2)
    }
}

// MARK: - Remove Tests

@Suite("DwindleLayout - Remove")
struct DwindleRemoveTests {

    @Test("Remove only window — tree becomes empty")
    func removeOnlyWindow() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.removeWindow(1)

        #expect(layout.windowIDs.isEmpty)
    }

    @Test("Remove from two-window tree — back to single leaf")
    func removeFromTwoWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)
        layout.removeWindow(1)

        #expect(layout.windowIDs == [2])
    }

    @Test("Remove second window from two-window tree")
    func removeSecondFromTwoWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)
        layout.removeWindow(2)

        #expect(layout.windowIDs == [1])
    }

    @Test("Remove from three-window tree — restructures correctly")
    func removeFromThreeWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)
        layout.insertWindow(3, afterFocused: 2)
        layout.removeWindow(2)

        #expect(layout.windowIDs.count == 2)
        #expect(layout.windowIDs.contains(1))
        #expect(layout.windowIDs.contains(3))
    }

    @Test("Remove non-existent window — no-op")
    func removeNonExistent() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.removeWindow(999)

        #expect(layout.windowIDs == [1])
    }

    @Test("Remove from empty tree — no-op")
    func removeFromEmpty() {
        var layout = DwindleLayout()
        layout.removeWindow(1)

        #expect(layout.windowIDs.isEmpty)
    }
}

// MARK: - Frame Calculation Tests

@Suite("DwindleLayout - Frame Calculation")
struct DwindleFrameTests {

    @Test("Single window fills screen minus outer gaps")
    func singleWindowFillsScreen() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)

        let gaps = GapConfig(inner: 5, outer: 10)
        let result = layout.calculateFrames(in: screenRect, gaps: gaps)

        let frame = result.frames[1]!
        #expect(frame.minX == 10)
        #expect(frame.minY == 10)
        #expect(frame.width == 1900)
        #expect(frame.height == 1060)
    }

    @Test("Single window with zero gaps fills entire screen")
    func singleWindowZeroGaps() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let frame = result.frames[1]!
        #expect(frame == screenRect)
    }

    @Test("Two windows split horizontally on landscape screen")
    func twoWindowsHorizontalSplit() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let frame1 = result.frames[1]!
        let frame2 = result.frames[2]!

        // On a landscape screen (1920 > 1080), split should be horizontal
        // First window on left, second on right
        #expect(frame1.minX < frame2.minX)
        #expect(frame1.height == frame2.height)
    }

    @Test("Two windows on portrait screen split vertically")
    func twoWindowsVerticalSplit() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let portraitRect = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let result = layout.calculateFrames(in: portraitRect, gaps: .zero)

        let frame1 = result.frames[1]!
        let frame2 = result.frames[2]!

        // On portrait (800 < 1200), split should be vertical
        #expect(frame1.minY < frame2.minY)
        #expect(frame1.width == frame2.width)
    }

    @Test("Three windows — dwindle pattern, non-overlapping")
    func threeWindowsNonOverlapping() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)
        layout.insertWindow(3, afterFocused: 2)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        #expect(result.frames.count == 3)

        // Verify no frames overlap
        let frames = Array(result.frames.values)
        for i in 0..<frames.count {
            for j in (i+1)..<frames.count {
                let intersection = frames[i].intersection(frames[j])
                #expect(intersection.isEmpty || intersection.width < 1 || intersection.height < 1)
            }
        }
    }

    @Test("Four windows — all have non-zero area")
    func fourWindowsAllHaveArea() {
        var layout = DwindleLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: id > 1 ? id - 1 : nil)
        }

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        #expect(result.frames.count == 4)
        for (_, frame) in result.frames {
            #expect(frame.width > 0)
            #expect(frame.height > 0)
        }
    }

    @Test("Gaps applied correctly between windows")
    func gapsAppliedCorrectly() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let gaps = GapConfig(inner: 10, outer: 20)
        let result = layout.calculateFrames(in: screenRect, gaps: gaps)

        let frame1 = result.frames[1]!
        let frame2 = result.frames[2]!

        // Outer gap on left edge
        #expect(frame1.minX == 20)
        // Inner gap between windows
        let gapBetween = frame2.minX - frame1.maxX
        #expect(abs(gapBetween - 10) < 1)
    }

    @Test("Empty layout returns empty frames")
    func emptyLayoutReturnsEmpty() {
        let layout = DwindleLayout()
        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        #expect(result.frames.isEmpty)
    }
}

// MARK: - Swap Tests

@Suite("DwindleLayout - Swap")
struct DwindleSwapTests {

    @Test("Swap two windows — positions exchange")
    func swapTwoWindows() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let beforeSwap = layout.calculateFrames(in: screenRect, gaps: .zero)
        let frame1Before = beforeSwap.frames[1]!
        let frame2Before = beforeSwap.frames[2]!

        layout.swapWindows(1, 2)

        let afterSwap = layout.calculateFrames(in: screenRect, gaps: .zero)
        let frame1After = afterSwap.frames[1]!
        let frame2After = afterSwap.frames[2]!

        // After swap, window 1 should be where window 2 was and vice versa
        #expect(abs(frame1After.minX - frame2Before.minX) < 1)
        #expect(abs(frame2After.minX - frame1Before.minX) < 1)
    }

    @Test("Swap in four-window layout — only swapped windows change")
    func swapInFourWindowLayout() {
        var layout = DwindleLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: id > 1 ? id - 1 : nil)
        }

        let before = layout.calculateFrames(in: screenRect, gaps: .zero)
        let frame3Before = before.frames[3]!
        let frame4Before = before.frames[4]!

        layout.swapWindows(1, 2)

        let after = layout.calculateFrames(in: screenRect, gaps: .zero)

        // Windows 3 and 4 should be unaffected
        #expect(abs(after.frames[3]!.minX - frame3Before.minX) < 1)
        #expect(abs(after.frames[4]!.minX - frame4Before.minX) < 1)
    }
}

// MARK: - Resize Tests

@Suite("DwindleLayout - Resize")
struct DwindleResizeTests {

    @Test("Resize positive delta — first window grows")
    func resizePositiveDelta() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let before = layout.calculateFrames(in: screenRect, gaps: .zero)
        let width1Before = before.frames[1]!.width

        layout.resizeSplit(at: 1, delta: 0.1)

        let after = layout.calculateFrames(in: screenRect, gaps: .zero)
        let width1After = after.frames[1]!.width

        #expect(width1After > width1Before)
    }

    @Test("Resize negative delta — first window shrinks")
    func resizeNegativeDelta() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let before = layout.calculateFrames(in: screenRect, gaps: .zero)
        let width1Before = before.frames[1]!.width

        layout.resizeSplit(at: 1, delta: -0.1)

        let after = layout.calculateFrames(in: screenRect, gaps: .zero)
        let width1After = after.frames[1]!.width

        #expect(width1After < width1Before)
    }

    @Test("Resize clamped at 0.1 minimum")
    func resizeClampedMin() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        // Try to resize way past the minimum
        layout.resizeSplit(at: 1, delta: -0.9)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)
        let frame1 = result.frames[1]!

        // Window should still have reasonable size (at least 10% of screen)
        #expect(frame1.width > screenRect.width * 0.05)
    }

    @Test("Resize clamped at 0.9 maximum")
    func resizeClampedMax() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        // Try to resize way past the maximum
        layout.resizeSplit(at: 1, delta: 0.9)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)
        let frame2 = result.frames[2]!

        // Second window should still have reasonable size
        #expect(frame2.width > screenRect.width * 0.05)
    }
}

// MARK: - Consistency Tests

@Suite("DwindleLayout - Consistency")
struct DwindleConsistencyTests {

    @Test("Insert then remove returns to previous state")
    func insertThenRemoveRestoresState() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let before = layout.calculateFrames(in: screenRect, gaps: .zero)

        layout.insertWindow(3, afterFocused: 2)
        layout.removeWindow(3)

        let after = layout.calculateFrames(in: screenRect, gaps: .zero)

        // Frames should be identical after insert+remove
        #expect(abs(before.frames[1]!.minX - after.frames[1]!.minX) < 1)
        #expect(abs(before.frames[2]!.minX - after.frames[2]!.minX) < 1)
    }

    @Test("All frames within screen bounds")
    func allFramesWithinBounds() {
        var layout = DwindleLayout()
        for id: WindowID in 1...5 {
            layout.insertWindow(id, afterFocused: id > 1 ? id - 1 : nil)
        }

        let gaps = GapConfig(inner: 5, outer: 10)
        let result = layout.calculateFrames(in: screenRect, gaps: gaps)

        for (_, frame) in result.frames {
            #expect(frame.minX >= 0)
            #expect(frame.minY >= 0)
            #expect(frame.maxX <= screenRect.maxX + 1)
            #expect(frame.maxY <= screenRect.maxY + 1)
        }
    }
}
