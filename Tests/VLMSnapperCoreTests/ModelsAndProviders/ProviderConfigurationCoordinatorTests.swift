import Foundation
import Testing
@testable import VLMSnapperCore

// Request integration for unavailable models is covered when the provider request
// pipeline is introduced; this suite owns the one-refresh decision primitive.
@Suite("Provider configuration coordinator")
struct ProviderConfigurationCoordinatorTests {
    @Test("unsafe local API keys cannot replace a saved credential",
          arguments: ["", "key\n", "key\rvalue", String(repeating: "x", count: 4097)])
    func unsafeInputPreservesSavedConfiguration(key: String) async throws {
        let credentialStore = MemoryCredentialStore()
        let coordinator = memoryCoordinator(lister: StaticModelLister(models: ["model"]), credentials: credentialStore)
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        do {
            _ = try await coordinator.validateAndSaveKey(key, for: .deepSeek)
            Issue.record("Unsafe input reached Provider validation")
        } catch {}
        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-key")
        #expect(try await coordinator.configurationState().configurations[.deepSeek]?.selectedModelID == "model")
    }

    @Test("a complete model list is saved with the validated key")
    func completeModelListIsSavedWithValidatedKey() async throws {
        let credentialStore = MemoryCredentialStore()
        let metadataStore = MemoryMetadataStore()
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["gpt-4o", "gpt-4.1"]),
            credentials: credentialStore,
            metadata: metadataStore,
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
        let coordinator = memoryCoordinator(credentials: credentialStore)

        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-secret")
        #expect(try await coordinator.apiKey(for: .gemini) == nil)
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["gpt-4.1", "gpt-4o"]),
            credentials: credentialStore,
            metadata: metadataStore
        )

        let replacement = try await coordinator.validateAndSaveKey(
            "replacement-secret",
            for: .openAI
        )

        #expect(replacement.selectedModelID == "gpt-4.1")
        #expect(try await credentialStore.credential(for: .openAI)?.apiKey == "replacement-secret")
        #expect(try await metadataStore.load().currentProvider == .openAI)
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
        let coordinator = memoryCoordinator(metadata: metadataStore, now: { referenceDate })

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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["deepseek-v4-flash-vision-exp"]),
            credentials: MemoryCredentialStore(credentials: [.deepSeek: credential]),
            metadata: metadataStore,
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

    @Test("a request's refresh replaces the list and clears a model that is gone", arguments: [["replacement"], []])
    func requestRefreshClearsAModelThatIsGone(models: [String]) async throws {
        let reference = Date(timeIntervalSince1970: 1_787_731_200)
        let coordinator = requestCoordinator(lister: StaticModelLister(models: models), now: reference)
        let lease = try await coordinator.beginRequestConfigurationFreeze()

        try await coordinator.refreshModelsForRequest(provider: .deepSeek)

        let state = try await coordinator.configurationState()
        #expect(state.configurations[.deepSeek] == ProviderConfiguration(
            models: models.map { ProviderModelState(id: $0) }, fetchedAt: reference, selectedModelID: nil
        ))
        #expect(state.currentProvider == .deepSeek)
        #expect(await coordinator.currentActivity() == .modelRequest)
        await coordinator.release(lease)
    }

    @Test("a request's refresh keeps a model still listed and forgets what was known about it")
    func requestRefreshKeepsAModelStillListed() async throws {
        let coordinator = requestCoordinator(lister: StaticModelLister(models: ["old-model", "another"]))
        _ = try await coordinator.beginRequestConfigurationFreeze()

        try await coordinator.refreshModelsForRequest(provider: .deepSeek)

        let configuration = try #require(try await coordinator.configurationState().configurations[.deepSeek])
        #expect(configuration.selectedModelID == "old-model")
        #expect(configuration.models == [ProviderModelState(id: "old-model"), ProviderModelState(id: "another")])
    }

    @Test("a request's failed refresh keeps the cache")
    func requestRefreshFailureKeepsCache() async throws {
        let coordinator = requestCoordinator(lister: StaticModelLister(models: [], error: .modelListFailed))
        let before = try await coordinator.configurationState()
        _ = try await coordinator.beginRequestConfigurationFreeze()

        await #expect(throws: BoundaryError.modelListFailed) {
            try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        }

        #expect(try await coordinator.configurationState() == before)
        #expect(await coordinator.currentActivity() == .modelRequest)
    }

    @Test("a refresh for a request needs a request to be running")
    func requestRefreshIsRefusedWithoutARequest() async throws {
        let lister = ScriptedModelLister()
        let coordinator = requestCoordinator(lister: lister)
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        }

        let capture = try await coordinator.beginCaptureActivity()
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        }
        await coordinator.release(capture)

        await lister.holdNextRequest()
        let validation = Task { try await coordinator.validateAndSaveKey("new-key", for: .gemini) }
        await lister.waitUntilHeld()
        #expect(await coordinator.currentActivity() == .credential(.gemini))
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        }
        await lister.finishHeld()
        _ = try await validation.value

        #expect(await lister.requests == [.gemini])
    }

    @Test("a canceled request sends no list request")
    func canceledRequestDoesNotRefresh() async throws {
        let lister = ScriptedModelLister()
        let coordinator = requestCoordinator(lister: lister)
        _ = try await coordinator.beginRequestConfigurationFreeze()

        let refresh = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        }

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(await lister.requests.isEmpty)
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
        let coordinator = memoryCoordinator(
            credentials: MemoryCredentialStore(credentials: [.openAI: credential]),
            metadata: metadataStore
        )

        let selected = try await coordinator.selectModel("gpt-4.1", for: .openAI)

        #expect(selected.selectedModelID == "gpt-4.1")
        let state = try await metadataStore.load()
        #expect(state.currentProvider == .openAI)
        #expect(state.configurations[.openAI] == selected)
    }

    @Test("configuring another provider never replaces a remembered current provider")
    func configuringAnotherProviderDoesNotReplaceRememberedCurrentProvider() async throws {
        let metadataStore = MemoryMetadataStore()
        let coordinator = memoryCoordinator(lister: StaticModelLister(models: ["model"]), metadata: metadataStore)

        _ = try await coordinator.validateAndSaveKey("openai-key", for: .openAI)
        _ = try await coordinator.selectModel("model", for: .openAI)
        _ = try await coordinator.validateAndSaveKey("gemini-key", for: .gemini)
        _ = try await coordinator.selectModel("model", for: .gemini)
        let replacement = try await coordinator.validateAndSaveKey("replacement-key", for: .gemini)

        #expect(replacement.selectedModelID == "model")
        let state = try await coordinator.configurationState()
        #expect(state.currentProvider == .openAI)
        #expect(state.configurations[.openAI]?.isUsable == true)
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
        let coordinator = memoryCoordinator(metadata: metadataStore)

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
        let coordinator = memoryCoordinator(metadata: metadataStore)

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
        let coordinator = memoryCoordinator(
            credentials: MemoryCredentialStore(credentials: [
                .openAI: ProviderCredential(generation: UUID(), apiKey: "openai-secret"),
                .gemini: ProviderCredential(generation: UUID(), apiKey: "gemini-secret"),
            ]),
            metadata: metadataStore
        )

        await #expect(throws: ProviderConfigurationError.providerNotUsable) {
            try await coordinator.setCurrentProvider(.gemini)
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
        let coordinator = memoryCoordinator(credentials: credentialStore, metadata: metadataStore)

        try await coordinator.clearProvider(.openAI)

        #expect(try await credentialStore.credential(for: .openAI) == nil)
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == nil)
        #expect(state.currentProvider == nil)
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: [], error: .modelListFailed),
            credentials: credentialStore,
            metadata: metadataStore
        )

        await #expect(throws: BoundaryError.modelListFailed) {
            _ = try await coordinator.validateAndSaveKey("candidate-secret", for: .openAI)
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: [], error: .modelListFailed),
            credentials: MemoryCredentialStore(credentials: [.openAI: ProviderCredential(generation: UUID(), apiKey: "saved-secret")]),
            metadata: metadataStore
        )

        await #expect(throws: BoundaryError.modelListFailed) {
            _ = try await coordinator.refreshModels(for: .openAI)
        }
        #expect(try await metadataStore.load() == initialState)
    }
}

/// DeepSeek configured and current, its selected model marked verified, for a request's refresh.
private func requestCoordinator(
    lister: any ProviderModelListing,
    now: Date = Date(timeIntervalSince1970: 1_787_731_200)
) -> ProviderConfigurationCoordinator {
    let configuration = ProviderConfiguration(
        models: [ProviderModelState(id: "old-model", visionCompatibility: .verified)],
        fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
        selectedModelID: "old-model"
    )
    return memoryCoordinator(
        lister: lister,
        credentials: MemoryCredentialStore(credentials: [
            .deepSeek: ProviderCredential(generation: UUID(), apiKey: "saved-secret"),
        ]),
        metadata: MemoryMetadataStore(state: ProviderMetadataState(
            configurations: [.deepSeek: configuration], currentProvider: .deepSeek
        )),
        now: { now }
    )
}
