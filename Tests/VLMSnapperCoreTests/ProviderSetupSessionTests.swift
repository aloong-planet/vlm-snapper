import Foundation
import Security
import Testing
@testable import VLMSnapperCore

// OS read delays and storage faults are injected. Installed-app Quit/window wiring
// requires user interaction; these tests do not simulate process death.
@Suite("Provider setup session")
struct ProviderSetupSessionTests {
    @Test("concurrent refresh activations retain one busy owner until the external request finishes")
    func concurrentRefreshKeepsBusyOwner() async throws {
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 { group.addTask { await session.refreshModels() } }
            await lister.waitUntilRefreshing()
            for _ in 0..<31 { await group.next() }
            #expect(await session.snapshot().refreshingProvider == .deepSeek)
            #expect(await session.snapshot().phase == .ready)
            #expect(await lister.requests == 2)
            await lister.finish()
        }
        #expect(await session.snapshot().refreshingProvider == nil)
        #expect(await session.snapshot().blocksConfigurationChanges == false)
    }

    @Test("a completed refresh that removes the selected model requires explicit reselection")
    func refreshedModelRemoval() async throws {
        let lister = SuspendedRefreshModelLister(refreshedModels: ["replacement"])
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        #expect(await session.snapshot().selectedModelID == "model")
        await session.selectProvider(.openAI)
        await lister.finish()
        await refresh.value
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .selectingModel)
        #expect(await session.snapshot().availableModelIDs == ["replacement"])
        #expect(await session.snapshot().selectedModelID == nil)
        #expect(await session.snapshot().canFinish == false)
        #expect(await session.snapshot().refreshingProvider == nil)
        await session.selectModel("replacement")
        #expect(await session.snapshot().phase == .ready)
    }

    @Test("returning to a refreshing card preserves its model and a network failure is not a credential failure", arguments: [false, true])
    func refreshSurvivesCardSwitchAndNetworkFailure(fails: Bool) async throws {
        let lister = SuspendedRefreshModelLister(fails: fails)
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        await session.selectProvider(.openAI)
        #expect(await session.snapshot().refreshingProvider == .deepSeek)
        #expect(await session.snapshot().isReadOnly == false)
        #expect(await session.snapshot().blocksConfigurationChanges)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().availableModelIDs == ["model"])
        #expect(await session.snapshot().selectedModelID == "model")
        await lister.finish()
        await refresh.value
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().failure == nil)
        #expect(await session.snapshot().selectedModelID == "model")
        #expect(await session.snapshot().blocksConfigurationChanges == false)
        #expect(try await coordinator.apiKey(for: .deepSeek) == "fixture-key")
        #expect(await session.snapshot().refreshingProvider == nil)
        #expect(await session.snapshot().modelRefreshFailure == (fails ? .unavailable : nil))
        #expect(await lister.requests == 2)
        await session.refreshModels()
        #expect(await session.snapshot().modelRefreshFailure == nil)
        #expect(await lister.requests == 3)
    }

    @Test("model refresh keeps configured content visible while conflicting changes stay blocked")
    func refreshPreservesConfiguredContent() async throws {
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        let busy = await session.snapshot()
        #expect(busy.phase == .ready)
        #expect(busy.availableModelIDs == ["model"])
        #expect(busy.selectedModelID == "model")
        #expect(busy.failure == nil)
        #expect(busy.blocksConfigurationChanges)
        #expect(busy.refreshingProvider == .deepSeek)
        await session.refreshModels()
        #expect(await session.validate(apiKey: "conflicting-key", for: .openAI) == false)
        await lister.finish()
        await refresh.value
        #expect(await lister.requests == 2)
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().blocksConfigurationChanges == false)
    }

    @Test("real coordinator capture state makes configuration read-only until release")
    func captureActivityLocksSession() async throws {
        let lister = SuspendedValidationModelLister(failFirst: false, suspendFirst: false)
        let coordinator = makeCoordinator(modelLister: lister)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let owner = try await coordinator.beginCaptureActivity()
        #expect(await session.snapshot().activity == .capture)
        #expect(await session.snapshot().isReadOnly)
        await session.validate(apiKey: "fixture")
        await session.refreshModels()
        await session.selectModel("model")
        #expect(await lister.keys.isEmpty)
        await coordinator.release(owner)
        #expect(await session.snapshot().isReadOnly == false)
        await session.validate(apiKey: "fixture")
        #expect(await lister.keys == ["fixture"])
    }

    @Test("another Provider keeps editing but duplicate submissions cannot overlap the active job", arguments: [false, true])
    func crossProviderSubmissionIsExclusive(failFirst: Bool) async {
        let lister = SuspendedValidationModelLister(failFirst: failFirst)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: lister))
        let first = Task { await session.validate(apiKey: "first-fixture-key") }
        await lister.waitUntilStarted()
        await session.selectProvider(.openAI)
        let snapshot = await session.snapshot()
        #expect(snapshot.selectedProvider == .openAI)
        #expect(!snapshot.isReadOnly)
        #expect(snapshot.blocksConfigurationChanges)
        for _ in 0..<2 {
            #expect(await session.validate(apiKey: "second-fixture-key", for: .openAI) == false)
        }
        #expect(await lister.providers == [.deepSeek])
        await lister.finish()
        await first.value
        #expect(await session.snapshot().blocksConfigurationChanges == false)
        #expect(await session.validate(apiKey: "second-fixture-key", for: .openAI))
        #expect(await lister.providers == [.deepSeek, .openAI])
    }

    @Test("canceling validation before a delayed credential read returns never starts a Provider request")
    func cancellationBeforeReplacementAdmission() async throws {
        let storage = SessionTestStorage()
        let lister = SuspendedValidationModelLister(failFirst: false, suspendFirst: false)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: storage, metadataStore: storage
        )
        await storage.suspendNextRead()
        let validation = Task {
            try await coordinator.validateAndSaveKey("memory-only-candidate", for: .deepSeek)
        }
        await storage.waitUntilReading()
        validation.cancel()
        await storage.finishReading()
        do {
            _ = try await validation.value
            Issue.record("Expected cancellation before replacement admission")
        } catch is CancellationError {} catch {
            Issue.record("Expected cancellation, not a storage or Provider failure")
        }
        #expect(await lister.keys.isEmpty)
        #expect(try await coordinator.apiKey(for: .deepSeek) == nil)
    }

    @Test("a late editing read error cannot lock a closed or newly reopened card", arguments: [false, true])
    func lateReadFailureIsIgnored(reopen: Bool) async {
        let session = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: makeCoordinator(modelLister: SuspendedValidationModelLister(failFirst: false, suspendFirst: false))
        )
        await session.load()
        await session.credentialReadDidFail(for: .deepSeek) {
            if reopen {
                await session.selectProvider(.openAI)
                await session.selectProvider(.deepSeek)
            }
            return reopen
        }
        #expect(await session.snapshot().failure == nil)
        #expect(!(await session.snapshot().isReadOnly))
        await session.credentialReadDidFail(for: .deepSeek) { true }
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(await session.snapshot().isReadOnly)
    }

    @Test("canceling a card load before Keychain responds cannot start recovery")
    func closingEditorInvalidatesCredentialRead() async throws {
        let storage = SessionTestStorage()
        let initial = ProviderConfigurationCoordinator(
            modelLister: SuspendedValidationModelLister(failFirst: false, suspendFirst: false),
            credentialStore: storage, metadataStore: storage
        )
        _ = try await initial.validateAndSaveKey("durable-key", for: .deepSeek)
        await storage.save(ProviderMetadataState())
        await storage.suspendNextRead()
        let lister = SuspendedValidationModelLister(failFirst: false, suspendFirst: false)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: storage, metadataStore: storage
        )
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        let load = Task { await session.load() }
        await storage.waitUntilReading()
        load.cancel()
        await storage.finishReading()
        await load.value
        #expect(await lister.keys.isEmpty)
        #expect(await session.snapshot().phase == .awaitingValidation)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .selectingModel)
    }

    @Test("recovery is observable and read-only until the complete model list arrives", arguments: [false, true])
    func recoveryPublishesBusyState(reopen: Bool) async throws {
        let storage = SessionTestStorage()
        let initial = ProviderConfigurationCoordinator(
            modelLister: SuspendedValidationModelLister(failFirst: false, suspendFirst: false),
            credentialStore: storage, metadataStore: storage
        )
        _ = try await initial.validateAndSaveKey("durable-key", for: .deepSeek)
        await storage.save(ProviderMetadataState())
        let lister = SuspendedValidationModelLister(failFirst: false)
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: lister, credentialStore: storage, metadataStore: storage
        )
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        let load = Task { await session.load() }
        await lister.waitUntilStarted()
        if reopen {
            await session.selectProvider(.openAI)
            await session.selectProvider(.deepSeek)
        }
        #expect(await session.snapshot().phase == .recovering)
        #expect(await session.snapshot().isReadOnly)
        await lister.finish()
        await load.value
        #expect(await session.snapshot().phase == .selectingModel)
        #expect(!(await session.snapshot().isReadOnly))
        #expect(await lister.keys == ["durable-key"])
    }

    @Test("Keychain read failure preserves metadata and locks editing until reopening retries", arguments: [false, true])
    func keychainReadFailureIsNotMissingCredential(genericFailure: Bool) async throws {
        let storage = SessionTestStorage()
        let coordinator = ProviderConfigurationCoordinator(
            modelLister: SuspendedValidationModelLister(failFirst: false, suspendFirst: false),
            credentialStore: storage, metadataStore: storage
        )
        _ = try await coordinator.validateAndSaveKey("saved-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        await storage.setReadFailure(true)
        await storage.setGenericReadFailure(genericFailure)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(await session.snapshot().isReadOnly)
        #expect(await storage.load().configurations[.deepSeek]?.selectedModelID == "model")
        await storage.setReadFailure(false)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .ready)
        #expect(!(await session.snapshot().isReadOnly))
    }

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

private actor SuspendedRefreshModelLister: ProviderModelListing {
    private let fails: Bool
    private let refreshedModels: [String]
    private(set) var requests = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(fails: Bool = false, refreshedModels: [String] = ["model"]) {
        self.fails = fails
        self.refreshedModels = refreshedModels
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        requests += 1
        if requests == 2 {
            await withCheckedContinuation { continuation in
                pending = continuation
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
            if fails { throw ProviderModelListError.requestRejected(statusCode: 503) }
        }
        return requests == 1 ? ["model"] : refreshedModels
    }

    func waitUntilRefreshing() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() { pending?.resume(); pending = nil }
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
    func currentActivity() async -> ProviderWorkflowActivity? { nil }
    func reconcileCredentialState(for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void) -> ProviderMetadataState { configurationState() }
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
    func currentActivity() async -> ProviderWorkflowActivity? { nil }
    func reconcileCredentialState(for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void) -> ProviderMetadataState { configurationState() }
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
    func currentActivity() async -> ProviderWorkflowActivity? { nil }
    func reconcileCredentialState(for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void) -> ProviderMetadataState { configurationState() }
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

    private var readFailure = false
    private var genericReadFailure = false
    private var suspendsRead = false
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    func suspendNextRead() { suspendsRead = true }
    func waitUntilReading() async {
        if readContinuation != nil { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }
    func finishReading() { readContinuation?.resume(); readContinuation = nil }
    func setReadFailure(_ value: Bool) { readFailure = value }
    func setGenericReadFailure(_ value: Bool) { genericReadFailure = value }
    func credential(for provider: ProviderID) async throws -> ProviderCredential? {
        if suspendsRead {
            suspendsRead = false
            await withCheckedContinuation { continuation in
                readContinuation = continuation
                for waiter in readWaiters { waiter.resume() }
                readWaiters.removeAll()
            }
        }
        if readFailure {
            if genericReadFailure { throw CocoaError(.fileReadUnknown) }
            throw AppleKeychainError.unexpectedStatus(errSecMissingEntitlement)
        }
        return credentials[provider]
    }
    func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) {
        credentials[provider] = credential
    }
    func deleteCredential(for provider: ProviderID) { credentials[provider] = nil }
    func load() -> ProviderMetadataState { state }
    func save(_ state: ProviderMetadataState) { self.state = state }
}
