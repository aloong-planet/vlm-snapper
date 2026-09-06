import Foundation
import Security
import Testing
@testable import VLMSnapperCore

@Suite("Provider setup session")
struct ProviderSetupSessionTests {
    @Test("returning after validation failure shows its original failure")
    func returningAfterValidationFailure() async {
        let boundary = SuspendedValidationModelLister(failFirst: true)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        let validation = Task { await session.validate(apiKey: "candidate") }
        await boundary.waitUntilStarted()
        await session.selectProvider(.openAI)
        await boundary.finish()
        await validation.value
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .invalidConfiguration)
    }

    @Test("a submitted key keeps its original Provider when dispatch occurs after a card switch")
    func submittedValidationUsesExplicitProvider() async {
        let boundary = SuspendedValidationModelLister(failFirst: false, suspendFirst: false)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        await session.selectProvider(.openAI)
        await session.validate(apiKey: " exact-key\t", for: .deepSeek)
        #expect(await boundary.providers == [.deepSeek])
        #expect(await boundary.keys == [" exact-key\t"])
        #expect(await session.snapshot().selectedProvider == .openAI)
        #expect(await session.snapshot().availableModelIDs.isEmpty)
        #expect(await session.snapshot().phase == .awaitingValidation)
    }

    @Test("a pending validation ignores duplicates and releases its slot after success or failure", arguments: [false, true])
    func pendingValidationSuppressesDuplicates(failFirst: Bool) async {
        let boundary = SuspendedValidationModelLister(failFirst: failFirst)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        let first = Task { await session.validate(apiKey: "first-key") }
        await boundary.waitUntilStarted()
        await session.validate(apiKey: "duplicate-key")
        await session.selectProvider(.openAI)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .validating)
        await session.validate(apiKey: "another-duplicate")
        #expect(await boundary.keys == ["first-key"])
        await boundary.finish()
        await first.value
        #expect(await session.snapshot().phase == (failFirst ? .failed : .selectingModel))
        await session.validate(apiKey: "next-key")
        #expect(await boundary.keys == ["first-key", "next-key"])
    }

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

private actor SuspendedValidationModelLister: ProviderModelListing {
    private let failFirst: Bool
    private let suspendFirst: Bool
    private(set) var keys: [String] = []
    private(set) var providers: [ProviderID] = []
    private var pending: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(failFirst: Bool, suspendFirst: Bool = true) {
        self.failFirst = failFirst
        self.suspendFirst = suspendFirst
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        keys.append(apiKey)
        providers.append(provider)
        if keys.count == 1 && suspendFirst {
            await withCheckedContinuation { continuation in
                pending = continuation
                for waiter in startWaiters { waiter.resume() }
                startWaiters.removeAll()
            }
            if failFirst { throw ProviderModelListError.authenticationRejected }
        }
        return ["model"]
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() { pending?.resume(); pending = nil }
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

private func makeCoordinator(modelLister: any ProviderModelListing) -> ProviderConfigurationCoordinator {
    let storage = SessionTestStorage()
    return ProviderConfigurationCoordinator(
        modelLister: modelLister, credentialStore: storage, metadataStore: storage
    )
}

// In-memory substitutes for external Keychain and metadata persistence only.
private actor SessionTestStorage: ProviderCredentialStoring, ProviderMetadataStoring {
    private var credentials: [ProviderID: ProviderCredential] = [:]
    private var state = ProviderMetadataState()

    func credential(for provider: ProviderID) -> ProviderCredential? { credentials[provider] }
    func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) {
        credentials[provider] = credential
    }
    func deleteCredential(for provider: ProviderID) { credentials[provider] = nil }
    func load() -> ProviderMetadataState { state }
    func save(_ state: ProviderMetadataState) { self.state = state }
}
