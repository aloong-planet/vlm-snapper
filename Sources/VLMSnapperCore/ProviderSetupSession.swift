public protocol ProviderSetupConfiguring: Sendable {
    func configurationState() async throws -> ProviderMetadataState
    func validateAndSaveKey(
        _ apiKey: String,
        for provider: ProviderID
    ) async throws -> ProviderConfiguration
    func refreshModels(for provider: ProviderID) async throws -> ProviderConfiguration
    func selectModel(
        _ modelID: String,
        for provider: ProviderID
    ) async throws -> ProviderConfiguration
}

public enum ProviderSetupPhase: Equatable, Sendable {
    case awaitingValidation
    case validating
    case selectingModel
    case ready
    case failed
}

public enum ProviderSetupFailure: Equatable, Sendable {
    case configurationLocked
    case invalidConfiguration
    case secureStorage
    case unavailable
}

public struct ProviderSetupSnapshot: Equatable, Sendable {
    public let selectedProvider: ProviderID
    public let availableModelIDs: [String]
    public let selectedModelID: String?
    public let phase: ProviderSetupPhase
    public let failure: ProviderSetupFailure?
    public let isReadOnly: Bool

    public init(
        selectedProvider: ProviderID,
        availableModelIDs: [String],
        selectedModelID: String?,
        phase: ProviderSetupPhase,
        failure: ProviderSetupFailure?,
        isReadOnly: Bool = false
    ) {
        self.selectedProvider = selectedProvider
        self.availableModelIDs = availableModelIDs
        self.selectedModelID = selectedModelID
        self.phase = phase
        self.failure = failure
        self.isReadOnly = isReadOnly
    }

    public var canFinish: Bool {
        phase == .ready && selectedModelID != nil
    }
}

public actor ProviderSetupSession {
    private let boundary: any ProviderSetupConfiguring
    private var selectedProvider: ProviderID
    private var configuration: ProviderConfiguration?
    private var phase: ProviderSetupPhase = .awaitingValidation
    private var failure: ProviderSetupFailure?
    private var generation = 0
    private var isReadOnly = false

    public init(
        selectedProvider: ProviderID,
        boundary: any ProviderSetupConfiguring
    ) {
        self.selectedProvider = selectedProvider
        self.boundary = boundary
    }

    public func snapshot() -> ProviderSetupSnapshot {
        ProviderSetupSnapshot(
            selectedProvider: selectedProvider,
            availableModelIDs: configuration?.models.map(\.id) ?? [],
            selectedModelID: configuration?.selectedModelID,
            phase: phase,
            failure: failure,
            isReadOnly: isReadOnly
        )
    }

    public func setReadOnly(_ isReadOnly: Bool) {
        self.isReadOnly = isReadOnly
    }

    public func load() async {
        let requestGeneration = generation
        do {
            let state = try await boundary.configurationState()
            guard requestGeneration == generation else {
                return
            }
            apply(state.configurations[selectedProvider])
        } catch {
            guard requestGeneration == generation else {
                return
            }
            setFailure(error)
        }
    }

    public func selectProvider(_ provider: ProviderID) async {
        generation += 1
        selectedProvider = provider
        configuration = nil
        phase = .awaitingValidation
        failure = nil
        await load()
    }

    public func validate(apiKey: String) async {
        guard !isReadOnly else {
            return
        }
        generation += 1
        let requestGeneration = generation
        let provider = selectedProvider
        phase = .validating
        failure = nil
        do {
            let validated = try await boundary.validateAndSaveKey(apiKey, for: provider)
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            apply(validated)
        } catch {
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            setFailure(error)
        }
    }

    public func refreshModels() async {
        guard !isReadOnly else {
            return
        }
        generation += 1
        let requestGeneration = generation
        let provider = selectedProvider
        phase = .validating
        failure = nil
        do {
            let refreshed = try await boundary.refreshModels(for: provider)
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            apply(refreshed)
        } catch {
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            setFailure(error)
        }
    }

    public func selectModel(_ modelID: String) async {
        guard !isReadOnly else {
            return
        }
        generation += 1
        let requestGeneration = generation
        let provider = selectedProvider
        failure = nil
        do {
            let selected = try await boundary.selectModel(modelID, for: provider)
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            apply(selected)
        } catch {
            guard requestGeneration == generation, provider == selectedProvider else {
                return
            }
            setFailure(error)
        }
    }

    private func apply(_ configuration: ProviderConfiguration?) {
        self.configuration = configuration
        failure = nil
        guard let configuration else {
            phase = .awaitingValidation
            return
        }
        phase = configuration.selectedModelID == nil ? .selectingModel : .ready
    }

    private func setFailure(_ error: any Error) {
        if let configurationError = error as? ProviderConfigurationError {
            failure = switch configurationError {
            case .configurationLocked, .configurationMutationInProgress:
                .configurationLocked
            case .missingCredential, .providerNotUsable, .modelNotFound,
                 .incompatibleModel, .inconsistentCredentialState:
                .invalidConfiguration
            }
        } else if let modelListError = error as? ProviderModelListError,
                  modelListError == .authenticationRejected {
            failure = .invalidConfiguration
        } else if error is AppleKeychainError {
            failure = .secureStorage
        } else {
            failure = .unavailable
        }
        phase = .failed
    }
}
