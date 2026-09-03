import SwiftUI
import Testing
@testable import VLMSnapperUI

@Suite("Result workspace window", .serialized)
@MainActor
struct ResultWorkspaceWindowControllerTests {
    @Test("the workspace uses normal window ordering and content refresh does not present it")
    func normalWindowAndNonPresentingRefresh() {
        let controller = ResultWorkspaceWindowController(
            onClose: { .hide },
            onDiscardUnsaved: {}
        )

        #expect(controller.window?.level == .normal)
        controller.update(content: Text("Updated"))
        #expect(controller.window?.isVisible == false)
    }

    @Test("capture retires the visible workspace before running the capture action")
    func captureRetiresVisibleWorkspace() async throws {
        let controller = ResultWorkspaceWindowController(
            onClose: { .hide },
            onDiscardUnsaved: {}
        )
        let window = try #require(controller.window)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        var captureCount = 0

        controller.performAfterHidingForCapture {
            captureCount += 1
        }

        #expect(window.isVisible == false)
        #expect(captureCount == 0)
        for _ in 0..<10 where captureCount == 0 {
            await Task.yield()
        }
        #expect(captureCount == 1)
    }
}
