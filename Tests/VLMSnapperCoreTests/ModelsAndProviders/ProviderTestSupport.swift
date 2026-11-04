import Foundation
import Security
import Testing
@testable import VLMSnapperCore

// Doubles and helpers the Provider tests share. Doubles stand in for external boundaries only.

/// A setup boundary with nothing configured and nothing to do. A double overrides only what its tests need.
protocol IdleSetupBoundary: ProviderSetupConfiguring {}

extension IdleSetupBoundary {
    func currentActivity() async -> ProviderWorkflowActivity? { nil }
    func shouldRefreshModelsOnSettingsOpen(for provider: ProviderID) async throws -> Bool { false }
    func configurationState() async throws -> ProviderMetadataState { ProviderMetadataState() }

    func reconcileCredentialState(
        for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void
    ) async throws -> ProviderMetadataState {
        try await configurationState()
    }

    func validateAndSaveKey(_ apiKey: String, for provider: ProviderID) async throws -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func refreshModels(for provider: ProviderID) async throws -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }

    func selectModel(_ modelID: String, for provider: ProviderID) async throws -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
    }
}

/// Answers model-list requests as a test scripts them, and records who asked.
actor ScriptedModelLister: ProviderModelListing {
    private(set) var requests: [ProviderID] = []
    private(set) var keys: [String] = []
    private var models: [String]
    private var error: (any Error)?
    private var nextError: (any Error)?
    private var holdsNext: Bool
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    init(models: [String] = ["model"], holdingNext: Bool = false, failingNext nextError: (any Error)? = nil) {
        self.models = models
        holdsNext = holdingNext
        self.nextError = nextError
    }

    func list(_ models: [String]) { self.models = models }
    /// Every request fails this way until told otherwise.
    func fail(with error: (any Error)?) { self.error = error }
    /// Only the next request fails this way, after any hold.
    func failNext(with error: any Error) { nextError = error }
    func holdNextRequest() { holdsNext = true }

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func finishHeld() {
        held?.resume()
        held = nil
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        requests.append(provider)
        keys.append(apiKey)
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                heldWaiters.forEach { $0.resume() }
                heldWaiters.removeAll()
            }
        }
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        if let error { throw error }
        return models
    }
}

/// A coordinator on memory stores. Tests pass the stores they look at or fail.
func memoryCoordinator(
    lister: any ProviderModelListing = StaticModelLister(models: []),
    credentials: any ProviderCredentialStoring = MemoryCredentialStore(),
    metadata: any ProviderMetadataStoring = MemoryMetadataStore(),
    now: @escaping @Sendable () -> Date = Date.init
) -> ProviderConfigurationCoordinator {
    ProviderConfigurationCoordinator(modelLister: lister, credentialStore: credentials, metadataStore: metadata, now: now)
}

/// A durable key with no configuration, as after the metadata is lost.
func storageWithOrphanedKey() async throws -> SessionTestStorage {
    let storage = SessionTestStorage()
    let coordinator = makeCoordinator(modelLister: ScriptedModelLister(), storage: storage)
    _ = try await coordinator.validateAndSaveKey("durable-key", for: .deepSeek)
    await storage.save(ProviderMetadataState())
    return storage
}

actor FailingProviderBoundary: IdleSetupBoundary {
    let error: any Error
    let failsConfigurationRead: Bool

    init(error: any Error, failsConfigurationRead: Bool = false) {
        self.error = error
        self.failsConfigurationRead = failsConfigurationRead
    }

    func configurationState() throws -> ProviderMetadataState {
        if failsConfigurationRead { throw error }
        return ProviderMetadataState()
    }

    func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) throws -> ProviderConfiguration {
        throw error
    }

    func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) -> ProviderConfiguration {
        ProviderConfiguration(models: [ProviderModelState(id: modelID)], fetchedAt: Date(), selectedModelID: modelID)
    }
}

func makeCoordinator(
    modelLister: any ProviderModelListing,
    storage: SessionTestStorage = SessionTestStorage(),
    now: @escaping @Sendable () -> Date = Date.init
) -> ProviderConfigurationCoordinator {
    ProviderConfigurationCoordinator(
        modelLister: modelLister, credentialStore: storage, metadataStore: storage, now: now
    )
}

// In-memory substitutes for external Keychain and metadata persistence only.
actor SessionTestStorage: ProviderCredentialStoring, ProviderMetadataStoring {
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

enum BoundaryError: Error, Equatable {
    case credentialWriteFailed
    case modelListFailed
}

struct StaticModelLister: ProviderModelListing {
    let models: [String]
    var error: BoundaryError?

    init(models: [String] = ["model"], error: BoundaryError? = nil) {
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

actor MemoryCredentialStore: ProviderCredentialStoring {
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

actor MemoryMetadataStore: ProviderMetadataStoring {
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

struct RejectUnexpectedModelRequest: ProviderModelListing {
    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        Issue.record("An unexpected Provider model request crossed a forbidden boundary")
        return []
    }
}
