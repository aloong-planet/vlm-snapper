import Foundation
import Security
import Testing
@testable import VLMSnapperCore

@Suite("Provider setup session")
struct ProviderSetupSessionTests {
    @Test("validation reveals the complete model list without choosing a model")
    func validationRevealsModelsWithoutSelection() async {
        let boundary = ProviderConfigurationBoundaryProbe(
            validationResult: ProviderConfiguration(
                models: [
                    ProviderModelState(id: "gemini-2.5-flash"),
                    ProviderModelState(id: "gemini-2.5-pro"),
                ],
                fetchedAt: Date(),
                selectedModelID: nil
            )
        )
        let session = ProviderSetupSession(
            selectedProvider: .gemini,
            boundary: boundary
        )

        await session.validate(apiKey: "candidate-secret")
        let snapshot = await session.snapshot()

        #expect(snapshot.availableModelIDs == ["gemini-2.5-flash", "gemini-2.5-pro"])
        #expect(snapshot.selectedModelID == nil)
        #expect(snapshot.phase == .selectingModel)
        #expect(!snapshot.canFinish)
        #expect(await boundary.validatedKeys == ["candidate-secret"])
    }

    @Test("selecting a model enables Done without replacing the current provider")
    func selectingModelEnablesDone() async {
        let boundary = ProviderConfigurationBoundaryProbe(
            validationResult: ProviderConfiguration(
                models: [ProviderModelState(id: "gpt-4.1")],
                fetchedAt: Date(),
                selectedModelID: nil
            )
        )
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: boundary
        )
        await session.validate(apiKey: "candidate-secret")

        await session.selectModel("gpt-4.1")
        let snapshot = await session.snapshot()

        #expect(snapshot.selectedModelID == "gpt-4.1")
        #expect(snapshot.phase == .ready)
        #expect(snapshot.canFinish)
        #expect(await boundary.selectedModels == ["gpt-4.1"])
    }

    @Test("selecting another provider clears only transient presentation state")
    func selectingProviderClearsTransientState() async {
        let boundary = ProviderConfigurationBoundaryProbe(
            validationResult: ProviderConfiguration(
                models: [ProviderModelState(id: "gpt-4.1")],
                fetchedAt: Date(),
                selectedModelID: nil
            )
        )
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: boundary
        )
        await session.validate(apiKey: "candidate-secret")

        await session.selectProvider(.deepSeek)
        let snapshot = await session.snapshot()

        #expect(snapshot.selectedProvider == .deepSeek)
        #expect(snapshot.availableModelIDs.isEmpty)
        #expect(snapshot.phase == .awaitingValidation)
    }

    @Test("a stale model selection cannot replace the newly selected provider")
    func staleSelectionCannotReplaceSelectedProvider() async {
        let boundary = SuspendedProviderConfigurationBoundaryProbe()
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: boundary
        )

        let selection = Task {
            await session.selectModel("gpt-4.1")
        }
        await boundary.waitUntilSelectionStarts()
        await session.selectProvider(.gemini)
        await boundary.finishSelection()
        await selection.value

        #expect(await session.snapshot().selectedProvider == .gemini)
    }

    @Test("read-only activity state permits viewing another Provider but blocks configuration mutations")
    func readOnlyStateBlocksConfigurationMutations() async {
        let boundary = ProviderConfigurationBoundaryProbe(
            validationResult: ProviderConfiguration(
                models: [ProviderModelState(id: "gpt-4.1")],
                fetchedAt: Date(),
                selectedModelID: nil
            )
        )
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: boundary
        )

        await session.setReadOnly(true)
        await session.validate(apiKey: "candidate-secret")
        await session.refreshModels()
        await session.selectModel("gpt-4.1")
        await session.selectProvider(.gemini)

        #expect(await session.snapshot().isReadOnly)
        #expect(await session.snapshot().selectedProvider == .gemini)
        #expect(await boundary.validatedKeys.isEmpty)
        #expect(await boundary.selectedModels.isEmpty)
    }

    @Test("a rejected API key is reported as invalid credentials")
    func rejectedAPIKeyIsReportedAsInvalidCredentials() async {
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: FailingProviderBoundary(
                error: ProviderModelListError.authenticationRejected
            )
        )

        await session.validate(apiKey: "rejected-secret")
        let snapshot = await session.snapshot()

        #expect(snapshot.phase == .failed)
        #expect(snapshot.failure == .invalidConfiguration)
    }

    @Test("a Provider outage is not reported as invalid credentials")
    func providerOutageIsNotReportedAsInvalidCredentials() async {
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: FailingProviderBoundary(
                error: ProviderModelListError.requestRejected(statusCode: 503)
            )
        )

        await session.validate(apiKey: "candidate-secret")
        let snapshot = await session.snapshot()

        #expect(snapshot.phase == .failed)
        #expect(snapshot.failure == .unavailable)
    }

    @Test("a Keychain write failure is reported as local secure storage")
    func keychainWriteFailureIsReportedAsLocalSecureStorage() async {
        let session = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: FailingProviderBoundary(
                error: AppleKeychainError.unexpectedStatus(errSecMissingEntitlement)
            )
        )

        await session.validate(apiKey: "candidate-secret")
        let snapshot = await session.snapshot()

        #expect(snapshot.phase == .failed)
        #expect(snapshot.failure == .secureStorage)
    }
}

private actor FailingProviderBoundary: ProviderSetupConfiguring {
    let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func configurationState() -> ProviderMetadataState {
        ProviderMetadataState()
    }

    func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) throws -> ProviderConfiguration {
        throw error
    }

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }
}

private actor ProviderConfigurationBoundaryProbe: ProviderSetupConfiguring {
    let validationResult: ProviderConfiguration
    private(set) var validatedKeys: [String] = []
    private(set) var selectedModels: [String] = []

    init(validationResult: ProviderConfiguration) {
        self.validationResult = validationResult
    }

    func configurationState() -> ProviderMetadataState {
        ProviderMetadataState()
    }

    func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) -> ProviderConfiguration {
        validatedKeys.append(apiKey)
        return validationResult
    }

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        validationResult
    }

    func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) -> ProviderConfiguration {
        selectedModels.append(modelID)
        return ProviderConfiguration(
            models: validationResult.models,
            fetchedAt: validationResult.fetchedAt,
            selectedModelID: modelID
        )
    }

}

private actor SuspendedProviderConfigurationBoundaryProbe: ProviderSetupConfiguring {
    private var selectionStarted = false
    private var selectionContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func configurationState() -> ProviderMetadataState {
        ProviderMetadataState()
    }

    func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) async -> ProviderConfiguration {
        selectionStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            selectionContinuation = continuation
        }
        return ProviderConfiguration(
            models: [ProviderModelState(id: modelID)],
            fetchedAt: Date(),
            selectedModelID: modelID
        )
    }

    func waitUntilSelectionStarts() async {
        guard !selectionStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishSelection() {
        selectionContinuation?.resume()
        selectionContinuation = nil
    }
}
