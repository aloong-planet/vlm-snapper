import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

// Signed-app acceptance verifies that capture excludes the open status-item
// popover before the controller retires it behind the frozen overlay.
@Suite("Ticket 12 menu bar interactions", .serialized)
@MainActor
struct Ticket12MenuBarInteractionTests {
    @Test("right mouse up opens the context action and other activations use the panel")
    func statusItemEventRouting() {
        #expect(
            MenuBarStatusItemInteractionRouter.route(eventType: .rightMouseUp)
                == .contextMenu
        )
        #expect(
            MenuBarStatusItemInteractionRouter.route(eventType: .leftMouseUp)
                == .primaryPanel
        )
        #expect(
            MenuBarStatusItemInteractionRouter.route(eventType: nil)
                == .primaryPanel
        )
    }

    @Test("the context menu contains only localized Quit and invokes the quit action")
    func contextMenuContract() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        defer {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        }
        var quitCount = 0
        let controller = MenuBarPanelController(
            content: EmptyView(),
            onQuit: { quitCount += 1 }
        )

        let item = try #require(controller.contextMenu.items.first)
        #expect(controller.contextMenu.items.count == 1)
        #expect(item.title == "Quit VLMSnapper")
        #expect(!item.isSeparatorItem)

        let action = try #require(item.action)
        #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
        #expect(quitCount == 1)

        VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        let chineseController = MenuBarPanelController(content: EmptyView(), onQuit: {})
        let chineseItem = try #require(chineseController.contextMenu.items.first)
        #expect(chineseController.contextMenu.items.count == 1)
        #expect(chineseItem.title == "\u{9000}\u{51FA} VLMSnapper")
    }

    @Test("every capture route enters application readiness handling immediately")
    func captureRouteActions() {
        var events: [String] = []
        let capture = { events.append("capture") }

        MenuCaptureActionHandler.perform(
            route: .configureProvider,
            performCapture: capture
        )
        MenuCaptureActionHandler.perform(
            route: .recoverPermission,
            performCapture: capture
        )
        MenuCaptureActionHandler.perform(
            route: .capture,
            performCapture: capture
        )

        #expect(events == ["capture", "capture", "capture"])
    }

}
