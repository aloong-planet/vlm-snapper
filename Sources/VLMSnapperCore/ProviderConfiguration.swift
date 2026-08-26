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

    public init(
        previousGeneration: UUID?,
        nextGeneration: UUID,
        configuration: ProviderConfiguration
    ) {
        self.previousGeneration = previousGeneration
        self.nextGeneration = nextGeneration
        self.configuration = configuration
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

public actor ProviderConfigurationCoordinator {
    private static let modelCacheLifetime: TimeInterval = 24 * 60 * 60

    private let modelLister: any ProviderModelListing
    private let credentialStore: any ProviderCredentialStoring
    private let metadataStore: any ProviderMetadataStoring
    private let now: @Sendable () -> Date
    private let makeGeneration: @Sendable () -> UUID
    private var configurationLocked = false
    private var configurationMutationInProgress = false

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
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        let modelIDs = try await modelLister.listModels(provider: provider, apiKey: apiKey)
        var seenModelIDs = Set<String>()
        let models = modelIDs.compactMap { modelID -> ProviderModelState? in
            guard !modelID.isEmpty, seenModelIDs.insert(modelID).inserted else {
                return nil
            }
            return ProviderModelState(id: modelID)
        }
        var state = try await metadataStore.load()
        let previousCredential = try await credentialStore.credential(for: provider)
        let previousSelection = state.configurations[provider]?.selectedModelID
        let configuration = ProviderConfiguration(
            models: models,
            fetchedAt: now(),
            selectedModelID: previousSelection.flatMap { selectedModelID in
                models.contains { $0.id == selectedModelID } ? selectedModelID : nil
            }
        )
        let nextCredential = ProviderCredential(
            generation: makeGeneration(),
            apiKey: apiKey
        )
        state.pendingReplacements[provider] = PendingProviderReplacement(
            previousGeneration: previousCredential?.generation,
            nextGeneration: nextCredential.generation,
            configuration: configuration
        )
        try await metadataStore.save(state)
        do {
            try await credentialStore.replaceCredential(nextCredential, for: provider)
        } catch {
            state.pendingReplacements[provider] = nil
            do {
                try await metadataStore.save(state)
            } catch {
                throw ProviderConfigurationError.inconsistentCredentialState
            }
            throw error
        }
        state.configurations[provider] = configuration
        state.pendingReplacements[provider] = nil
        try await metadataStore.save(state)
        return configuration
    }

    public func reconcilePendingReplacements() async throws -> ProviderMetadataState {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        var state = try await metadataStore.load()
        guard !state.pendingReplacements.isEmpty else {
            return state
        }
        for (provider, pending) in state.pendingReplacements {
            let durableGeneration = try await credentialStore.credential(for: provider)?.generation
            if durableGeneration == pending.nextGeneration {
                state.configurations[provider] = pending.configuration
            } else if durableGeneration != pending.previousGeneration {
                throw ProviderConfigurationError.inconsistentCredentialState
            }
            state.pendingReplacements[provider] = nil
        }
        try await metadataStore.save(state)
        return state
    }

    public func shouldRefreshModelsOnSettingsOpen(
        for provider: ProviderID
    ) async throws -> Bool {
        guard let configuration = try await metadataStore.load().configurations[provider] else {
            return true
        }
        return now().timeIntervalSince(configuration.fetchedAt) >= Self.modelCacheLifetime
    }

    public func refreshModels(for provider: ProviderID) async throws -> ProviderConfiguration {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        guard let credential = try await credentialStore.credential(for: provider) else {
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
        var state = try await metadataStore.load()
        let previousSelection = state.configurations[provider]?.selectedModelID
        let refreshed = ProviderConfiguration(
            models: models,
            fetchedAt: now(),
            selectedModelID: previousSelection.flatMap { selectedModelID in
                models.contains { $0.id == selectedModelID } ? selectedModelID : nil
            }
        )
        state.configurations[provider] = refreshed
        try await metadataStore.save(state)
        return refreshed
    }

    public func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) async throws -> ProviderConfiguration {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        guard try await credentialStore.credential(for: provider) != nil else {
            throw ProviderConfigurationError.missingCredential
        }
        var state = try await metadataStore.load()
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
        try await metadataStore.save(state)
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
        guard try await credentialStore.credential(for: provider) != nil else {
            throw ProviderConfigurationError.missingCredential
        }
        var state = try await metadataStore.load()
        guard state.configurations[provider]?.isUsable == true else {
            throw ProviderConfigurationError.providerNotUsable
        }
        state.currentProvider = provider
        try await metadataStore.save(state)
    }

    public func clearProvider(_ provider: ProviderID) async throws {
        try beginConfigurationMutation()
        defer { endConfigurationMutation() }
        try await credentialStore.deleteCredential(for: provider)
        var state = try await metadataStore.load()
        state.configurations[provider] = nil
        state.pendingReplacements[provider] = nil
        try await metadataStore.save(state)
    }

    public func recordVisionSuccess(
        provider: ProviderID,
        modelID: String
    ) async throws {
        var state = try await metadataStore.load()
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
        try await metadataStore.save(state)
    }

    public func recordVisionFailure(
        provider: ProviderID,
        modelID: String,
        evidence: VisionFailureEvidence
    ) async throws {
        guard evidence == .imageInputUnsupported else {
            return
        }
        var state = try await metadataStore.load()
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
        try await metadataStore.save(state)
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

    private func endConfigurationMutation() {
        configurationMutationInProgress = false
    }

}
