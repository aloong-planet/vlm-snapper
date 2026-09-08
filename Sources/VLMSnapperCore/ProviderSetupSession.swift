public protocol ProviderSetupConfiguring: Sendable {
    func currentActivity() async -> ProviderWorkflowActivity?
    func configurationState() async throws -> ProviderMetadataState
    func reconcileCredentialState(
        for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void
    ) async throws -> ProviderMetadataState
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
    case recovering
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
    public let activity: ProviderWorkflowActivity?
    public let refreshingProvider: ProviderID?
    public let modelRefreshFailure: ProviderSetupFailure?

    public var blocksConfigurationChanges: Bool { isReadOnly || activity != nil }

    public init(
        selectedProvider: ProviderID,
        availableModelIDs: [String],
        selectedModelID: String?,
        phase: ProviderSetupPhase,
        failure: ProviderSetupFailure?,
        isReadOnly: Bool = false,
        activity: ProviderWorkflowActivity? = nil,
        refreshingProvider: ProviderID? = nil,
        modelRefreshFailure: ProviderSetupFailure? = nil
    ) {
        self.selectedProvider = selectedProvider
        self.availableModelIDs = availableModelIDs
        self.selectedModelID = selectedModelID
        self.phase = phase
        self.failure = failure
        self.isReadOnly = isReadOnly
        self.activity = activity
        self.refreshingProvider = refreshingProvider
        self.modelRefreshFailure = modelRefreshFailure
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
    private var credentialReadFailed = false
    private var recoveringProviders: Set<ProviderID> = []
    private var validatingProviders: Set<ProviderID> = []
    private var refreshingConfigurations: [ProviderID: ProviderConfiguration] = [:]
    private var modelRefreshFailures: [ProviderID: ProviderSetupFailure] = [:]
    private var validationFailures: [ProviderID: ProviderSetupFailure] = [:]
    private var changeContinuation: AsyncStream<Void>.Continuation?

    public func changes() -> AsyncStream<Void> {
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        changeContinuation = channel.continuation
        return channel.stream
    }

    public init(
        selectedProvider: ProviderID,
        boundary: any ProviderSetupConfiguring
    ) {
        self.selectedProvider = selectedProvider
        self.boundary = boundary
    }

    public func snapshot() async -> ProviderSetupSnapshot {
        let activity = await boundary.currentActivity()
            ?? validatingProviders.first.map(ProviderWorkflowActivity.credential)
            ?? recoveringProviders.first.map(ProviderWorkflowActivity.credential)
        let workflowReadOnly: Bool
        switch activity {
        case .capture, .modelRequest: workflowReadOnly = true
        case let .credential(provider): workflowReadOnly = provider == selectedProvider
        case nil: workflowReadOnly = false
        }
        return ProviderSetupSnapshot(
            selectedProvider: selectedProvider,
            availableModelIDs: configuration?.models.map(\.id) ?? [],
            selectedModelID: configuration?.selectedModelID,
            phase: phase,
            failure: failure,
            isReadOnly: isReadOnly || credentialReadFailed || workflowReadOnly,
            activity: activity,
            refreshingProvider: refreshingConfigurations.keys.first,
            modelRefreshFailure: modelRefreshFailures[selectedProvider]
        )
    }

    public func setReadOnly(_ isReadOnly: Bool) {
        self.isReadOnly = isReadOnly
        changeContinuation?.yield(())
    }

    public func load(onRecovery: @escaping @Sendable () async -> Void = {}) async {
        defer { changeContinuation?.yield(()) }
        if let refreshing = refreshingConfigurations[selectedProvider] {
            apply(refreshing)
            return
        }
        if recoveringProviders.contains(selectedProvider) {
            configuration = nil
            phase = .recovering
            failure = nil
            return
        }
        if validatingProviders.contains(selectedProvider) {
            configuration = nil
            phase = .validating
            failure = nil
            return
        }
        if let storedFailure = validationFailures[selectedProvider], storedFailure != .secureStorage {
            configuration = nil
            failure = storedFailure
            phase = .failed
            return
        }
        let requestGeneration = generation
        let provider = selectedProvider
        do {
            if let activeProvider = await boundary.currentActivity()?.provider, activeProvider != provider {
                let state = try await boundary.configurationState()
                guard requestGeneration == generation, provider == selectedProvider else { return }
                apply(state.configurations[provider])
                return
            }
            let state = try await boundary.reconcileCredentialState(for: provider) {
                await self.recoveryStarted(for: provider)
                await onRecovery()
            }
            let wasRecovering = recoveringProviders.remove(provider) != nil
            guard provider == selectedProvider, requestGeneration == generation || wasRecovering else {
                return
            }
            credentialReadFailed = false
            if state.configurations[provider] == nil, let storedFailure = validationFailures[provider] {
                configuration = nil
                failure = storedFailure
                phase = .failed
            } else {
                validationFailures[provider] = nil
                apply(state.configurations[selectedProvider])
            }
        } catch {
            let wasRecovering = recoveringProviders.remove(provider) != nil
            guard !Task.isCancelled else { return }
            guard provider == selectedProvider, requestGeneration == generation || wasRecovering else {
                return
            }
            setFailure(error)
            credentialReadFailed = classifyFailure(error) == .secureStorage
        }
    }

    private func recoveryStarted(for provider: ProviderID) {
        recoveringProviders.insert(provider)
        if selectedProvider == provider {
            configuration = nil
            phase = .recovering
            failure = nil
        }
        changeContinuation?.yield(())
    }

    public func selectProvider(
        _ provider: ProviderID,
        onRecovery: @escaping @Sendable () async -> Void = {}
    ) async {
        generation += 1
        selectedProvider = provider
        configuration = nil
        phase = .awaitingValidation
        failure = nil
        credentialReadFailed = false
        changeContinuation?.yield(())
        await load(onRecovery: onRecovery)
    }

    public func validate(apiKey: String) async {
        await validate(apiKey: apiKey, for: selectedProvider)
    }

    @discardableResult
    public func validate(apiKey: String, for provider: ProviderID) async -> Bool {
        let activity = await boundary.currentActivity()
        guard activity == nil, !isReadOnly, recoveringProviders.isEmpty, validatingProviders.isEmpty,
              !(provider == selectedProvider && credentialReadFailed),
              validatingProviders.insert(provider).inserted else {
            return false
        }
        defer {
            validatingProviders.remove(provider)
            changeContinuation?.yield(())
        }
        validationFailures[provider] = nil
        modelRefreshFailures[provider] = nil
        if provider == selectedProvider {
            generation += 1
            configuration = nil
            phase = .validating
            failure = nil
        }
        do {
            let validated = try await boundary.validateAndSaveKey(apiKey, for: provider)
            guard provider == selectedProvider else {
                return true
            }
            generation += 1
            apply(validated)
            return true
        } catch {
            validationFailures[provider] = classifyFailure(error)
            guard provider == selectedProvider else {
                return false
            }
            generation += 1
            setFailure(error)
            return false
        }
    }

    public func clearValidationFailure(for provider: ProviderID) {
        validationFailures[provider] = nil
        modelRefreshFailures[provider] = nil
    }

    public func credentialReadDidFail(
        for provider: ProviderID,
        isCurrent: @escaping @Sendable () async -> Bool
    ) async {
        let readGeneration = generation
        guard await isCurrent(), readGeneration == generation else { return }
        guard selectedProvider == provider else { return }
        configuration = nil
        failure = .secureStorage
        phase = .failed
        credentialReadFailed = true
        changeContinuation?.yield(())
    }

    public func refreshModels() async {
        guard !(await snapshot()).blocksConfigurationChanges, let configuration else { return }
        generation += 1
        let provider = selectedProvider
        refreshingConfigurations[provider] = configuration
        modelRefreshFailures[provider] = nil
        validatingProviders.insert(provider)
        defer {
            refreshingConfigurations[provider] = nil
            validatingProviders.remove(provider)
            changeContinuation?.yield(())
        }
        failure = nil
        changeContinuation?.yield(())
        do {
            let refreshed = try await boundary.refreshModels(for: provider)
            guard provider == selectedProvider, !credentialReadFailed else {
                return
            }
            generation += 1
            apply(refreshed)
        } catch {
            let refreshFailure = classifyFailure(error)
            if refreshFailure == .unavailable {
                modelRefreshFailures[provider] = refreshFailure
            }
            guard provider == selectedProvider, !credentialReadFailed else {
                return
            }
            generation += 1
            if refreshFailure == .unavailable {
                apply(configuration)
            } else {
                setFailure(error)
            }
        }
    }

    public func selectModel(_ modelID: String) async {
        guard !(await snapshot()).blocksConfigurationChanges else { return }
        generation += 1
        let requestGeneration = generation
        let provider = selectedProvider
        failure = nil
        modelRefreshFailures[provider] = nil
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
            modelRefreshFailures[selectedProvider] = nil
            phase = .awaitingValidation
            return
        }
        phase = configuration.selectedModelID == nil ? .selectingModel : .ready
    }

    private func setFailure(_ error: any Error) {
        failure = classifyFailure(error)
        phase = .failed
    }

    private func classifyFailure(_ error: any Error) -> ProviderSetupFailure {
        if let configurationError = error as? ProviderConfigurationError {
            return switch configurationError {
            case .configurationLocked, .configurationMutationInProgress:
                .configurationLocked
            case .missingCredential, .providerNotUsable, .modelNotFound,
                 .incompatibleModel:
                .invalidConfiguration
            case .inconsistentCredentialState:
                .secureStorage
            }
        } else if let modelListError = error as? ProviderModelListError,
                  modelListError == .authenticationRejected {
            return .invalidConfiguration
        } else if error is AppleKeychainError || error is ProviderPersistenceError {
            return .secureStorage
        } else {
            return .unavailable
        }
    }
}
