import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

// Measures real native controls in the production shell. Color/hover and the
// HTML comparison require separate visual review, not these geometry assertions.
@Suite("Provider visual geometry", .serialized)
@MainActor
struct ProviderVisualGeometryTests {
    @Test("configured model control stretches across the narrow card at the confirmed height")
    func modelControlGeometry() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let editor = ProviderCredentialEditor(loadedValue: "fixture-key")
        let controller = ManagementCenterWindowController(records: [], providerSettings: ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: ["fixture-vision"],
                                            selectedModelID: "fixture-vision", phase: .ready, failure: nil),
            configurations: [.deepSeek: ProviderConfiguration(models: [ProviderModelState(id: "fixture-vision")],
                                                              fetchedAt: Date(), selectedModelID: "fixture-vision")],
            currentProvider: .deepSeek,
            credentialEditor: editor, pendingModelID: .constant("fixture-vision"),
            onSelectProvider: { _ in }, onValidate: { _ in }, onRefresh: {}, onSelectModel: { _ in }
        ))
        controller.show(destination: .providerSettings)
        defer { controller.close() }
        let window = try #require(controller.window)
        window.setContentSize(NSSize(width: 920, height: 620))
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let picker = try #require(descendants(content).compactMap { $0 as? NSPopUpButton }
            .first { $0.itemTitles.contains("fixture-vision") })
        #expect(abs(picker.frame.height - 32) < 1)
        // 920-point content minus sidebar, page/card padding, Refresh and gap.
        #expect(picker.frame.width > 450)
    }

    @Test("native model selection follows refreshed items and cannot submit while read-only")
    func selectionAndRefresh() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let editor = ProviderCredentialEditor(loadedValue: "fixture-key")
        var selections: [String] = []
        func configuration(_ models: [String], selected: String?, locked: Bool = false) -> ProviderSettingsConfiguration {
            ProviderSettingsConfiguration(
                snapshot: ProviderSetupSnapshot(selectedProvider: .deepSeek, availableModelIDs: models,
                                                selectedModelID: selected, phase: selected == nil ? .selectingModel : .ready, failure: nil,
                                                isReadOnly: locked),
                configurations: [.deepSeek: ProviderConfiguration(models: models.map { ProviderModelState(id: $0) },
                                                                  fetchedAt: Date(), selectedModelID: selected)],
                credentialEditor: editor, pendingModelID: .constant(selected),
                onSelectProvider: { _ in }, onValidate: { _ in }, onRefresh: {},
                onSelectModel: { selections.append($0) }
            )
        }
        let controller = ManagementCenterWindowController(records: [], providerSettings:
            configuration(["fixture-vision", "fixture-other"], selected: "fixture-vision"))
        controller.show(destination: .providerSettings)
        defer { controller.close() }
        let content = try #require(controller.window?.contentView)
        func picker() throws -> NSPopUpButton {
            content.layoutSubtreeIfNeeded()
            return try #require(descendants(content).compactMap { $0 as? NSPopUpButton }.first)
        }
        let initial = try picker()
        #expect(initial.titleOfSelectedItem == "fixture-vision")
        initial.selectItem(withTitle: "fixture-other")
        initial.sendAction(initial.action, to: initial.target)
        #expect(selections == ["fixture-other"])

        controller.update(records: [], selectedRecordID: nil, selectedImage: nil, cleanupFailureCount: 0,
                          retention: .thirtyDays, settings: GeneralSettingsSnapshot(), providerSettings:
                            configuration(["fixture-refreshed"], selected: nil, locked: true))
        let locked = try picker()
        #expect(locked.itemTitles == ["Choose a model", "fixture-refreshed"])
        #expect(!locked.isEnabled)
        locked.selectItem(withTitle: "fixture-refreshed")
        locked.sendAction(locked.action, to: locked.target)
        #expect(selections == ["fixture-other"])

        controller.update(records: [], selectedRecordID: nil, selectedImage: nil, cleanupFailureCount: 0,
                          retention: .thirtyDays, settings: GeneralSettingsSnapshot(), providerSettings:
                            configuration(["fixture-refreshed"], selected: nil))
        let refreshed = try picker()
        #expect(refreshed.isEnabled)
        refreshed.selectItem(withTitle: "fixture-refreshed")
        refreshed.sendAction(refreshed.action, to: refreshed.target)
        #expect(selections == ["fixture-other", "fixture-refreshed"])
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
