import Foundation
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Provider settings presentation")
struct ProviderSettingsPresentationTests {
    @Test("local input errors have specific localized hints")
    @MainActor
    func localAPIKeyErrorsHaveSpecificHints() {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        for (issue, hint) in [
            (ProviderAPIKeyInputIssue.empty, "Enter a key to validate"),
            (.containsNewline, "Remove the remaining line breaks from the API key before validating."),
            (.tooLong, "The API key is too long. Check for extra pasted content."),
        ] {
            let presentation = ProviderInlineCredentialPresentation(
                isConfigured: true, isSelected: true, isDirty: true, phase: .ready,
                hasAPIKey: issue != .empty, isReadOnly: false, inputIssue: issue
            )
            #expect(!presentation.canValidate)
            #expect(presentation.localInputHint == hint)
        }
    }

    @Test("inline credential states expose validation only when needed")
    func inlineCredentialStates() {
        let configured = ProviderInlineCredentialPresentation(
            isConfigured: true,
            isSelected: true,
            isDirty: false,
            phase: .ready,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(configured.status == .configured)
        #expect(!configured.showsValidation)
        #expect(!configured.canValidate)

        let edited = ProviderInlineCredentialPresentation(
            isConfigured: true,
            isSelected: true,
            isDirty: true,
            phase: .ready,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(edited.status == .pending)
        #expect(edited.showsValidation)
        #expect(edited.canValidate)

        let otherCard = ProviderInlineCredentialPresentation(
            isConfigured: true,
            isSelected: false,
            isDirty: true,
            phase: .ready,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(otherCard.status == .configured)
        #expect(!otherCard.showsValidation)

        let empty = ProviderInlineCredentialPresentation(
            isConfigured: false,
            isSelected: true,
            isDirty: false,
            phase: .awaitingValidation,
            hasAPIKey: false,
            isReadOnly: false
        )
        #expect(empty.status == .notConfigured)
        #expect(empty.showsValidation)
        #expect(!empty.canValidate)

        let awaitingModel = ProviderInlineCredentialPresentation(
            isConfigured: true,
            isSelected: true,
            isDirty: false,
            phase: .selectingModel,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(awaitingModel.status == .configured)
        #expect(!awaitingModel.showsValidation)
        #expect(!awaitingModel.canValidate)
    }

    @Test("validation and failure override the inline credential status")
    func validationAndFailureOverrideStatus() {
        let validating = ProviderInlineCredentialPresentation(
            isConfigured: false,
            isSelected: true,
            isDirty: true,
            phase: .validating,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(validating.status == .validating)
        #expect(!validating.canValidate)

        let failed = ProviderInlineCredentialPresentation(
            isConfigured: false,
            isSelected: true,
            isDirty: true,
            phase: .failed,
            hasAPIKey: true,
            isReadOnly: false
        )
        #expect(failed.status == .failed)
        #expect(failed.canValidate)
    }

    @Test("Provider card distinguishes validated credentials awaiting a model")
    func providerCardDistinguishesPendingModel() {
        let configuration = ProviderConfiguration(
            models: [ProviderModelState(id: "vision-model")],
            fetchedAt: Date(timeIntervalSince1970: 1),
            selectedModelID: nil
        )
        let pendingModel = ProviderInlineCardPresentation(
            provider: .deepSeek,
            snapshot: ProviderSetupSnapshot(
                selectedProvider: .deepSeek,
                availableModelIDs: ["vision-model"],
                selectedModelID: nil,
                phase: .selectingModel,
                failure: nil
            ),
            configuration: configuration,
            isDirty: false
        )
        let configuredOtherProvider = ProviderInlineCardPresentation(
            provider: .openAI,
            snapshot: ProviderSetupSnapshot(
                selectedProvider: .deepSeek,
                availableModelIDs: ["vision-model"],
                selectedModelID: nil,
                phase: .selectingModel,
                failure: nil
            ),
            configuration: ProviderConfiguration(
                models: [ProviderModelState(id: "gpt-vision")],
                fetchedAt: Date(timeIntervalSince1970: 1),
                selectedModelID: "gpt-vision"
            ),
            isDirty: false
        )

        #expect(pendingModel.status == .pendingModel)
        #expect(configuredOtherProvider.status == .ready)
    }

    @Test("expanded Provider preference is explicit target then current then DeepSeek")
    func expandedProviderPreference() {
        #expect(
            ProviderSettingsInitialSelection.resolve(
                explicitTarget: .gemini,
                currentProvider: .openAI
            ) == .gemini
        )
        #expect(
            ProviderSettingsInitialSelection.resolve(
                explicitTarget: nil,
                currentProvider: .openAI
            ) == .openAI
        )
        #expect(
            ProviderSettingsInitialSelection.resolve(
                explicitTarget: nil,
                currentProvider: nil
            ) == .deepSeek
        )
    }

    @Test("onboarding return is consumed by completion or early close exactly once")
    func onboardingReturnIsConsumedExactlyOnce() {
        var completionFlow = ProviderSettingsReturnContext()
        completionFlow.beginFromOnboarding()
        let completionReturned = completionFlow.consumeAfterModelSelection()
        let completionCloseReturned = completionFlow.consumeAfterWindowClose()
        #expect(completionReturned)
        #expect(!completionCloseReturned)

        var closeFlow = ProviderSettingsReturnContext()
        closeFlow.beginFromOnboarding()
        let closeReturned = closeFlow.consumeAfterWindowClose()
        let closeCompletionReturned = closeFlow.consumeAfterModelSelection()
        #expect(closeReturned)
        #expect(!closeCompletionReturned)

        var ordinaryFlow = ProviderSettingsReturnContext()
        let ordinaryCompletionReturned = ordinaryFlow.consumeAfterModelSelection()
        let ordinaryCloseReturned = ordinaryFlow.consumeAfterWindowClose()
        #expect(!ordinaryCompletionReturned)
        #expect(!ordinaryCloseReturned)
    }
}
