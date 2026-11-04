import Foundation
import Security
import Testing
@testable import VLMSnapperCore

// Doubles and helpers the Provider tests share. Doubles stand in for external boundaries only.

actor SuspendedValidationModelLister: ProviderModelListing {
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

actor FailingProviderBoundary: ProviderSetupConfiguring {
    func shouldRefreshModelsOnSettingsOpen(for provider: ProviderID) -> Bool { false }
    func currentActivity() async -> ProviderWorkflowActivity? { nil }
    func reconcileCredentialState(for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void) throws -> ProviderMetadataState { try configurationState() }
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

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        ProviderConfiguration(models: [], fetchedAt: Date(), selectedModelID: nil)
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

actor SuspendedModelLister: ProviderModelListing {
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
