import Foundation

public enum ProviderID: String, CaseIterable, Codable, Sendable {
    case openAI = "openai"
    case gemini
    case deepSeek = "deepseek"
}

public enum VisionCompatibility: String, Codable, Equatable, Sendable {
    case unknown
    case verified
    case incompatible
}

public enum VisionFailureEvidence: Equatable, Sendable {
    case imageInputUnsupported
    case other
}

public struct ModelUnavailableRefreshGate: Sendable {
    private var refreshClaimed = false

    public init() {}

    public mutating func claimRefresh() -> Bool {
        guard !refreshClaimed else {
            return false
        }
        refreshClaimed = true
        return true
    }
}

public struct ProviderModelState: Codable, Equatable, Sendable {
    public let id: String
    public let visionCompatibility: VisionCompatibility

    public init(id: String, visionCompatibility: VisionCompatibility = .unknown) {
        self.id = id
        self.visionCompatibility = visionCompatibility
    }
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public let models: [ProviderModelState]
    public let fetchedAt: Date
    public let selectedModelID: String?

    public init(
        models: [ProviderModelState],
        fetchedAt: Date,
        selectedModelID: String?
    ) {
        self.models = models
        self.fetchedAt = fetchedAt
        self.selectedModelID = selectedModelID
    }

    public var isUsable: Bool {
        guard let selectedModelID else {
            return false
        }
        return models.contains {
            $0.id == selectedModelID && $0.visionCompatibility != .incompatible
        }
    }
}

public struct ProviderCredential: Codable, Equatable, Sendable {
    public let generation: UUID
    public let apiKey: String

    public init(generation: UUID, apiKey: String) {
        self.generation = generation
        self.apiKey = apiKey
    }
}

public struct PendingProviderReplacement: Codable, Equatable, Sendable {
    public let previousGeneration: UUID?
    public let nextGeneration: UUID
    public let configuration: ProviderConfiguration
    public let restoreCurrentProvider: Bool?

    public init(
        previousGeneration: UUID?,
        nextGeneration: UUID,
        configuration: ProviderConfiguration,
        restoreCurrentProvider: Bool? = nil
    ) {
        self.previousGeneration = previousGeneration
        self.nextGeneration = nextGeneration
        self.configuration = configuration
        self.restoreCurrentProvider = restoreCurrentProvider
    }
}

public struct ProviderMetadataState: Codable, Equatable, Sendable {
    public var configurations: [ProviderID: ProviderConfiguration]
    public var pendingReplacements: [ProviderID: PendingProviderReplacement]
    public var currentProvider: ProviderID?

    public init(
        configurations: [ProviderID: ProviderConfiguration] = [:],
        pendingReplacements: [ProviderID: PendingProviderReplacement] = [:],
        currentProvider: ProviderID? = nil
    ) {
        self.configurations = configurations
        self.pendingReplacements = pendingReplacements
        self.currentProvider = currentProvider
    }
}

public protocol ProviderModelListing: Sendable {
    func listModels(provider: ProviderID, apiKey: String) async throws -> [String]
}

public protocol ProviderCredentialStoring: Sendable {
    func credential(for provider: ProviderID) async throws -> ProviderCredential?
    func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) async throws
    func deleteCredential(for provider: ProviderID) async throws
}

public protocol ProviderMetadataStoring: Sendable {
    func load() async throws -> ProviderMetadataState
    func save(_ state: ProviderMetadataState) async throws
}

public enum ProviderConfigurationError: Error, Equatable {
    case configurationLocked
    case configurationMutationInProgress
    case missingCredential
    case providerNotUsable
    case modelNotFound
    case incompatibleModel
    case inconsistentCredentialState
}

public enum ProviderPersistenceError: Error, Equatable, Sendable {
    case metadataUnavailable
    case credentialUnavailable
}

public actor ProviderConfigurationCoordinator: ProviderSetupConfiguring {
    private static let modelCacheLifetime: TimeInterval = 24 * 60 * 60

    private let modelLister: any ProviderModelListing
    private let credentialStore: any ProviderCredentialStoring
    private let metadataStore: any ProviderMetadataStoring
    private let now: @Sendable () -> Date
    private let makeGeneration: @Sendable () -> UUID
    private var configurationLocked = false
    private var configurationMutationInProgress = false
    private var unavailableProviders: Set<ProviderID> = []

    public init(
        modelLister: any ProviderModelListing,
        credentialStore: any ProviderCredentialStoring,
        metadataStore: any ProviderMetadataStoring,
        now: @escaping @Sendable () -> Date = Date.init,
        makeGeneration: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.modelLister = modelLister
        self.credentialStore = credentialStore
        self.metadataStore = metadataStore
        self.now = now
        self.makeGeneration = makeGeneration
    }

    public func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) async throws -> ProviderConfiguration {
        if let issue = ProviderAPIKeyInput.issue(in: apiKey) { throw issue }
        try Task.checkCancellation()
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        unavailableProviders.insert(provider)
        var state = try await loadMetadata()
        let previousSelection = state.configurations[provider]?.selectedModelID
        let restoreCurrentProvider = state.currentProvider == provider
        let previousGeneration = try await readCredential(for: provider)?.generation
        try Task.checkCancellation()
        let nextGeneration = makeGeneration()
        state.configurations[provider] = nil
        // Persist retirement before deletion: a failed delete must not turn the
        // old key into an apparently orphaned, recoverable credential on restart.
        state.pendingReplacements[provider] = PendingProviderReplacement(
            previousGeneration: previousGeneration, nextGeneration: nextGeneration,
            configuration: ProviderConfiguration(models: [], fetchedAt: now(), selectedModelID: nil),
            restoreCurrentProvider: restoreCurrentProvider
        )
        if restoreCurrentProvider {
            state.currentProvider = nil
        }
        try await saveMetadata(state)
        try await deleteCredential(for: provider)

        let modelIDs: [String]
        do {
            try Task.checkCancellation()
            modelIDs = try await modelLister.listModels(provider: provider, apiKey: apiKey)
            try Task.checkCancellation()
        } catch {
            state.pendingReplacements[provider] = nil
            try await saveMetadata(state)
            throw error
        }
        var seenModelIDs = Set<String>()
        let models = modelIDs.compactMap { modelID -> ProviderModelState? in
            guard !modelID.isEmpty, seenModelIDs.insert(modelID).inserted else {
                return nil
            }
            return ProviderModelState(id: modelID)
        }
        let configuration = ProviderConfiguration(
            models: models,
            fetchedAt: now(),
            selectedModelID: previousSelection.flatMap { selectedModelID in
                models.contains { $0.id == selectedModelID } ? selectedModelID : nil
            }
        )
        let nextCredential = ProviderCredential(
            generation: nextGeneration,
            apiKey: apiKey
        )
        state.pendingReplacements[provider] = PendingProviderReplacement(
            previousGeneration: nil,
            nextGeneration: nextCredential.generation,
            configuration: configuration,
            restoreCurrentProvider: restoreCurrentProvider
        )
        try await saveMetadata(state)
        do {
            try Task.checkCancellation()
            try await writeCredential(nextCredential, for: provider)
        } catch {
            state.pendingReplacements[provider] = nil
            do {
                try await saveMetadata(state)
            } catch {
                throw ProviderConfigurationError.inconsistentCredentialState
            }
            throw error
        }
        try Task.checkCancellation()
        state.configurations[provider] = configuration
        if restoreCurrentProvider, configuration.isUsable {
            state.currentProvider = provider
        }
        state.pendingReplacements[provider] = nil
        try await saveMetadata(state)
        unavailableProviders.remove(provider)
        return configuration
    }

    public func configurationState() async throws -> ProviderMetadataState {
        var state = try await loadMetadata()
        for provider in unavailableProviders.union(state.pendingReplacements.keys) {
            state.configurations[provider] = nil
            if state.currentProvider == provider { state.currentProvider = nil }
        }
        return state
    }

    public func apiKey(for provider: ProviderID) async throws -> String? {
        do { return try await readCredential(for: provider)?.apiKey }
        catch {
            unavailableProviders.insert(provider)
            throw error
        }
    }

    public func reconcilePendingReplacements() async throws -> ProviderMetadataState {
        try await reconcileCredentials(for: ProviderID.allCases)
    }

    public func reconcileCredentialState(
        for provider: ProviderID,
        onRecovery: @escaping @Sendable () async -> Void = {}
    ) async throws -> ProviderMetadataState {
        try await reconcileCredentials(for: [provider], onRecovery: onRecovery)
    }

    private func reconcileCredentials(
        for providers: [ProviderID],
        onRecovery: @escaping @Sendable () async -> Void = {}
    ) async throws -> ProviderMetadataState {
        try Task.checkCancellation()
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        var state = try await loadMetadata()
        let originalState = state
        for provider in providers {
            unavailableProviders.insert(provider)
            let storedCredential = try await readCredential(for: provider)
            try Task.checkCancellation()
            guard let credential = storedCredential else {
                state.configurations[provider] = nil
                state.pendingReplacements[provider] = nil
                if state.currentProvider == provider { state.currentProvider = nil }
                continue
            }
            let pending = state.pendingReplacements[provider]
            if let pending, pending.nextGeneration != credential.generation {
                if pending.previousGeneration == credential.generation {
                    try await deleteCredential(for: provider)
                    state.configurations[provider] = nil
                    state.pendingReplacements[provider] = nil
                    if state.currentProvider == provider { state.currentProvider = nil }
                    continue
                }
                throw ProviderConfigurationError.inconsistentCredentialState
            }
            guard state.configurations[provider] == nil || pending != nil else { continue }
            await onRecovery()
            try Task.checkCancellation()
            let modelIDs = try await modelLister.listModels(provider: provider, apiKey: credential.apiKey)
            try Task.checkCancellation()
            var seen = Set<String>()
            state.configurations[provider] = ProviderConfiguration(
                models: modelIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
                    .map { ProviderModelState(id: $0) },
                fetchedAt: now(), selectedModelID: pending?.configuration.selectedModelID.flatMap {
                    modelIDs.contains($0) ? $0 : nil
                }
            )
            if pending?.restoreCurrentProvider == true, state.currentProvider == nil,
               state.configurations[provider]?.isUsable == true {
                state.currentProvider = provider
            }
            state.pendingReplacements[provider] = nil
        }
        if state != originalState { try await saveMetadata(state) }
        unavailableProviders.subtract(providers)
        return state
    }

    public func shouldRefreshModelsOnSettingsOpen(
        for provider: ProviderID
    ) async throws -> Bool {
        guard let configuration = try await loadMetadata().configurations[provider] else {
            return true
        }
        return now().timeIntervalSince(configuration.fetchedAt) >= Self.modelCacheLifetime
    }

    public func refreshModels(for provider: ProviderID) async throws -> ProviderConfiguration {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        guard let credential = try await readCredential(for: provider) else {
            throw ProviderConfigurationError.missingCredential
        }
        let modelIDs = try await modelLister.listModels(
            provider: provider,
            apiKey: credential.apiKey
        )
        var seenModelIDs = Set<String>()
        let models = modelIDs.compactMap { modelID -> ProviderModelState? in
            guard !modelID.isEmpty, seenModelIDs.insert(modelID).inserted else {
                return nil
            }
            return ProviderModelState(id: modelID)
        }
        var state = try await loadMetadata()
        let previousSelection = state.configurations[provider]?.selectedModelID
        let refreshed = ProviderConfiguration(
            models: models,
            fetchedAt: now(),
            selectedModelID: previousSelection.flatMap { selectedModelID in
                models.contains { $0.id == selectedModelID } ? selectedModelID : nil
            }
        )
        state.configurations[provider] = refreshed
        try await saveMetadata(state)
        return refreshed
    }

    public func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) async throws -> ProviderConfiguration {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        guard try await readCredential(for: provider) != nil else {
            throw ProviderConfigurationError.missingCredential
        }
        var state = try await loadMetadata()
        guard let configuration = state.configurations[provider],
              let model = configuration.models.first(where: { $0.id == modelID }) else {
            throw ProviderConfigurationError.modelNotFound
        }
        guard model.visionCompatibility != .incompatible else {
            throw ProviderConfigurationError.incompatibleModel
        }
        let selected = ProviderConfiguration(
            models: configuration.models,
            fetchedAt: configuration.fetchedAt,
            selectedModelID: modelID
        )
        state.configurations[provider] = selected
        if state.currentProvider == nil {
            state.currentProvider = provider
        }
        try await saveMetadata(state)
        return selected
    }

    public func beginRequestConfigurationFreeze() throws {
        guard !configurationLocked else {
            throw ProviderConfigurationError.configurationLocked
        }
        guard !configurationMutationInProgress else {
            throw ProviderConfigurationError.configurationMutationInProgress
        }
        configurationLocked = true
    }

    public func endRequestConfigurationFreeze() {
        configurationLocked = false
    }

    public func setCurrentProvider(_ provider: ProviderID) async throws {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        guard try await readCredential(for: provider) != nil else {
            throw ProviderConfigurationError.missingCredential
        }
        var state = try await loadMetadata()
        guard state.configurations[provider]?.isUsable == true else {
            throw ProviderConfigurationError.providerNotUsable
        }
        state.currentProvider = provider
        try await saveMetadata(state)
    }

    public func clearProvider(_ provider: ProviderID) async throws {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        try await deleteCredential(for: provider)
        var state = try await loadMetadata()
        state.configurations[provider] = nil
        state.pendingReplacements[provider] = nil
        if state.currentProvider == provider {
            state.currentProvider = nil
        }
        try await saveMetadata(state)
    }

    public func recordVisionSuccess(
        provider: ProviderID,
        modelID: String
    ) async throws {
        var state = try await loadMetadata()
        guard let configuration = state.configurations[provider],
              configuration.models.contains(where: { $0.id == modelID }) else {
            throw ProviderConfigurationError.modelNotFound
        }
        let models = configuration.models.map { model in
            model.id == modelID
                ? ProviderModelState(id: model.id, visionCompatibility: .verified)
                : model
        }
        state.configurations[provider] = ProviderConfiguration(
            models: models,
            fetchedAt: configuration.fetchedAt,
            selectedModelID: configuration.selectedModelID
        )
        try await saveMetadata(state)
    }

    public func recordVisionFailure(
        provider: ProviderID,
        modelID: String,
        evidence: VisionFailureEvidence
    ) async throws {
        guard evidence == .imageInputUnsupported else {
            return
        }
        var state = try await loadMetadata()
        guard let configuration = state.configurations[provider],
              configuration.models.contains(where: { $0.id == modelID }) else {
            throw ProviderConfigurationError.modelNotFound
        }
        let models = configuration.models.map { model in
            model.id == modelID
                ? ProviderModelState(id: model.id, visionCompatibility: .incompatible)
                : model
        }
        state.configurations[provider] = ProviderConfiguration(
            models: models,
            fetchedAt: configuration.fetchedAt,
            selectedModelID: configuration.selectedModelID == modelID
                ? nil
                : configuration.selectedModelID
        )
        try await saveMetadata(state)
    }

    private func beginConfigurationMutation() throws {
        guard !configurationLocked else {
            throw ProviderConfigurationError.configurationLocked
        }
        guard !configurationMutationInProgress else {
            throw ProviderConfigurationError.configurationMutationInProgress
        }
        configurationMutationInProgress = true
    }

    private func loadMetadata() async throws -> ProviderMetadataState {
        do { return try await metadataStore.load() }
        catch { throw ProviderPersistenceError.metadataUnavailable }
    }

    private func readCredential(for provider: ProviderID) async throws -> ProviderCredential? {
        do { return try await credentialStore.credential(for: provider) }
        catch {
            unavailableProviders.insert(provider)
            if error is AppleKeychainError { throw error }
            throw ProviderPersistenceError.credentialUnavailable
        }
    }

    private func saveMetadata(_ state: ProviderMetadataState) async throws {
        do { try await metadataStore.save(state) }
        catch { throw ProviderPersistenceError.metadataUnavailable }
    }

    private func writeCredential(_ credential: ProviderCredential, for provider: ProviderID) async throws {
        do { try await credentialStore.replaceCredential(credential, for: provider) }
        catch {
            if error is AppleKeychainError { throw error }
            throw ProviderPersistenceError.credentialUnavailable
        }
    }

    private func deleteCredential(for provider: ProviderID) async throws {
        do { try await credentialStore.deleteCredential(for: provider) }
        catch {
            if error is AppleKeychainError { throw error }
            throw ProviderPersistenceError.credentialUnavailable
        }
    }

    private func endConfigurationMutation() {
        configurationMutationInProgress = false
    }

}
