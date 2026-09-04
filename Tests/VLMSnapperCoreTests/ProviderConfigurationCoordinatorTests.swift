import Foundation
import Testing
@testable import VLMSnapperCore

// Request integration for unavailable models is covered when the provider request
// pipeline is introduced; this suite owns the one-refresh decision primitive.
@Suite("Provider configuration coordinator")
struct ProviderConfigurationCoordinatorTests {
    @Test("one model-unavailable attempt can claim at most one list refresh")
    func modelUnavailableAttemptClaimsOneRefresh() {
        var gate = ModelUnavailableRefreshGate()

        let firstClaim = gate.claimRefresh()
        let secondClaim = gate.claimRefresh()
        #expect(firstClaim)
        #expect(!secondClaim)
    }

    @Test("a complete model list is saved with the validated key")
    func completeModelListIsSavedWithValidatedKey() async throws {
        let credentialStore = MemoryCredentialStore()
        let metadataStore = MemoryMetadataStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["gpt-4o", "gpt-4.1"]),
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 1_787_731_200) }
        )

        let configuration = try await coordinator.validateAndSaveKey(
            "candidate-secret",
            for: .openAI
        )

        #expect(
            configuration == ProviderConfiguration(
                models: [
                    ProviderModelState(id: "gpt-4o"),
                    ProviderModelState(id: "gpt-4.1"),
                ],
                fetchedAt: Date(timeIntervalSince1970: 1_787_731_200),
                selectedModelID: nil
            )
        )
        #expect(try await credentialStore.credential(for: .openAI)?.apiKey == "candidate-secret")
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == configuration)
        #expect(state.pendingReplacements[.openAI] == nil)
    }

    @Test("the saved API key can be loaded for inline editing")
    func savedAPIKeyCanBeLoadedForInlineEditing() async throws {
        let credentialStore = MemoryCredentialStore(
            credentials: [
                .deepSeek: ProviderCredential(generation: UUID(), apiKey: "saved-secret"),
            ]
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: credentialStore,
            metadataStore: MemoryMetadataStore()
        )

        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-secret")
        #expect(try await coordinator.apiKey(for: .gemini) == nil)
    }

    @Test("a replacement credential write failure does not restore the previous configuration")
    func credentialWriteFailureDoesNotRestorePreviousConfiguration() async throws {
        let previousCredential = ProviderCredential(
            generation: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            apiKey: "previous-secret"
        )
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4o", visionCompatibility: .verified)],
            fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
            selectedModelID: "gpt-4o"
        )
        let initialState = ProviderMetadataState(
            configurations: [.openAI: previousConfiguration],
            currentProvider: .openAI
        )
        let credentialStore = MemoryCredentialStore(
            credentials: [.openAI: previousCredential],
            replaceError: BoundaryError.credentialWriteFailed
        )
        let metadataStore = MemoryMetadataStore(state: initialState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["gpt-4.1"]),
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            makeGeneration: {
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
            }
        )

        do {
            _ = try await coordinator.validateAndSaveKey("candidate-secret", for: .openAI)
            Issue.record("Expected the credential write to fail")
        } catch {
            #expect(error as? BoundaryError == .credentialWriteFailed)
        }

        #expect(try await credentialStore.credential(for: .openAI) == nil)
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == nil)
        #expect(state.currentProvider == nil)
        #expect(state.pendingReplacements[.openAI] == nil)
    }

    @Test("replacing a current provider preserves an available model and current selection")
    func replacementPreservesAvailableModelAndCurrentProvider() async throws {
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1", visionCompatibility: .verified)],
            fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
            selectedModelID: "gpt-4.1"
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(
                configurations: [.openAI: previousConfiguration],
                currentProvider: .openAI
            )
        )
        let credentialStore = MemoryCredentialStore(
            credentials: [
                .openAI: ProviderCredential(generation: UUID(), apiKey: "previous-secret"),
            ]
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["gpt-4.1", "gpt-4o"]),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )

        let replacement = try await coordinator.validateAndSaveKey(
            "replacement-secret",
            for: .openAI
        )

        #expect(replacement.selectedModelID == "gpt-4.1")
        #expect(try await credentialStore.credential(for: .openAI)?.apiKey == "replacement-secret")
        #expect(try await metadataStore.load().currentProvider == .openAI)
    }

    @Test("startup reconciliation commits metadata when the new credential is durable")
    func reconciliationCommitsMetadataForDurableNewCredential() async throws {
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "old-model")],
            fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
            selectedModelID: "old-model"
        )
        let replacementConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "new-model")],
            fetchedAt: Date(timeIntervalSince1970: 1_787_700_000),
            selectedModelID: nil
        )
        let previousGeneration = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let nextGeneration = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let pendingState = ProviderMetadataState(
            configurations: [.gemini: previousConfiguration],
            pendingReplacements: [
                .gemini: PendingProviderReplacement(
                    previousGeneration: previousGeneration,
                    nextGeneration: nextGeneration,
                    configuration: replacementConfiguration
                ),
            ]
        )
        let credentialStore = MemoryCredentialStore(
            credentials: [
                .gemini: ProviderCredential(generation: nextGeneration, apiKey: "new-secret"),
            ]
        )
        let metadataStore = MemoryMetadataStore(state: pendingState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )

        let reconciled = try await coordinator.reconcilePendingReplacements()

        #expect(reconciled.configurations[.gemini] == replacementConfiguration)
        #expect(reconciled.pendingReplacements[.gemini] == nil)
        #expect(try await metadataStore.load() == reconciled)
    }

    @Test("opening provider settings refreshes only a missing or 24-hour-old cache")
    func settingsRefreshRequirementUsesTwentyFourHourBoundary() async throws {
        let referenceDate = Date(timeIntervalSince1970: 1_787_731_200)
        let freshConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gemini-2.5-flash")],
            fetchedAt: referenceDate.addingTimeInterval(-(24 * 60 * 60) + 1),
            selectedModelID: nil
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(configurations: [.gemini: freshConfiguration])
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(),
            metadataStore: metadataStore,
            now: { referenceDate }
        )

        #expect(try await coordinator.shouldRefreshModelsOnSettingsOpen(for: .openAI))
        #expect(!(try await coordinator.shouldRefreshModelsOnSettingsOpen(for: .gemini)))

        let staleConfiguration = ProviderConfiguration(
            models: freshConfiguration.models,
            fetchedAt: referenceDate.addingTimeInterval(-(24 * 60 * 60)),
            selectedModelID: nil
        )
        try await metadataStore.save(
            ProviderMetadataState(configurations: [.gemini: staleConfiguration])
        )
        #expect(try await coordinator.shouldRefreshModelsOnSettingsOpen(for: .gemini))
    }

    @Test("a successful refresh replaces the cache and clears a missing selection")
    func refreshReplacesCacheAndClearsMissingSelection() async throws {
        let credential = ProviderCredential(generation: UUID(), apiKey: "saved-secret")
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "old-model", visionCompatibility: .verified)],
            fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
            selectedModelID: "old-model"
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(configurations: [.deepSeek: previousConfiguration])
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["deepseek-v4-flash-vision-exp"]),
            credentialStore: MemoryCredentialStore(credentials: [.deepSeek: credential]),
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 1_787_731_200) }
        )

        let refreshed = try await coordinator.refreshModels(for: .deepSeek)

        #expect(
            refreshed == ProviderConfiguration(
                models: [ProviderModelState(id: "deepseek-v4-flash-vision-exp")],
                fetchedAt: Date(timeIntervalSince1970: 1_787_731_200),
                selectedModelID: nil
            )
        )
        #expect(try await metadataStore.load().configurations[.deepSeek] == refreshed)
    }

    @Test("selecting the first usable provider makes it current")
    func selectingFirstUsableProviderMakesItCurrent() async throws {
        let configuration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1")],
            fetchedAt: Date(),
            selectedModelID: nil
        )
        let credential = ProviderCredential(generation: UUID(), apiKey: "saved-secret")
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(configurations: [.openAI: configuration])
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(credentials: [.openAI: credential]),
            metadataStore: metadataStore
        )

        let selected = try await coordinator.selectModel("gpt-4.1", for: .openAI)

        #expect(selected.selectedModelID == "gpt-4.1")
        let state = try await metadataStore.load()
        #expect(state.currentProvider == .openAI)
        #expect(state.configurations[.openAI] == selected)
    }

    @Test("configuring another provider never replaces a remembered current provider")
    func configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider() async throws {
        let geminiConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gemini-2.5-flash")],
            fetchedAt: Date(),
            selectedModelID: nil
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(
                configurations: [.gemini: geminiConfiguration],
                currentProvider: .openAI
            )
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(
                credentials: [
                    .gemini: ProviderCredential(generation: UUID(), apiKey: "gemini-secret"),
                ]
            ),
            metadataStore: metadataStore
        )

        _ = try await coordinator.selectModel("gemini-2.5-flash", for: .gemini)

        #expect(try await metadataStore.load().currentProvider == .openAI)
    }

    @Test("model selection is frozen while a request is active")
    func activeRequestFreezesModelSelection() async throws {
        let configuration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1")],
            fetchedAt: Date(),
            selectedModelID: nil
        )
        let initialState = ProviderMetadataState(configurations: [.openAI: configuration])
        let metadataStore = MemoryMetadataStore(state: initialState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(
                credentials: [
                    .openAI: ProviderCredential(generation: UUID(), apiKey: "saved-secret"),
                ]
            ),
            metadataStore: metadataStore
        )
        try await coordinator.beginRequestConfigurationFreeze()

        do {
            _ = try await coordinator.selectModel("gpt-4.1", for: .openAI)
            Issue.record("Expected selection to be frozen")
        } catch {
            #expect(error as? ProviderConfigurationError == .configurationLocked)
        }
        #expect(try await metadataStore.load() == initialState)
        await coordinator.endRequestConfigurationFreeze()
    }

    @Test("a successful image request verifies only the used model")
    func imageSuccessVerifiesUsedModel() async throws {
        let configuration = ProviderConfiguration(
            models: [
                ProviderModelState(id: "gemini-2.5-flash"),
                ProviderModelState(id: "gemini-2.5-pro"),
            ],
            fetchedAt: Date(),
            selectedModelID: "gemini-2.5-flash"
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(configurations: [.gemini: configuration])
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(),
            metadataStore: metadataStore
        )

        try await coordinator.recordVisionSuccess(
            provider: .gemini,
            modelID: "gemini-2.5-flash"
        )

        let models = try #require(await metadataStore.load().configurations[.gemini]?.models)
        #expect(models[0].visionCompatibility == .verified)
        #expect(models[1].visionCompatibility == .unknown)
    }

    @Test("only explicit image-input rejection marks a model incompatible")
    func explicitImageRejectionMarksModelIncompatible() async throws {
        let configuration = ProviderConfiguration(
            models: [ProviderModelState(id: "deepseek-v4-flash-vision-exp")],
            fetchedAt: Date(),
            selectedModelID: "deepseek-v4-flash-vision-exp"
        )
        let initialState = ProviderMetadataState(
            configurations: [.deepSeek: configuration],
            currentProvider: .deepSeek
        )
        let metadataStore = MemoryMetadataStore(state: initialState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(),
            metadataStore: metadataStore
        )

        try await coordinator.recordVisionFailure(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            evidence: .other
        )
        #expect(try await metadataStore.load() == initialState)

        try await coordinator.recordVisionFailure(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            evidence: .imageInputUnsupported
        )
        let configurationAfterFailure = try #require(
            await metadataStore.load().configurations[.deepSeek]
        )
        #expect(configurationAfterFailure.selectedModelID == nil)
        #expect(configurationAfterFailure.models[0].visionCompatibility == .incompatible)
        #expect(try await metadataStore.load().currentProvider == .deepSeek)
    }

    @Test("the user can switch the global current provider only to a usable configuration")
    func currentProviderSwitchRequiresUsableConfiguration() async throws {
        let openAIConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1")],
            fetchedAt: Date(),
            selectedModelID: "gpt-4.1"
        )
        let geminiConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gemini-2.5-flash")],
            fetchedAt: Date(),
            selectedModelID: nil
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(
                configurations: [
                    .openAI: openAIConfiguration,
                    .gemini: geminiConfiguration,
                ],
                currentProvider: .openAI
            )
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(
                credentials: [
                    .openAI: ProviderCredential(generation: UUID(), apiKey: "openai-secret"),
                    .gemini: ProviderCredential(generation: UUID(), apiKey: "gemini-secret"),
                ]
            ),
            metadataStore: metadataStore
        )

        do {
            try await coordinator.setCurrentProvider(.gemini)
            Issue.record("Expected the provider without a selected model to be rejected")
        } catch {
            #expect(error as? ProviderConfigurationError == .providerNotUsable)
        }
        #expect(try await metadataStore.load().currentProvider == .openAI)

        _ = try await coordinator.selectModel("gemini-2.5-flash", for: .gemini)
        try await coordinator.setCurrentProvider(.gemini)
        #expect(try await metadataStore.load().currentProvider == .gemini)
    }

    @Test("clearing a provider removes its key and metadata without switching providers")
    func clearingProviderRemovesKeyAndMetadataWithoutFallback() async throws {
        let configuration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1")],
            fetchedAt: Date(),
            selectedModelID: "gpt-4.1"
        )
        let metadataStore = MemoryMetadataStore(
            state: ProviderMetadataState(
                configurations: [.openAI: configuration],
                currentProvider: .openAI
            )
        )
        let credentialStore = MemoryCredentialStore(
            credentials: [
                .openAI: ProviderCredential(generation: UUID(), apiKey: "saved-secret"),
            ]
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )

        try await coordinator.clearProvider(.openAI)

        #expect(try await credentialStore.credential(for: .openAI) == nil)
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == nil)
        #expect(state.currentProvider == nil)
    }

    @Test("a request cannot begin while provider configuration is being mutated")
    func requestFreezeDoesNotOverlapConfigurationMutation() async throws {
        let modelLister = SuspendedModelLister()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: modelLister,
            credentialStore: MemoryCredentialStore(),
            metadataStore: MemoryMetadataStore()
        )
        let validation = Task {
            try await coordinator.validateAndSaveKey("candidate-secret", for: .gemini)
        }
        await modelLister.waitUntilStarted()

        do {
            try await coordinator.beginRequestConfigurationFreeze()
            Issue.record("Expected the request freeze to reject an in-flight mutation")
        } catch {
            #expect(error as? ProviderConfigurationError == .configurationMutationInProgress)
        }

        await modelLister.finish(with: ["gemini-2.5-flash"])
        _ = try await validation.value
        try await coordinator.beginRequestConfigurationFreeze()
        await coordinator.endRequestConfigurationFreeze()
    }

    @Test("replacement model-list failure discards the previous provider configuration")
    func listFailureDoesNotRestorePreviousProviderConfiguration() async throws {
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1")],
            fetchedAt: Date(),
            selectedModelID: "gpt-4.1"
        )
        let initialState = ProviderMetadataState(
            configurations: [.openAI: previousConfiguration],
            currentProvider: .openAI
        )
        let credentialStore = MemoryCredentialStore(
            credentials: [
                .openAI: ProviderCredential(generation: UUID(), apiKey: "previous-secret"),
            ]
        )
        let metadataStore = MemoryMetadataStore(state: initialState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(
                models: [],
                error: .modelListFailed
            ),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )

        do {
            _ = try await coordinator.validateAndSaveKey("candidate-secret", for: .openAI)
            Issue.record("Expected model-list validation to fail")
        } catch {
            #expect(error as? BoundaryError == .modelListFailed)
        }
        #expect(try await credentialStore.credential(for: .openAI) == nil)
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == nil)
        #expect(state.currentProvider == nil)
        #expect(state.pendingReplacements[.openAI] == nil)
    }

    @Test("refresh failure preserves the previous cache and selection")
    func refreshFailurePreservesCacheAndSelection() async throws {
        let previousConfiguration = ProviderConfiguration(
            models: [ProviderModelState(id: "gpt-4.1", visionCompatibility: .verified)],
            fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
            selectedModelID: "gpt-4.1"
        )
        let initialState = ProviderMetadataState(
            configurations: [.openAI: previousConfiguration],
            currentProvider: .openAI
        )
        let metadataStore = MemoryMetadataStore(state: initialState)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: [], error: .modelListFailed),
            credentialStore: MemoryCredentialStore(
                credentials: [
                    .openAI: ProviderCredential(generation: UUID(), apiKey: "saved-secret"),
                ]
            ),
            metadataStore: metadataStore
        )

        do {
            _ = try await coordinator.refreshModels(for: .openAI)
            Issue.record("Expected refresh to fail")
        } catch {
            #expect(error as? BoundaryError == .modelListFailed)
        }
        #expect(try await metadataStore.load() == initialState)
    }
}

private enum BoundaryError: Error, Equatable {
    case credentialWriteFailed
    case modelListFailed
}

private struct StaticModelLister: ProviderModelListing {
    let models: [String]
    var error: BoundaryError?

    init(models: [String], error: BoundaryError? = nil) {
        self.models = models
        self.error = error
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        if let error {
            throw error
        }
        return models
    }
}

private actor SuspendedModelLister: ProviderModelListing {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<[String], Never>?

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(with models: [String]) {
        resultContinuation?.resume(returning: models)
        resultContinuation = nil
    }
}

private actor MemoryCredentialStore: ProviderCredentialStoring {
    private var credentials: [ProviderID: ProviderCredential]
    private let replaceError: BoundaryError?

    init(
        credentials: [ProviderID: ProviderCredential] = [:],
        replaceError: BoundaryError? = nil
    ) {
        self.credentials = credentials
        self.replaceError = replaceError
    }

    func credential(for provider: ProviderID) async throws -> ProviderCredential? {
        credentials[provider]
    }

    func replaceCredential(
        _ credential: ProviderCredential,
        for provider: ProviderID
    ) async throws {
        if let replaceError {
            throw replaceError
        }
        credentials[provider] = credential
    }

    func deleteCredential(for provider: ProviderID) async throws {
        credentials[provider] = nil
    }
}

private actor MemoryMetadataStore: ProviderMetadataStoring {
    private var state: ProviderMetadataState

    init(state: ProviderMetadataState = ProviderMetadataState()) {
        self.state = state
    }

    func load() async throws -> ProviderMetadataState {
        state
    }

    func save(_ state: ProviderMetadataState) async throws {
        self.state = state
    }
}
