import Foundation
import Security
import Testing
@testable import VLMSnapperCore

// OS read delays and storage faults are injected. Installed-app Quit/window wiring
// requires user interaction; these tests do not simulate process death.
@Suite("Provider setup session")
struct ProviderSetupSessionTests {
    /// Validates and selects a model at the clock's time, so moving the clock is what ages the cache.
    func configure(_ provider: ProviderID, on coordinator: ProviderConfigurationCoordinator) async throws {
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: provider)
        _ = try await coordinator.selectModel("model", for: provider)
    }

    @Test("real coordinator capture state makes configuration read-only until release")
    func captureActivityLocksSession() async throws {
        let lister = ScriptedModelLister()
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
        let lister = ScriptedModelLister(holdingNext: true, failingNext: failFirst ? ProviderModelListError.authenticationRejected : nil)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: lister))
        let first = Task { await session.validate(apiKey: "first-fixture-key") }
        await lister.waitUntilHeld()
        await session.selectProvider(.openAI)
        let snapshot = await session.snapshot()
        #expect(snapshot.selectedProvider == .openAI)
        #expect(!snapshot.isReadOnly)
        #expect(snapshot.blocksConfigurationChanges)
        for _ in 0..<2 {
            #expect(await session.validate(apiKey: "second-fixture-key", for: .openAI) == false)
        }
        #expect(await lister.requests == [.deepSeek])
        await lister.finishHeld()
        await first.value
        #expect(await session.snapshot().blocksConfigurationChanges == false)
        #expect(await session.validate(apiKey: "second-fixture-key", for: .openAI))
        #expect(await lister.requests == [.deepSeek, .openAI])
    }

    @Test("canceling validation before a delayed credential read returns never starts a Provider request")
    func cancellationBeforeReplacementAdmission() async throws {
        let storage = SessionTestStorage()
        let lister = ScriptedModelLister()
        let coordinator = makeCoordinator(modelLister: lister, storage: storage)
        await storage.suspendNextRead()
        let validation = Task {
            try await coordinator.validateAndSaveKey("memory-only-candidate", for: .deepSeek)
        }
        await storage.waitUntilReading()
        validation.cancel()
        await storage.finishReading()
        await #expect(throws: CancellationError.self) { _ = try await validation.value }
        #expect(await lister.keys.isEmpty)
        #expect(try await coordinator.apiKey(for: .deepSeek) == nil)
    }

    @Test("a late editing read error cannot lock a closed or newly reopened card", arguments: [false, true])
    func lateReadFailureIsIgnored(reopen: Bool) async {
        let session = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: makeCoordinator(modelLister: ScriptedModelLister())
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
        let storage = try await storageWithOrphanedKey()
        await storage.suspendNextRead()
        let lister = ScriptedModelLister()
        let coordinator = makeCoordinator(modelLister: lister, storage: storage)
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
        let lister = ScriptedModelLister(holdingNext: true)
        let coordinator = makeCoordinator(modelLister: lister, storage: try await storageWithOrphanedKey())
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        let load = Task { await session.load() }
        await lister.waitUntilHeld()
        if reopen {
            await session.selectProvider(.openAI)
            await session.selectProvider(.deepSeek)
        }
        #expect(await session.snapshot().phase == .recovering)
        #expect(await session.snapshot().isReadOnly)
        await lister.finishHeld()
        await load.value
        #expect(await session.snapshot().phase == .selectingModel)
        #expect(!(await session.snapshot().isReadOnly))
        #expect(await lister.keys == ["durable-key"])
    }

    @Test("Keychain read failure preserves metadata and locks editing until reopening retries", arguments: [false, true])
    func keychainReadFailureIsNotMissingCredential(genericFailure: Bool) async throws {
        let storage = SessionTestStorage()
        let coordinator = makeCoordinator(modelLister: ScriptedModelLister(), storage: storage)
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
        let boundary = ScriptedModelLister(holdingNext: true, failingNext: ProviderModelListError.authenticationRejected)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        let validation = Task { await session.validate(apiKey: "candidate") }
        await boundary.waitUntilHeld()
        await session.selectProvider(.openAI)
        await boundary.finishHeld()
        await validation.value
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .invalidConfiguration)
    }

    @Test("a submitted key keeps its original Provider when dispatch occurs after a card switch")
    func submittedValidationUsesExplicitProvider() async {
        let boundary = ScriptedModelLister()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        await session.selectProvider(.openAI)
        await session.validate(apiKey: " exact-key\t", for: .deepSeek)
        #expect(await boundary.requests == [.deepSeek])
        #expect(await boundary.keys == [" exact-key\t"])
        #expect(await session.snapshot().selectedProvider == .openAI)
        #expect(await session.snapshot().availableModelIDs.isEmpty)
        #expect(await session.snapshot().phase == .awaitingValidation)
    }

    @Test("a pending validation ignores duplicates and releases its slot after success or failure", arguments: [false, true])
    func pendingValidationSuppressesDuplicates(failFirst: Bool) async {
        let boundary = ScriptedModelLister(holdingNext: true, failingNext: failFirst ? ProviderModelListError.authenticationRejected : nil)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: boundary))
        let first = Task { await session.validate(apiKey: "first-key") }
        await boundary.waitUntilHeld()
        await session.validate(apiKey: "duplicate-key")
        await session.selectProvider(.openAI)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .validating)
        await session.validate(apiKey: "another-duplicate")
        #expect(await boundary.keys == ["first-key"])
        await boundary.finishHeld()
        await first.value
        #expect(await session.snapshot().phase == (failFirst ? .failed : .selectingModel))
        await session.validate(apiKey: "next-key")
        #expect(await boundary.keys == ["first-key", "next-key"])
    }

    @Test("validation reveals the complete model list without choosing a model, and selecting one enables Done")
    func validationRevealsModelsAndSelectingEnablesDone() async {
        let boundary = ProviderConfigurationBoundaryProbe(models: ["gemini-2.5-flash", "gemini-2.5-pro"])
        let session = ProviderSetupSession(selectedProvider: .gemini, boundary: boundary)

        await session.validate(apiKey: "candidate-secret")
        let revealed = await session.snapshot()

        #expect(revealed.availableModelIDs == ["gemini-2.5-flash", "gemini-2.5-pro"])
        #expect(revealed.selectedModelID == nil)
        #expect(revealed.phase == .selectingModel)
        #expect(!revealed.canFinish)
        #expect(await boundary.validatedKeys == ["candidate-secret"])

        await session.selectModel("gemini-2.5-flash")
        let selected = await session.snapshot()

        #expect(selected.selectedModelID == "gemini-2.5-flash")
        #expect(selected.phase == .ready)
        #expect(selected.canFinish)
        #expect(await boundary.selectedModels == ["gemini-2.5-flash"])
    }

    @Test("selecting another provider clears only transient presentation state")
    func selectingProviderClearsTransientState() async {
        let boundary = ProviderConfigurationBoundaryProbe(models: ["gpt-4.1"])
        let session = ProviderSetupSession(selectedProvider: .openAI, boundary: boundary)
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
        let boundary = ProviderConfigurationBoundaryProbe(models: ["gpt-4.1"])
        let session = ProviderSetupSession(selectedProvider: .openAI, boundary: boundary)

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

    static let validationFailures: [(any Error, ProviderSetupFailure)] = [
        (ProviderModelListError.authenticationRejected, .invalidConfiguration),
        (ProviderModelListError.requestRejected(statusCode: 503), .unavailable),
        (AppleKeychainError.unexpectedStatus(errSecMissingEntitlement), .secureStorage),
    ]

    @Test("a failed validation says why, and keeps saying so through a reload", arguments: validationFailures)
    func validationFailureIsReportedAndStaysThroughReload(error: any Error, expected: ProviderSetupFailure) async {
        let session = ProviderSetupSession(selectedProvider: .openAI, boundary: FailingProviderBoundary(error: error))

        await session.validate(apiKey: "candidate")
        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == expected)

        await session.reloadConfiguration(of: .openAI)
        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == expected)
    }
}

private actor ProviderConfigurationBoundaryProbe: IdleSetupBoundary {
    let validationResult: ProviderConfiguration
    private(set) var validatedKeys: [String] = []
    private(set) var selectedModels: [String] = []

    init(models: [String]) {
        validationResult = ProviderConfiguration(
            models: models.map { ProviderModelState(id: $0) }, fetchedAt: Date(), selectedModelID: nil
        )
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

private actor SuspendedProviderConfigurationBoundaryProbe: IdleSetupBoundary {
    private var selectionStarted = false
    private var selectionContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

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
