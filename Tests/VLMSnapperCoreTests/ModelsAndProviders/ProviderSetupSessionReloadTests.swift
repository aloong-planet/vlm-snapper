import Foundation
import Security
import Testing
@testable import VLMSnapperCore

// What these tests leave to installed-app checks is in the header of ProviderSetupSessionTests.swift.
extension ProviderSetupSessionTests {
    @Test("choosing a model marked incompatible says so, and a list refresh makes it choosable again")
    func choosingAnIncompatibleModelSaysSo() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister())
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "model", evidence: .imageInputUnsupported
        )
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        #expect(await session.snapshot().selectedModelID == nil)

        await session.selectModel("model")
        #expect(await session.snapshot().failure == .incompatibleModel)
        #expect(await session.snapshot().selectedModelID == nil)

        await session.refreshModels()
        await session.selectModel("model")
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().selectedModelID == "model")
    }

    @Test("a configuration change shows during a capture, without waiting for it to end")
    func configurationChangeShowsDuringACapture() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister())
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        #expect(await session.snapshot().selectedModelID == "model")

        let capture = try await coordinator.beginCaptureActivity()
        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "model", evidence: .imageInputUnsupported
        )
        let reload = Task { await session.reloadConfiguration(of: .deepSeek) }
        var shown = await session.snapshot().selectedModelID
        for _ in 0..<100 where shown != nil {
            try await Task.sleep(for: .milliseconds(10))
            shown = await session.snapshot().selectedModelID
        }

        #expect(shown == nil, "The reload waited for the capture to end")
        #expect(await session.snapshot().availableModelIDs == ["model"], "Refreshing and choosing again needs the list")
        #expect(await session.snapshot().phase == .selectingModel)
        // Ending the capture lets a reload that waited finish, so this test cannot hang.
        await coordinator.release(capture)
        await reload.value
    }

    @Test("a configuration that cannot be read leaves the card as it is")
    func unreadableConfigurationLeavesTheCard() async {
        let session = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: FailingProviderBoundary(
                error: ProviderPersistenceError.metadataUnavailable,
                failsConfigurationRead: true
            )
        )
        await session.selectModel("model")
        let before = await session.snapshot()
        #expect(before.phase == .ready)
        #expect(before.availableModelIDs == ["model"])

        await session.reloadConfiguration(of: .deepSeek)

        #expect(await session.snapshot().phase == before.phase)
        #expect(await session.snapshot().availableModelIDs == before.availableModelIDs)
        #expect(await session.snapshot().selectedModelID == "model")
        #expect(await session.snapshot().failure == nil)
    }

    @Test("a card showing a rejected key keeps it through a reload")
    func rejectedKeyStaysThroughReload() async {
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: FailingProviderBoundary(error: ProviderModelListError.authenticationRejected)
        )
        await session.validate(apiKey: "rejected-secret")
        #expect(await session.snapshot().failure == .invalidConfiguration)

        await session.reloadConfiguration(of: .openAI)

        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .invalidConfiguration)
    }

    @Test("a card showing a Keychain read failure keeps it through a reload")
    func keychainReadFailureStaysThroughReload() async {
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: FailingProviderBoundary(error: ProviderModelListError.authenticationRejected)
        )
        await session.credentialReadDidFail(for: .openAI) { true }
        #expect(await session.snapshot().failure == .secureStorage)

        await session.reloadConfiguration(of: .openAI)

        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(await session.snapshot().isReadOnly)
    }

    @Test("a card showing a Keychain write failure keeps it through a reload")
    func keychainWriteFailureStaysThroughReload() async {
        let session = ProviderSetupSession(
            selectedProvider: .openAI,
            boundary: FailingProviderBoundary(error: AppleKeychainError.unexpectedStatus(errSecMissingEntitlement))
        )
        await session.validate(apiKey: "candidate")
        #expect(await session.snapshot().failure == .secureStorage)

        await session.reloadConfiguration(of: .openAI)

        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .secureStorage)
    }

    @Test("a reload of another Provider leaves the open card")
    func reloadOfAnotherProviderLeavesTheCard() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister())
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .openAI)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "model", evidence: .imageInputUnsupported
        )

        await session.reloadConfiguration(of: .openAI)

        #expect(await session.snapshot().selectedModelID == "model", "Only the named Provider is read again")
    }

    @Test("a reload that finds the same selection stays ready")
    func reloadWithTheSameSelectionStaysReady() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister())
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()

        await session.reloadConfiguration(of: .deepSeek)

        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().selectedModelID == "model")
    }

    @Test("a reload leaves a validation in progress showing")
    func reloadLeavesAValidationShowing() async {
        let lister = SuspendedValidationModelLister(failFirst: false)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: lister))
        let validation = Task { await session.validate(apiKey: "candidate") }
        await lister.waitUntilStarted()

        await session.reloadConfiguration(of: .deepSeek)

        #expect(await session.snapshot().phase == .validating)
        await lister.finish()
        await validation.value
    }

    @Test("a reload that finishes after the card changed shows nothing", arguments: [false, true])
    func staleReloadShowsNothing(cameBack: Bool) async {
        let boundary = SuspendedConfigurationReadBoundary()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let reload = Task { await session.reloadConfiguration(of: .deepSeek) }
        await boundary.waitUntilReading()

        await session.selectProvider(.gemini)
        if cameBack { await session.selectProvider(.deepSeek) }
        await boundary.finishReading()
        await reload.value

        #expect(await session.snapshot().availableModelIDs == (cameBack ? ["fresh-model"] : []))
    }

    @Test("a Keychain read failure during the reload's read stays")
    func keychainFailureDuringTheReloadStays() async {
        let boundary = SuspendedConfigurationReadBoundary()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let reload = Task { await session.reloadConfiguration(of: .deepSeek) }
        await boundary.waitUntilReading()

        await session.credentialReadDidFail(for: .deepSeek) { true }
        await boundary.finishReading()
        await reload.value

        #expect(await session.snapshot().phase == .failed)
        #expect(await session.snapshot().failure == .secureStorage)
        #expect(await session.snapshot().availableModelIDs.isEmpty)
    }

    @Test("a reload whose state has no configuration leaves the card")
    func reloadWithoutAConfigurationLeavesTheCard() async {
        let boundary = SuspendedConfigurationReadBoundary(readHoldsNoConfiguration: true)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let reload = Task { await session.reloadConfiguration(of: .deepSeek) }
        await boundary.waitUntilReading()
        await boundary.finishReading()
        await reload.value

        #expect(await session.snapshot().availableModelIDs == ["fresh-model"])
        #expect(await session.snapshot().phase == .selectingModel)
    }

    @Test("a card showing a failure still drops the model a rejection cleared")
    func cardWithAFailureDropsTheClearedModel() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister(models: ["first", "second"]))
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("second", for: .deepSeek)
        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "second", evidence: .imageInputUnsupported
        )
        _ = try await coordinator.selectModel("first", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        await session.selectModel("second")
        #expect(await session.snapshot().failure == .incompatibleModel)
        #expect(await session.snapshot().selectedModelID == "first")

        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "first", evidence: .imageInputUnsupported
        )
        await session.reloadConfiguration(of: .deepSeek)

        #expect(await session.snapshot().selectedModelID == nil)
        #expect(await session.snapshot().failure == .incompatibleModel)
        #expect(await session.snapshot().phase == .failed)
    }

    @Test("a reload leaves a recovery showing")
    func reloadLeavesARecoveryShowing() async throws {
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

        await session.reloadConfiguration(of: .deepSeek)

        #expect(await session.snapshot().phase == .recovering)
        await lister.finish()
        await load.value
    }

    @Test("a new key makes a rejected model choosable again")
    func newKeyMakesARejectedModelChoosable() async throws {
        let coordinator = makeCoordinator(modelLister: FixedModelLister())
        _ = try await coordinator.validateAndSaveKey("first-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        try await coordinator.recordVisionFailure(
            provider: .deepSeek, modelID: "model", evidence: .imageInputUnsupported
        )

        _ = try await coordinator.validateAndSaveKey("second-key", for: .deepSeek)

        let configuration = try #require(try await coordinator.configurationState().configurations[.deepSeek])
        #expect(configuration.models == [ProviderModelState(id: "model", visionCompatibility: .unknown)])
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        await session.selectModel("model")
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().selectedModelID == "model")
    }
}

/// A load finds DeepSeek's fresh configuration. The configuration read waits until told to finish, as a slow metadata
/// read does, then gives a stale one, or none.
private actor SuspendedConfigurationReadBoundary: ProviderSetupConfiguring {
    func shouldRefreshModelsOnSettingsOpen(for provider: ProviderID) -> Bool { false }
    private let readHoldsNoConfiguration: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(readHoldsNoConfiguration: Bool = false) {
        self.readHoldsNoConfiguration = readHoldsNoConfiguration
    }

    func currentActivity() async -> ProviderWorkflowActivity? { nil }

    func reconcileCredentialState(
        for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void
    ) -> ProviderMetadataState {
        ProviderMetadataState(configurations: [
            .deepSeek: ProviderConfiguration(
                models: [ProviderModelState(id: "fresh-model")], fetchedAt: Date(), selectedModelID: nil
            ),
        ])
    }

    func configurationState() async throws -> ProviderMetadataState {
        await withCheckedContinuation { continuation in
            pending = continuation
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
        if readHoldsNoConfiguration { return ProviderMetadataState() }
        return ProviderMetadataState(configurations: [
            .deepSeek: ProviderConfiguration(
                models: [ProviderModelState(id: "stale-model")], fetchedAt: Date(), selectedModelID: nil
            ),
        ])
    }

    func validateAndSaveKey(_ apiKey: String, for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func selectModel(_ modelID: String, for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func waitUntilReading() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finishReading() {
        pending?.resume()
        pending = nil
    }
}

private struct FixedModelLister: ProviderModelListing {
    var models = ["model"]

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] { models }
}
