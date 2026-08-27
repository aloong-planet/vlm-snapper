import CoreGraphics
import Testing
@testable import VLMSnapperUI

@Suite("Capture toolbar placement")
struct ToolbarPlacementTests {
    @Test("the toolbar is left aligned exactly four points below the selection")
    func toolbarIsFourPointsBelowSelection() {
        let selection = CGRect(x: 120, y: 300, width: 400, height: 200)

        let origin = CaptureToolbarPlacement.origin(
            selectionFrame: selection,
            toolbarSize: CGSize(width: 320, height: 31),
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )

        #expect(origin.x == selection.minX)
        #expect(selection.minY - (origin.y + 31) == 4)
    }

    @Test("a toolbar that would leave the screen moves above the selection")
    func toolbarMovesAboveAtBottomEdge() {
        let selection = CGRect(x: 10, y: 8, width: 200, height: 100)

        let origin = CaptureToolbarPlacement.origin(
            selectionFrame: selection,
            toolbarSize: CGSize(width: 300, height: 31),
            visibleScreenFrame: CGRect(x: 0, y: 0, width: 500, height: 400)
        )

        #expect(origin.y == selection.maxY + 4)
        #expect(origin.x == 10)
    }

    @Test("a toolbar wider than the screen keeps its leading edge visible")
    func wideToolbarKeepsLeadingEdgeVisible() {
        let screen = CGRect(x: 40, y: 20, width: 280, height: 400)

        let origin = CaptureToolbarPlacement.origin(
            selectionFrame: CGRect(x: 90, y: 180, width: 180, height: 100),
            toolbarSize: CGSize(width: 360, height: 31),
            visibleScreenFrame: screen
        )

        #expect(origin.x == screen.minX)
    }
}
