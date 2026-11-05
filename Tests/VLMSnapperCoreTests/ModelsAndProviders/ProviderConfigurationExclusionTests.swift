import Foundation
import Testing
@testable import VLMSnapperCore

// ApplicationWorkflow tests exercise production admission with injected native
// effects. Installed shortcut delivery, screen freezing and unsaved-result
// window foregrounding still require signed-app interaction acceptance. The
// guarded capture entry was not mutated into an unguarded production bypass.
extension ProviderConfigurationCoordinatorTests {
    @Test("capture and model owners preserve every saved configuration mutation", arguments: [false, true])
    func workflowOwnerBlocksAllConfigurationChanges(capturing: Bool) async throws {
        let credentials = MemoryCredentialStore()
        let coordinator = memoryCoordinator(lister: StaticModelLister(models: ["vision"]), credentials: credentials)
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
        let coordinator = memoryCoordinator()
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
        let lister = ScriptedModelLister(models: ["vision"], holdingNext: true)
        let coordinator = memoryCoordinator(lister: lister)
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        let selection = ProviderSelection(providerID: "deepseek", modelID: "vision")
        #expect(try await workflow.performOperation {
            try await session.startSelectedOperation(selection: selection, targetLanguage: "en")
        })
        let original = try #require(try await history.history(matching: HistoryQuery()).first)
        #expect(original.operation.sourceMarkdown == "Result 1")
        let firstSnapshot = await session.snapshot()
        let validation = Task { try await coordinator.validateAndSaveKey("fixture", for: .deepSeek) }
        await lister.waitUntilHeld()
        let accepted = try await workflow.performOperation {
            await session.select(.translate)
            try await session.startSelectedOperation(selection: selection, targetLanguage: "en")
        }
        #expect(!accepted)
        #expect(await provider.requests == 1)
        #expect(await session.snapshot() == firstSnapshot)
        #expect(try await history.history(matching: HistoryQuery()) == [original])
        await lister.finishHeld()
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
    @Test("a request from an open capture keeps the activity until the capture ends")
    func captureKeepsActivityThroughItsRequests() async throws {
        let coordinator = memoryCoordinator()
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
        for _ in 1...2 {
            let accepted = await workflow.performInCapture(owner: token) {
                #expect(await coordinator.currentActivity() == .modelRequest)
                #expect(await coordinator.acquire() == nil)
            }
            #expect(accepted)
            #expect(await coordinator.currentActivity() == .capture)
            #expect(await coordinator.acquire() == nil)
        }
        await coordinator.release(token)
        #expect(await coordinator.currentActivity() == nil)
        var staleEffect = false
        #expect(await workflow.performInCapture(owner: token) { staleEffect = true } == false)
        #expect(!staleEffect)
    }

    @MainActor
    @Test("a capture that ends during its request does not get the activity back")
    func endedCaptureDoesNotRetakeActivity() async throws {
        let coordinator = memoryCoordinator()
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        var owner: UUID?
        #expect(await workflow.capture(from: .shortcut, presentProvider: { _ in }) { token in
            owner = token
            return true
        })
        let token = try #require(owner)
        #expect(await workflow.performInCapture(owner: token) {
            await coordinator.release(token)
        })
        #expect(await coordinator.currentActivity() == nil)
    }

    @MainActor
    @Test("shortcut and menu capture route active credential work without freezing", arguments: CaptureEntryPoint.allCases)
    func captureRoutesActiveProviderJob(source: CaptureEntryPoint) async throws {
        let lister = ScriptedModelLister(models: ["vision"], holdingNext: true)
        let coordinator = memoryCoordinator(lister: lister)
        let workflow = ApplicationWorkflow(coordinator: coordinator)
        let validation = Task { try await coordinator.validateAndSaveKey("fixture", for: .deepSeek) }
        await lister.waitUntilHeld()
        var captures = 0
        var shownProvider: ProviderID?
        let accepted = await workflow.capture(from: source, presentProvider: { shownProvider = $0 }) { _ in
            captures += 1
            return true
        }
        #expect(!accepted)
        #expect(captures == 0)
        #expect(shownProvider == .deepSeek)
        await lister.finishHeld()
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
        let coordinator = memoryCoordinator()
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["recovered-model"]),
            credentials: credentials,
            metadata: metadata
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["vision"]),
            credentials: credentials,
            metadata: metadata
        )
        let capture = try await coordinator.beginCaptureActivity()
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            _ = try await coordinator.validateAndSaveKey("fixture", for: .deepSeek)
        }
        #expect(try await credentials.credential(for: .deepSeek) == nil)
        #expect(try await metadata.load().pendingReplacements.isEmpty)
        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            try await coordinator.transitionCaptureToModelRequest(UUID())
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
        let coordinator = memoryCoordinator(
            lister: StaticModelLister(models: ["vision"]),
            credentials: credentials,
            metadata: metadata
        )
        let capture = try await coordinator.beginCaptureActivity()
        let recovery = Task { try await coordinator.reconcileCredentialState(for: .deepSeek) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await coordinator.currentActivity() == .capture)
        #expect(try await metadata.load().configurations.isEmpty)
        if cancel { recovery.cancel() }
        await coordinator.release(capture)
        if cancel {
            await #expect(throws: CancellationError.self) {
                _ = try await recovery.value
            }
            #expect(try await metadata.load().configurations.isEmpty)
        } else {
            #expect(try await recovery.value.configurations[.deepSeek]?.models.map(\.id) == ["vision"])
        }
        #expect(await coordinator.currentActivity() == nil)
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
        let coordinator = memoryCoordinator(
            credentials: MemoryCredentialStore(credentials: [.openAI: ProviderCredential(generation: UUID(), apiKey: "saved-secret")]),
            metadata: metadataStore
        )
        let lease = try await coordinator.beginRequestConfigurationFreeze()

        await #expect(throws: ProviderConfigurationError.configurationLocked) {
            _ = try await coordinator.selectModel("gpt-4.1", for: .openAI)
        }
        #expect(try await metadataStore.load() == initialState)
        await coordinator.release(lease)
    }

    @Test("a request cannot begin while provider configuration is being mutated")
    func requestFreezeDoesNotOverlapConfigurationMutation() async throws {
        let modelLister = ScriptedModelLister(models: ["gemini-2.5-flash"], holdingNext: true)
        let coordinator = memoryCoordinator(lister: modelLister)
        let validation = Task {
            try await coordinator.validateAndSaveKey("candidate-secret", for: .gemini)
        }
        await modelLister.waitUntilHeld()

        await #expect(throws: ProviderConfigurationError.configurationMutationInProgress) {
            try await coordinator.beginRequestConfigurationFreeze()
        }

        await modelLister.finishHeld()
        _ = try await validation.value
        let lease = try await coordinator.beginRequestConfigurationFreeze()
        await coordinator.release(lease)
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
