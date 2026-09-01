import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

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

    @Test("a visible panel defers capture until the close callback")
    func visiblePanelDefersActionUntilClose() {
        var isPanelShown = true
        var closeCount = 0
        var events: [String] = []
        let coordinator = MenuBarPanelDismissalCoordinator(
            isPanelShown: { isPanelShown },
            requestClose: { closeCount += 1 }
        )

        coordinator.performAfterDismissing {
            events.append("capture")
        }

        #expect(closeCount == 1)
        #expect(events.isEmpty)

        isPanelShown = false
        coordinator.panelDidClose()

        #expect(events == ["capture"])
    }

    @Test("a hidden panel performs capture immediately and close callbacks are idempotent")
    func hiddenPanelPerformsActionImmediately() {
        var closeCount = 0
        var captureCount = 0
        let coordinator = MenuBarPanelDismissalCoordinator(
            isPanelShown: { false },
            requestClose: { closeCount += 1 }
        )

        coordinator.performAfterDismissing {
            captureCount += 1
        }
        coordinator.panelDidClose()
        coordinator.panelDidClose()

        #expect(closeCount == 0)
        #expect(captureCount == 1)
    }

    @Test("every capture route dismisses the panel before application readiness handling")
    func captureRouteActions() {
        var events: [String] = []
        let captureAfterDismissal = { events.append("capture-after-dismissal") }

        MenuCaptureActionHandler.perform(
            route: .configureProvider,
            captureAfterPanelDismissal: captureAfterDismissal
        )
        MenuCaptureActionHandler.perform(
            route: .recoverPermission,
            captureAfterPanelDismissal: captureAfterDismissal
        )
        MenuCaptureActionHandler.perform(
            route: .capture,
            captureAfterPanelDismissal: captureAfterDismissal
        )

        #expect(
            events == [
                "capture-after-dismissal",
                "capture-after-dismissal",
                "capture-after-dismissal",
            ]
        )
    }

}
