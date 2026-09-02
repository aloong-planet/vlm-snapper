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
}
