import AppKit
import CoreGraphics
import Foundation
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 13 confirmed surface contracts")
struct ConfirmedSurfaceContractTests {
    @Test("onboarding and attached sheets use the accepted dimensions")
    func setupSurfaceGeometry() {
        #expect(OnboardingMetrics.width == 760)
        #expect(OnboardingMetrics.minimumHeight == 540)
        #expect(OnboardingMetrics.rowCornerRadius == 9)
        #expect(ProviderSetupMetrics.width == 720)
        #expect(ProviderSetupMetrics.bodyHeight == 410)
        #expect(ProviderSetupMetrics.cornerRadius == 8)
        #expect(PermissionRecoveryMetrics.width == 520)
        #expect(PermissionRecoveryMetrics.cornerRadius == 8)
    }

    @Test("result and management shells use the accepted hierarchy geometry")
    func workspaceGeometry() {
        #expect(ResultWorkspaceMetrics.minimumSize == CGSize(width: 1_020, height: 620))
        #expect(ResultWorkspaceMetrics.headerHeight == 58)
        #expect(ResultWorkspaceMetrics.footerHeight == 50)
        #expect(ManagementCenterMetrics.defaultSize == CGSize(width: 1_200, height: 720))
        #expect(ManagementCenterMetrics.sidebarWidth == 218)
        #expect(ManagementCenterMetrics.titlebarHeight == 46)
    }

    @Test("provider rows preserve configuration state for non-selected providers")
    func providerRowState() {
        let snapshot = ProviderSetupSnapshot(
            selectedProvider: .deepSeek,
            availableModelIDs: [],
            selectedModelID: nil,
            phase: .awaitingValidation,
            failure: nil
        )
        let openAI = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-vision", visionCompatibility: .verified)],
            fetchedAt: Date(timeIntervalSince1970: 1),
            selectedModelID: "gpt-vision"
        )
        let presentation = ProviderSidebarPresentation(
            provider: .openAI,
            snapshot: snapshot,
            configurations: [.openAI: openAI]
        )

        #expect(presentation.isConfigured)
        #expect(presentation.detail == "gpt-vision")
    }
}

@Suite("Management center window contract", .serialized)
@MainActor
struct ManagementCenterWindowContractTests {
    // Integration gap: SwiftUI List double-click delivery and the disabled
    // rerun state for a missing screenshot require verification in the built app.
    @Test("the minimum applies to the complete content area")
    func minimumAppliesToContentArea() throws {
        let controller = ManagementCenterWindowController(records: [])
        let window = try #require(controller.window)

        #expect(window.contentMinSize == NSSize(width: 920, height: 620))

        window.setFrame(
            NSRect(origin: .zero, size: window.minSize),
            display: false
        )

        #expect(window.contentLayoutRect.width >= 920)
        #expect(window.contentLayoutRect.height >= 620)
    }

    @Test("capture retires the visible management center before continuing")
    func captureRetiresVisibleManagementCenter() async throws {
        let controller = ManagementCenterWindowController(records: [])
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

    @Test("history callbacks keep selection and opening as separate actions")
    func historyCallbacksSeparateSelectionAndOpening() {
        let id = UUID()
        var selectedID: UUID?
        var openedID: UUID?
        let callbacks = ManagementCenterCallbacks(
            onSelectRecord: { selectedID = $0 },
            onOpenRecord: { openedID = $0 }
        )

        callbacks.onSelectRecord(id)
        #expect(selectedID == id)
        #expect(openedID == nil)

        callbacks.onOpenRecord(id)
        #expect(openedID == id)
    }
}
