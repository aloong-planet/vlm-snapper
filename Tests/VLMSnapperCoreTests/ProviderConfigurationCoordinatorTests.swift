import Foundation
import Testing
@testable import VLMSnapperCore

// Request integration for unavailable models is covered when the provider request
// pipeline is introduced; this suite owns the one-refresh decision primitive.
// ApplicationWorkflow tests exercise production admission with injected native
// effects. Installed shortcut delivery, screen freezing and unsaved-result
// window foregrounding still require signed-app interaction acceptance. The
// guarded capture entry was not mutated into an unguarded production bypass.
@Suite("Provider configuration coordinator")
struct ProviderConfigurationCoordinatorTests {
    @Test("capture and model owners preserve every saved configuration mutation", arguments: [false, true])
    func workflowOwnerBlocksAllConfigurationChanges(capturing: Bool) async throws {
        let credentials = MemoryCredentialStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["vision"]), credentialStore: credentials,
            metadataStore: MemoryMetadataStore()
        )
        _ = try await coordinator.validateAndSaveKey("saved-fixture", for: .deepSeek)
        _ = try await coordinator.selectModel("vision", for: .deepSeek)
        let before = try await coordinator.configurationState()
        let owner = try await (capturing ? coordinator.beginCaptureActivity() : coordinator.beginRequestConfigurationFreeze())
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            _ = try await coordinator.validateAndSaveKey("new-fixture", for: .deepSeek)
        }
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            _ = try await coordinator.refreshModels(for: .deepSeek)
        }
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            _ = try await coordinator.selectModel("vision", for: .deepSeek)
        }
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.setCurrentProvider(.deepSeek)
        }
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.clearProvider(.deepSeek)
        }
        #expect(try await coordinator.configurationState() == before)
        #expect(try await credentials.credential(for: .deepSeek)?.apiKey == "saved-fixture")
        await coordinator.release(owner)
        try await coordinator.clearProvider(.deepSeek)
        #expect(try await coordinator.configurationState().configurations.isEmpty)
    }

    @Test("a canceled recovery waiter finishes before the capture owner releases")
    func canceledRecoveryDoesNotWaitForOwner() async throws {
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []), credentialStore: MemoryCredentialStore(),
            metadataStore: MemoryMetadataStore()
        )
        let owner = try await coordinator.beginCaptureActivity()
        let recovery = Task { try await coordinator.reconcileCredentialState(for: .deepSeek) }
        try await Task.sleep(for: .milliseconds(30))
        recovery.cancel()
        // This bounded test-only rescue prevents a cancellation regression from
        // hanging the suite, and makes such a regression fail the owner assertion.
        let rescue = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await coordinator.release(owner)
        }
        await #expect(throws: CancellationError.self) { _ = try await recovery.value }
        #expect(await coordinator.currentActivity() == .capture)
        rescue.cancel()
        await rescue.value
        await coordinator.release(owner)
    }

    @MainActor
    @Test("Try Again during credential work cannot request or alter persisted history")
    func blockedTryAgainPreservesHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = try SQLiteHistoryStore(databaseURL: root.appendingPathComponent("history.sqlite"))
        let provider = WorkflowProviderBoundary()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: FileSystemScreenshotStore(rootDirectory: root.appendingPathComponent("pictures")),
            historyStore: history, provider: provider
        )
        let session = OperationWorkspaceSession(originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                                                runner: runner, activeGate: ActiveOperationGate())
        let lister = SuspendedModelLister()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: MemoryCredentialStore(), metadataStore: MemoryMetadataStore()
        )
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        let selection = ProviderSelection(providerID: "deepseek", modelID: "vision")
        #expect(try await workflow.performOperation {
            try await session.startSelectedOperation(selection: selection, targetLanguage: "en")
        })
        let original = try #require(try await history.history(matching: HistoryQuery()).first)
        #expect(original.operation.sourceMarkdown == "Result 1")
        let firstSnapshot = await session.snapshot()
        let validation = Task { try await coordinator.validateAndSaveKey("fixture", for: .deepSeek) }
        await lister.waitUntilStarted()
        let accepted = try await workflow.performOperation {
            await session.select(.translate)
            try await session.startSelectedOperation(selection: selection, targetLanguage: "en")
        }
        #expect(!accepted)
        #expect(await provider.requests == 1)
        #expect(await session.snapshot() == firstSnapshot)
        #expect(try await history.history(matching: HistoryQuery()) == [original])
        await lister.finish(with: ["vision"])
        _ = try await validation.value
        #expect(try await workflow.performOperation {
            try await session.startSelectedOperation(selection: selection, targetLanguage: "en")
        })
        let replaced = try await history.history(matching: HistoryQuery())
        #expect(await provider.requests == 2)
        #expect(replaced.count == 1)
        #expect(replaced.first?.id == original.id)
        #expect(replaced.first?.operation.sourceMarkdown == "Result 2")
    }

    @MainActor
    @Test("selection handoff remains exclusive and releases after an operation failure")
    func captureHandoffFailureReleasesOwner() async throws {
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []), credentialStore: MemoryCredentialStore(),
            metadataStore: MemoryMetadataStore()
        )
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        var owner: UUID?
        #expect(await workflow.capture(from: .shortcut, presentProvider: { _ in }) { token in
            owner = token
            return true
        })
        let token = try #require(owner)
        #expect(await coordinator.currentActivity() == .capture)
        #expect(await workflow.capture(from: .shortcut, replacing: token, presentProvider: { _ in }) { _ in false } == false)
        #expect(await coordinator.currentActivity() == .capture)
        await #expect(throws: CancellationError.self) {
            _ = try await workflow.performOperation(continuingCapture: token) {
                #expect(await coordinator.currentActivity() == .modelRequest)
                #expect(await coordinator.acquire() == nil)
                throw CancellationError()
            }
        }
        #expect(await coordinator.currentActivity() == nil)
        var staleEffect = false
        #expect(try await workflow.performOperation(continuingCapture: token) { staleEffect = true } == false)
        #expect(!staleEffect)
    }

    @MainActor
    @Test("shortcut and menu capture route active credential work without freezing", arguments: CaptureEntryPoint.allCases)
    func captureRoutesActiveProviderJob(source: CaptureEntryPoint) async throws {
        let lister = SuspendedModelLister()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: MemoryCredentialStore(),
            metadataStore: MemoryMetadataStore()
        )
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        let validation = Task { try await coordinator.validateAndSaveKey("fixture", for: .deepSeek) }
        await lister.waitUntilStarted()
        var captures = 0
        var shownProvider: ProviderID?
        let accepted = await workflow.capture(from: source, presentProvider: { shownProvider = $0 }) { _ in
            captures += 1
            return true
        }
        #expect(!accepted)
        #expect(captures == 0)
        #expect(shownProvider == .deepSeek)
        await lister.finish(with: ["vision"])
        _ = try await validation.value
        let nextCapture = await workflow.capture(from: source, presentProvider: { _ in
            Issue.record("Completed credential work must not be presented as active")
        }) { _ in
            captures += 1
            return false
        }
        #expect(!nextCapture)
        #expect(captures == 1)
        #expect(await coordinator.currentActivity() == nil)
    }

    @Test("only the owning operation lease can release configuration exclusion")
    func exclusiveActivityReleaseRequiresTheOwnerToken() async throws {
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: []),
            credentialStore: MemoryCredentialStore(),
            metadataStore: MemoryMetadataStore()
        )
        let owner = try #require(await coordinator.acquire())
        await coordinator.release(UUID())
        #expect(await coordinator.acquire() == nil)
        await coordinator.release(owner)
        let nextOwner = try #require(await coordinator.acquire())
        await coordinator.release(owner)
        #expect(await coordinator.acquire() == nil)
        await coordinator.release(nextOwner)
    }

    @Test("recovery waits for a model operation rather than failing configuration")
    func reconciliationWaitsForModelRequestToFinish() async throws {
        let metadata = MemoryMetadataStore()
        let credentials = MemoryCredentialStore()
        try await credentials.replaceCredential(
            ProviderCredential(generation: UUID(), apiKey: "fixture-key"), for: .deepSeek
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["recovered-model"]),
            credentialStore: credentials, metadataStore: metadata
        )
        let owner = try #require(await coordinator.acquire())
        let recovery = Task { try await coordinator.reconcileCredentialState(for: .deepSeek) }
        // Hold the external operation long enough to distinguish waiting from
        // rejection. The production wait must be notification-driven, not timed.
        try await Task.sleep(for: .milliseconds(50))
        #expect(try await metadata.load().configurations.isEmpty)
        await coordinator.release(owner)
        let recovered = try await recovery.value
        #expect(recovered.configurations[.deepSeek]?.models.map(\.id) == ["recovered-model"])
    }

    @Test("capture owns configuration until its atomic transition to a model request")
    func providerValidationAndCaptureAreMutuallyExclusive() async throws {
        let metadata = MemoryMetadataStore()
        let credentials = MemoryCredentialStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["vision"]),
            credentialStore: credentials, metadataStore: metadata
        )
        let capture = try await coordinator.beginCaptureActivity()
        do {
            _ = try await coordinator.validateAndSaveKey("fixture", for: .deepSeek)
            Issue.record("Capture must reject credential replacement")
        } catch {
            #expect(error as? ProviderConfigurationError == .configurationLocked)
        }
        #expect(try await credentials.credential(for: .deepSeek) == nil)
        #expect(try await metadata.load().pendingReplacements.isEmpty)
        do {
            try await coordinator.transitionCaptureToModelRequest(UUID())
            Issue.record("A foreign owner cannot transition capture")
        } catch {
            #expect(error as? ProviderConfigurationError == .configurationLocked)
        }
        #expect(await coordinator.currentActivity() == .capture)
        try await coordinator.transitionCaptureToModelRequest(capture)
        #expect(await coordinator.currentActivity() == .modelRequest)
        #expect(await coordinator.acquire() == nil)
        await coordinator.release(capture)
        _ = try await coordinator.validateAndSaveKey("fixture", for: .deepSeek)
        #expect(await coordinator.currentActivity() == nil)
    }

    @Test("recovery waits for selection to end and a canceled waiter cannot recover", arguments: [false, true])
    func reconciliationWaitsForCaptureToFinish(cancel: Bool) async throws {
        let metadata = MemoryMetadataStore()
        let credentials = MemoryCredentialStore()
        try await credentials.replaceCredential(
            ProviderCredential(generation: UUID(), apiKey: "fixture"), for: .deepSeek
        )
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["vision"]),
            credentialStore: credentials, metadataStore: metadata
        )
        let capture = try await coordinator.beginCaptureActivity()
        let recovery = Task { try await coordinator.reconcileCredentialState(for: .deepSeek) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await coordinator.currentActivity() == .capture)
        #expect(try await metadata.load().configurations.isEmpty)
        if cancel { recovery.cancel() }
        await coordinator.release(capture)
        if cancel {
            do {
                _ = try await recovery.value
                Issue.record("Canceled recovery must not publish configuration")
            } catch { #expect(error is CancellationError) }
            #expect(try await metadata.load().configurations.isEmpty)
        } else {
            #expect(try await recovery.value.configurations[.deepSeek]?.models.map(\.id) == ["vision"])
        }
        #expect(await coordinator.currentActivity() == nil)
    }

    @Test("generic credential write failures are secure-storage failures, not Provider outages")
    func genericCredentialWriteFailureIsSecureStorage() async {
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: MemoryCredentialStore(replaceError: .credentialWriteFailed),
            metadataStore: MemoryMetadataStore()
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
        let initial = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: credentials, metadataStore: metadata
        )
        _ = try await initial.validateAndSaveKey("old-key", for: .deepSeek)
        _ = try await initial.selectModel("model", for: .deepSeek)
        await metadata.setSaveFailure(true)
        await credentials.setDeleteFailure(true)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: RejectUnexpectedModelRequest(),
            credentialStore: credentials, metadataStore: metadata
        )
        do {
            _ = try await coordinator.validateAndSaveKey("candidate", for: .deepSeek)
            Issue.record("Replacement must be rejected before retirement is durable")
        } catch { #expect(error as? ProviderPersistenceError == .metadataUnavailable) }
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
        let lister = SuspendedModelLister()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: credentials, metadataStore: MemoryMetadataStore()
        )
        let request = Task { try await coordinator.validateAndSaveKey("candidate", for: .deepSeek) }
        await lister.waitUntilStarted()
        request.cancel()
        await lister.finish(with: ["model"])
        do {
            _ = try await request.value
            Issue.record("Cancelled validation published a credential")
        } catch { #expect(error is CancellationError) }
        #expect(try await coordinator.apiKey(for: .deepSeek) == nil)
        #expect(try await coordinator.configurationState().configurations[.deepSeek] == nil)
    }

    @Test("a failed old-key deletion cannot resurrect that key through recovery", arguments: [false, true])
    func failedDeletionCannotRecoverRetiredCredential(allowDeletionOnRestart: Bool) async throws {
        let credentials = MemoryCredentialStore()
        let metadata = MemoryMetadataStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: credentials, metadataStore: metadata
        )
        _ = try await coordinator.validateAndSaveKey("old-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        await credentials.setDeleteFailure(true)
        do {
            _ = try await coordinator.validateAndSaveKey("new-key", for: .deepSeek)
            Issue.record("Expected deletion failure")
        } catch {}
        if allowDeletionOnRestart { await credentials.setDeleteFailure(false) }
        let restarted = ProviderConfigurationCoordinator(
            modelLister: RejectUnexpectedModelRequest(),
            credentialStore: credentials, metadataStore: metadata
        )
        _ = try? await restarted.reconcilePendingReplacements()
        #expect(try await restarted.configurationState().configurations[.deepSeek] == nil)
        #expect(try await restarted.configurationState().currentProvider == nil)
        if allowDeletionOnRestart {
            #expect(try await restarted.apiKey(for: .deepSeek) == nil)
        }
    }

    @Test("metadata publication failure is local secure storage rather than a Provider outage")
    func metadataPublicationFailureIsSecureStorage() async {
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: MemoryCredentialStore(), metadataStore: PublicationFailingMetadataStore()
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
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["initial"]),
            credentialStore: credentials, metadataStore: metadata
        )
        do {
            _ = try await coordinator.validateAndSaveKey("new-key", for: .deepSeek)
            Issue.record("Expected publication failure")
        } catch {}
        #expect(try await coordinator.apiKey(for: .deepSeek) == "new-key")
        #expect(try await coordinator.configurationState().configurations[.deepSeek] == nil)
        await metadata.allowPublication()
        let restarted = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["fresh-a", "fresh-b"]),
            credentialStore: credentials, metadataStore: metadata
        )
        let recovered = try await restarted.reconcilePendingReplacements()
        #expect(recovered.configurations[.deepSeek]?.models.map(\.id) == ["fresh-a", "fresh-b"])
        #expect(recovered.pendingReplacements[.deepSeek] == nil)
    }

    @Test("a missing durable credential clears its cache and global selection")
    func reconciliationClearsConfigurationWithoutCredential() async throws {
        let credentials = MemoryCredentialStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: credentials, metadataStore: MemoryMetadataStore()
        )
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        try await credentials.deleteCredential(for: .deepSeek)
        let recovered = try await coordinator.reconcilePendingReplacements()
        #expect(recovered.configurations[.deepSeek] == nil)
        #expect(recovered.currentProvider == nil)
    }

    @Test("an orphaned durable credential recovers the complete model configuration")
    func reconciliationRecoversStoredKeyWithoutConfiguration() async throws {
        let credentials = MemoryCredentialStore()
        let metadata = MemoryMetadataStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model-a", "model-b"]),
            credentialStore: credentials, metadataStore: metadata
        )
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        // Loss of the non-secret cache does not delete the independently durable key.
        try await metadata.save(ProviderMetadataState())
        let recovered = try await coordinator.reconcilePendingReplacements()
        #expect(recovered.configurations[.deepSeek]?.models.map(\.id) == ["model-a", "model-b"])
        #expect(recovered.configurations[.deepSeek]?.selectedModelID == nil)
        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-key")
    }

    @Test("unsafe local API keys cannot replace a saved credential",
          arguments: ["", "key\n", "key\rvalue", String(repeating: "x", count: 4097)])
    func unsafeInputPreservesSavedConfiguration(key: String) async throws {
        let credentialStore = MemoryCredentialStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: credentialStore, metadataStore: MemoryMetadataStore()
        )
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        do {
            _ = try await coordinator.validateAndSaveKey(key, for: .deepSeek)
            Issue.record("Unsafe input reached Provider validation")
        } catch {}
        #expect(try await coordinator.apiKey(for: .deepSeek) == "saved-key")
        #expect(try await coordinator.configurationState().configurations[.deepSeek]?.selectedModelID == "model")
    }

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
            #expect(error as? ProviderPersistenceError == .credentialUnavailable)
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
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["fresh-model"]),
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            now: { Date(timeIntervalSince1970: 1_787_731_200) }
        )

        let reconciled = try await coordinator.reconcilePendingReplacements()

        #expect(reconciled.configurations[.gemini]?.models.map(\.id) == ["fresh-model"])
        #expect(reconciled.configurations[.gemini]?.selectedModelID == nil)
        #expect(reconciled.configurations[.gemini]?.fetchedAt == Date(timeIntervalSince1970: 1_787_731_200))
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
        let metadataStore = MemoryMetadataStore()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: StaticModelLister(models: ["model"]),
            credentialStore: MemoryCredentialStore(),
            metadataStore: metadataStore
        )

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
        let lease = try await coordinator.beginRequestConfigurationFreeze()

        do {
            _ = try await coordinator.selectModel("gpt-4.1", for: .openAI)
            Issue.record("Expected selection to be frozen")
        } catch {
            #expect(error as? ProviderConfigurationError == .configurationLocked)
        }
        #expect(try await metadataStore.load() == initialState)
        await coordinator.endRequestConfigurationFreeze(lease)
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
        let lease = try await coordinator.beginRequestConfigurationFreeze()
        await coordinator.endRequestConfigurationFreeze(lease)
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

private actor WorkflowProviderBoundary: PreparedOperationStreaming {
    private(set) var requests = 0

    func stream(originalPNG: Data, preparedOperation: PreparedOperation) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        requests += 1
        let result = "Result \(requests)"
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta(result))
            continuation.yield(.metadata(ProviderResponseMetadata(requestID: nil, usage: nil)))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

private enum BoundaryError: Error, Equatable {
    case credentialWriteFailed
    case modelListFailed
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
    private var deleteFailure = false
    func setDeleteFailure(_ value: Bool) { deleteFailure = value }

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
        if deleteFailure { throw BoundaryError.credentialWriteFailed }
        credentials[provider] = nil
    }
}

private actor MemoryMetadataStore: ProviderMetadataStoring {
    private var state: ProviderMetadataState
    private var saveFailure = false
    func setSaveFailure(_ value: Bool) { saveFailure = value }

    init(state: ProviderMetadataState = ProviderMetadataState()) {
        self.state = state
    }

    func load() async throws -> ProviderMetadataState {
        state
    }

    func save(_ state: ProviderMetadataState) async throws {
        if saveFailure { throw CocoaError(.fileWriteNoPermission) }
        self.state = state
    }
}

private struct RejectUnexpectedModelRequest: ProviderModelListing {
    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        Issue.record("An unexpected Provider model request crossed a forbidden boundary")
        return []
    }
}
