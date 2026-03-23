import CoreGraphics
import Testing
@testable import HyprArc

private let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

// MARK: - Insert Tests

@Suite("MasterStackLayout - Insert")
struct MasterStackInsertTests {

    @Test("First window becomes master")
    func firstWindowIsMaster() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)

        #expect(layout.masterWindows == [1])
        #expect(layout.stackWindows.isEmpty)
    }

    @Test("Second window joins stack")
    func secondWindowJoinsStack() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        #expect(layout.masterWindows == [1])
        #expect(layout.stackWindows == [2])
    }

    @Test("Multiple windows stack in order")
    func multipleWindowsStack() {
        var layout = MasterStackLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: nil)
        }

        #expect(layout.masterWindows == [1])
        #expect(layout.stackWindows == [2, 3, 4])
        #expect(layout.windowIDs.count == 4)
    }
}

// MARK: - Remove Tests

@Suite("MasterStackLayout - Remove")
struct MasterStackRemoveTests {

    @Test("Remove only window — empty")
    func removeOnlyWindow() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.removeWindow(1)

        #expect(layout.windowIDs.isEmpty)
    }

    @Test("Remove master — first stack auto-promotes")
    func removeMasterAutoPromotes() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)

        layout.removeWindow(1)

        #expect(layout.masterWindows == [2])
        #expect(layout.stackWindows == [3])
    }

    @Test("Remove stack window — master unchanged")
    func removeStackWindow() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)

        layout.removeWindow(2)

        #expect(layout.masterWindows == [1])
        #expect(layout.stackWindows == [3])
    }

    @Test("Remove non-existent — no-op")
    func removeNonExistent() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.removeWindow(999)

        #expect(layout.windowIDs == [1])
    }
}

// MARK: - Promote / Demote Tests

@Suite("MasterStackLayout - Promote/Demote")
struct MasterStackPromoteDemoteTests {

    @Test("Promote stack window to master")
    func promoteToMaster() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)

        layout.promote(3)

        #expect(layout.masterWindows.contains(3))
        #expect(!layout.stackWindows.contains(3))
    }

    @Test("Demote master window to stack — with 3 windows")
    func demoteToStack() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)

        layout.demote(1)

        // First stack window (1, inserted at front) auto-promotes to master
        // since master was emptied. Then stack has [2, 3] minus the promoted one.
        #expect(layout.masterWindows.count == 1)
        #expect(!layout.stackWindows.contains(layout.masterWindows[0]))
        #expect(layout.windowIDs.count == 3)
    }
}

// MARK: - Frame Calculation Tests

@Suite("MasterStackLayout - Frame Calculation")
struct MasterStackFrameTests {

    @Test("Single window fills screen minus gaps")
    func singleWindowFillsScreen() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)

        let gaps = GapConfig(inner: 5, outer: 10)
        let result = layout.calculateFrames(in: screenRect, gaps: gaps)

        let frame = result.frames[1]!
        #expect(frame.minX == 10)
        #expect(frame.minY == 10)
        #expect(frame.width == 1900)
        #expect(frame.height == 1060)
    }

    @Test("Two windows — master left 55%, stack right 45%")
    func twoWindowsMasterStack() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let masterFrame = result.frames[1]!
        let stackFrame = result.frames[2]!

        // Master on left, stack on right
        #expect(masterFrame.minX < stackFrame.minX)
        // Master should be ~55% width
        #expect(masterFrame.width > stackFrame.width)
    }

    @Test("Three windows — master left, two stacked right")
    func threeWindowsStacked() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)
        layout.insertWindow(3, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let masterFrame = result.frames[1]!
        let stack2 = result.frames[2]!
        let stack3 = result.frames[3]!

        // Master on left
        #expect(masterFrame.minX < stack2.minX)
        // Stack windows stacked vertically
        #expect(stack2.minY < stack3.minY)
        // Stack windows have equal height
        #expect(abs(stack2.height - stack3.height) < 1)
    }

    @Test("All frames non-overlapping")
    func framesNonOverlapping() {
        var layout = MasterStackLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: nil)
        }

        let result = layout.calculateFrames(in: screenRect, gaps: GapConfig(inner: 5, outer: 10))
        let frames = Array(result.frames.values)

        for i in 0..<frames.count {
            for j in (i+1)..<frames.count {
                let intersection = frames[i].intersection(frames[j])
                #expect(intersection.isEmpty || intersection.width < 1 || intersection.height < 1)
            }
        }
    }

    @Test("Empty layout returns empty")
    func emptyLayout() {
        let layout = MasterStackLayout()
        let result = layout.calculateFrames(in: screenRect, gaps: .zero)
        #expect(result.frames.isEmpty)
    }

    @Test("Right orientation — master on right")
    func rightOrientation() {
        var layout = MasterStackLayout()
        layout.orientation = .right
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let masterFrame = result.frames[1]!
        let stackFrame = result.frames[2]!

        // Master on right
        #expect(masterFrame.minX > stackFrame.minX)
    }

    @Test("Top orientation — master on top")
    func topOrientation() {
        var layout = MasterStackLayout()
        layout.orientation = .top
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        let masterFrame = result.frames[1]!
        let stackFrame = result.frames[2]!

        // Master on top
        #expect(masterFrame.minY < stackFrame.minY)
    }
}

// MARK: - Swap Tests

@Suite("MasterStackLayout - Swap")
struct MasterStackSwapTests {

    @Test("Swap master with stack — positions exchange")
    func swapMasterWithStack() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        layout.swapWindows(1, 2)

        #expect(layout.masterWindows == [2])
        #expect(layout.stackWindows == [1])
    }

    @Test("Swap within stack")
    func swapWithinStack() {
        var layout = MasterStackLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: nil)
        }

        layout.swapWindows(2, 4)

        #expect(layout.stackWindows[0] == 4)
        #expect(layout.stackWindows[2] == 2)
    }
}

// MARK: - Resize Tests

@Suite("MasterStackLayout - Resize")
struct MasterStackResizeTests {

    @Test("Resize master — ratio increases")
    func resizeMasterGrows() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        let before = layout.masterRatio
        layout.resizeSplit(at: 1, delta: 0.1)

        #expect(layout.masterRatio > before)
    }

    @Test("Resize stack — ratio decreases (master shrinks)")
    func resizeStackShrinksMaster() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        let before = layout.masterRatio
        layout.resizeSplit(at: 2, delta: 0.1)

        #expect(layout.masterRatio < before)
    }

    @Test("Resize clamped at boundaries")
    func resizeClamped() {
        var layout = MasterStackLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: nil)

        layout.resizeSplit(at: 1, delta: 0.9)
        #expect(layout.masterRatio <= 0.9)

        layout.resizeSplit(at: 1, delta: -0.9)
        #expect(layout.masterRatio >= 0.1)
    }
}
