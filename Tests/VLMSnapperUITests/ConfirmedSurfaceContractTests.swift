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
}
