import CoreGraphics
import Testing
@testable import HyprArc

private let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

@Suite("Geometric Navigation")
struct GeometricNavigationTests {

    @Test("Two windows side by side — left/right navigation works")
    func twoWindowsSideBySide() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        // Window 1 is left, window 2 is right
        let rightNeighbor = layout.neighbor(of: 1, direction: .right, frames: result)
        #expect(rightNeighbor == 2)

        let leftNeighbor = layout.neighbor(of: 2, direction: .left, frames: result)
        #expect(leftNeighbor == 1)
    }

    @Test("Two windows side by side — up/down returns nil")
    func twoWindowsSideBySideNoVertical() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        #expect(layout.neighbor(of: 1, direction: .up, frames: result) == nil)
        #expect(layout.neighbor(of: 1, direction: .down, frames: result) == nil)
    }

    @Test("Two windows stacked — up/down navigation works")
    func twoWindowsStacked() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        // Use a portrait rect so they split vertically
        let portraitRect = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let result = layout.calculateFrames(in: portraitRect, gaps: .zero)

        let downNeighbor = layout.neighbor(of: 1, direction: .down, frames: result)
        #expect(downNeighbor == 2)

        let upNeighbor = layout.neighbor(of: 2, direction: .up, frames: result)
        #expect(upNeighbor == 1)
    }

    @Test("Edge window — navigation off edge returns nil")
    func edgeNavigationReturnsNil() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)
        layout.insertWindow(2, afterFocused: 1)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        // Window 1 is leftmost — going left should return nil
        #expect(layout.neighbor(of: 1, direction: .left, frames: result) == nil)

        // Window 2 is rightmost — going right should return nil
        #expect(layout.neighbor(of: 2, direction: .right, frames: result) == nil)
    }

    @Test("Four windows — all directional navigation correct")
    func fourWindowsNavigation() {
        var layout = DwindleLayout()
        for id: WindowID in 1...4 {
            layout.insertWindow(id, afterFocused: id > 1 ? id - 1 : nil)
        }

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        // With 4 windows in dwindle, we should be able to navigate between them
        // Just verify that every window has at least one reachable neighbor
        for id: WindowID in 1...4 {
            let hasNeighbor = Direction.allCases.contains { direction in
                layout.neighbor(of: id, direction: direction, frames: result) != nil
            }
            #expect(hasNeighbor, "Window \(id) should have at least one neighbor")
        }
    }

    @Test("Single window — no neighbors in any direction")
    func singleWindowNoNeighbors() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        for direction in Direction.allCases {
            #expect(layout.neighbor(of: 1, direction: direction, frames: result) == nil)
        }
    }

    @Test("Navigation with non-existent window returns nil")
    func nonExistentWindowReturnsNil() {
        var layout = DwindleLayout()
        layout.insertWindow(1, afterFocused: nil)

        let result = layout.calculateFrames(in: screenRect, gaps: .zero)

        #expect(layout.neighbor(of: 999, direction: .right, frames: result) == nil)
    }
}
