import Foundation
import Testing
@testable import VLMSnapperCore

extension ProviderConfigurationCoordinatorTests {
    @Test("generic credential write failures are secure-storage failures, not Provider outages")
    func genericCredentialWriteFailureIsSecureStorage() async {
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["model"]),
            credentials: MemoryCredentialStore(replaceError: .credentialWriteFailed)
        )
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.validate(apiKey: "candidate")
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(!(await session.snapshot().canFinish))
    }

    @Test("a replacement is rejected without network access when retirement cannot be persisted")
    func retirementWriteFailurePreservesOriginalConfiguration() async throws {
        let credentials = MemoryCredentialStore()
        let metadata = MemoryMetadataStore()
        let initial = memoryCoordinator(
            lister: StaticModelLister(models: ["model"]),
            credentials: credentials,
            metadata: metadata
        )
        _ = try await initial.validateAndSaveKey("old-key", for: .deepSeek)
        _ = try await initial.selectModel("model", for: .deepSeek)
        await metadata.setSaveFailure(true)
        await credentials.setDeleteFailure(true)
        let coordinator = memoryCoordinator(
            lister: RejectUnexpectedModelRequest(),
            credentials: credentials,
            metadata: metadata
        )
        await #expect(throws: ProviderPersistenceError.metadataUnavailable) {
            _ = try await coordinator.validateAndSaveKey("candidate", for: .deepSeek)
        }
        await metadata.setSaveFailure(false)
        await credentials.setDeleteFailure(false)
        let reopened = try await coordinator.reconcileCredentialState(for: .deepSeek)
        #expect(reopened.currentProvider == .deepSeek)
        #expect(reopened.configurations[.deepSeek]?.selectedModelID == "model")
        #expect(try await coordinator.apiKey(for: .deepSeek) == "old-key")
    }

    @Test("cancellation after a submitted request cannot persist its memory-only candidate")
    func canceledValidationDoesNotPersistCandidate() async throws {
        let credentials = MemoryCredentialStore()
        let lister = ScriptedModelLister(holdingNext: true)
        let coordinator = memoryCoordinator(lister: lister, credentials: credentials)
        let request = Task { try await coordinator.validateAndSaveKey("candidate", for: .deepSeek) }
        await lister.waitUntilHeld()
        request.cancel()
        await lister.finishHeld()
        await #expect(throws: CancellationError.self) {
            _ = try await request.value
        }
        #expect(try await coordinator.apiKey(for: .deepSeek) == nil)
        #expect(try await coordinator.configurationState().configurations[.deepSeek] == nil)
    }

    @Test("a failed old-key deletion cannot resurrect that key through recovery", arguments: [false, true])
    func failedDeletionCannotRecoverRetiredCredential(allowDeletionOnRestart: Bool) async throws {
        let credentials = MemoryCredentialStore()
        let metadata = MemoryMetadataStore()
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["model"]),
            credentials: credentials,
            metadata: metadata
        )
        _ = try await coordinator.validateAndSaveKey("old-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        await credentials.setDeleteFailure(true)
        do {
            _ = try await coordinator.validateAndSaveKey("new-key", for: .deepSeek)
            Issue.record("Expected deletion failure")
        } catch {}
        if allowDeletionOnRestart { await credentials.setDeleteFailure(false) }
        let restarted = memoryCoordinator(
            lister: RejectUnexpectedModelRequest(),
            credentials: credentials,
            metadata: metadata
        )
        _ = try? await restarted.reconcileCredentialState(for: .deepSeek)
        #expect(try await restarted.configurationState().configurations[.deepSeek] == nil)
        #expect(try await restarted.configurationState().currentProvider == nil)
        if allowDeletionOnRestart {
            #expect(try await restarted.apiKey(for: .deepSeek) == nil)
        }
    }

    @Test("metadata publication failure is local secure storage rather than a Provider outage")
    func metadataPublicationFailureIsSecureStorage() async {
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["model"]),
            metadata: PublicationFailingMetadataStore()
        )
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.validate(apiKey: "candidate")
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(!(await session.snapshot().canFinish))
    }

    @Test("publication failure leaves the durable new key recoverable from a fresh model list")
    func postKeychainPublicationFailureRecovers() async throws {
        let credentials = MemoryCredentialStore()
        let metadata = PublicationFailingMetadataStore()
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["initial"]),
            credentials: credentials,
            metadata: metadata
        )
        do {
            _ = try await coordinator.validateAndSaveKey("new-key", for: .deepSeek)
            Issue.record("Expected publication failure")
        } catch {}
        #expect(try await coordinator.apiKey(for: .deepSeek) == "new-key")
        #expect(try await coordinator.configurationState().configurations[.deepSeek] == nil)
        await metadata.allowPublication()
        let restarted = memoryCoordinator(
            lister: StaticModelLister(models: ["fresh-a", "fresh-b"]),
            credentials: credentials,
            metadata: metadata
        )
        let recovered = try await restarted.reconcileCredentialState(for: .deepSeek)
        #expect(recovered.configurations[.deepSeek]?.models.map(\.id) == ["fresh-a", "fresh-b"])
        #expect(recovered.pendingReplacements[.deepSeek] == nil)
    }

    @Test("a missing durable credential clears its cache and global selection")
    func reconciliationClearsConfigurationWithoutCredential() async throws {
        let credentials = MemoryCredentialStore()
        let coordinator = memoryCoordinator(lister: StaticModelLister(models: ["model"]), credentials: credentials)
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        try await credentials.deleteCredential(for: .deepSeek)
        let recovered = try await coordinator.reconcileCredentialState(for: .deepSeek)
        #expect(recovered.configurations[.deepSeek] == nil)
        #expect(recovered.currentProvider == nil)
    }

    @Test("an orphaned durable credential recovers the complete model configuration")
    func reconciliationRecoversStoredKeyWithoutConfiguration() async throws {
        let credentials = MemoryCredentialStore()
        let metadata = MemoryMetadataStore()
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["model-a", "model-b"]),
            credentials: credentials,
            metadata: metadata
        )
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        // Loss of the non-secret cache does not delete the independently durable key.
        try await metadata.save(ProviderMetadataState())
        let recovered = try await coordinator.reconcileCredentialState(for: .deepSeek)
        #expect(recovered.configurations[.deepSeek]?.models.map(\.id) == ["model-a", "model-b"])
        #expect(recovered.configurations[.deepSeek]?.selectedModelID == nil)
        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-key")
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

        await #expect(throws: ProviderPersistenceError.credentialUnavailable) {
            _ = try await coordinator.validateAndSaveKey("candidate-secret", for: .openAI)
        }

        #expect(try await credentialStore.credential(for: .openAI) == nil)
        let state = try await metadataStore.load()
        #expect(state.configurations[.openAI] == nil)
        #expect(state.currentProvider == nil)
        #expect(state.pendingReplacements[.openAI] == nil)
    }

    @Test("a legacy replacement journal recovers a durable new credential with a fresh list")
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["fresh-model"]),
            credentials: credentialStore,
            metadata: metadataStore,
            now: { Date(timeIntervalSince1970: 1_787_731_200) }
        )

        let reconciled = try await coordinator.reconcileCredentialState(for: .gemini)

        #expect(reconciled.configurations[.gemini]?.models.map(\.id) == ["fresh-model"])
        #expect(reconciled.configurations[.gemini]?.selectedModelID == nil)
        #expect(reconciled.configurations[.gemini]?.fetchedAt == Date(timeIntervalSince1970: 1_787_731_200))
        #expect(reconciled.pendingReplacements[.gemini] == nil)
        #expect(try await metadataStore.load() == reconciled)
    }

    @Test("a replacement that never reached the keychain removes the previous credential and its configuration")
    func reconciliationRemovesCredentialLeftAtPreviousGeneration() async throws {
        let previousGeneration = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let pendingState = ProviderMetadataState(
            configurations: [
                .gemini: ProviderConfiguration(
                    models: [ProviderModelState(id: "old-model")],
                    fetchedAt: Date(timeIntervalSince1970: 1_787_600_000),
                    selectedModelID: "old-model"
                ),
            ],
            pendingReplacements: [
                .gemini: PendingProviderReplacement(
                    previousGeneration: previousGeneration,
                    nextGeneration: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    configuration: ProviderConfiguration(
                        models: [ProviderModelState(id: "new-model")],
                        fetchedAt: Date(timeIntervalSince1970: 1_787_700_000),
                        selectedModelID: nil
                    )
                ),
            ],
            currentProvider: .gemini
        )
        let metadataStore = MemoryMetadataStore(state: pendingState)
        let coordinator = memoryCoordinator(
            credentials: MemoryCredentialStore(
                credentials: [.gemini: ProviderCredential(generation: previousGeneration, apiKey: "old-secret")]
            ),
            metadata: metadataStore
        )

        let reconciled = try await coordinator.reconcileCredentialState(for: .gemini)

        #expect(reconciled == ProviderMetadataState())
        #expect(try await metadataStore.load() == reconciled)
        #expect(try await coordinator.apiKey(for: .gemini) == nil)
    }
}

private actor PublicationFailingMetadataStore: ProviderMetadataStoring {
    private var state = ProviderMetadataState()
    private var failsPublication = true

    func load() -> ProviderMetadataState { state }
    func allowPublication() { failsPublication = false }
    func save(_ state: ProviderMetadataState) throws {
        if failsPublication, state.configurations[.deepSeek] != nil {
            throw CocoaError(.fileWriteNoPermission)
        }
        self.state = state
    }
}
