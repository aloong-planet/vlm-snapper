import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Provider setup input state")
struct ProviderSetupInputStateTests {
    @Test("pasting an API key immediately enables validation")
    func pastedAPIKeyEnablesValidation() {
        var state = ProviderSetupInputState(selectedProvider: .deepSeek)

        state.updateAPIKey("sk-live-example")

        #expect(state.apiKey == "sk-live-example")
        #expect(state.canValidate(phase: .awaitingValidation))
        #expect(!state.canValidate(phase: .validating))
    }

    @Test("switching Provider clears only the previous Provider key draft")
    func providerSwitchClearsDraft() {
        var state = ProviderSetupInputState(selectedProvider: .deepSeek)
        state.updateAPIKey("sk-deepseek-example")

        state.prepareForProviderSelection(.deepSeek)
        #expect(state.apiKey == "sk-deepseek-example")

        state.prepareForProviderSelection(.openAI)
        #expect(state.selectedProvider == .openAI)
        #expect(state.apiKey.isEmpty)
        #expect(!state.canValidate(phase: .awaitingValidation))
    }
}
