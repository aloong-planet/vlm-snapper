import VLMSnapperCore

public struct ProviderSettingsDetailPresentation: Equatable, Sendable {
    public let detail: String
    public let isConfigured: Bool

    public init(
        provider: ProviderID,
        snapshot: ProviderSetupSnapshot,
        configurations: [ProviderID: ProviderConfiguration]
    ) {
        if provider == snapshot.selectedProvider {
            switch snapshot.phase {
            case .validating, .recovering:
                detail = snapshot.phase == .recovering ? VLMSnapperStrings.recovering : VLMSnapperStrings.validating
                isConfigured = false
                return
            case .selectingModel:
                detail = VLMSnapperStrings.modelPending
                isConfigured = false
                return
            case .ready:
                detail = snapshot.selectedModelID ?? VLMSnapperStrings.modelPending
                isConfigured = snapshot.selectedModelID != nil
                return
            case .failed:
                detail = snapshot.failure == .secureStorage
                    ? VLMSnapperStrings.providerStorageFailure : VLMSnapperStrings.failed
                isConfigured = false
                return
            case .awaitingValidation:
                break
            }
        }

        if let configuration = configurations[provider] {
            detail = configuration.selectedModelID ?? VLMSnapperStrings.modelPending
            isConfigured = configuration.isUsable
        } else {
            detail = VLMSnapperStrings.notConfigured
            isConfigured = false
        }
    }
}

public enum ProviderInlineCredentialStatus: Equatable, Sendable {
    case notConfigured
    case pending
    case validating
    case recovering
    case storageFailure
    case configured
    case failed
}

public enum ProviderInlineCardStatus: Equatable, Sendable {
    case notConfigured
    case pendingValidation
    case validating
    case recovering
    case storageFailure
    case pendingModel
    case ready
    case failed
}

public struct ProviderInlineCardPresentation: Equatable, Sendable {
    public let status: ProviderInlineCardStatus

    public init(
        provider: ProviderID,
        snapshot: ProviderSetupSnapshot,
        configuration: ProviderConfiguration?,
        isDirty: Bool
    ) {
        if provider == snapshot.selectedProvider {
            if snapshot.phase == .recovering {
                status = .recovering
                return
            }
            if snapshot.phase == .validating {
                status = .validating
                return
            }
            if snapshot.phase == .failed {
                status = snapshot.failure == .secureStorage ? .storageFailure : .failed
                return
            }
            if isDirty {
                status = .pendingValidation
                return
            }
            if snapshot.phase == .selectingModel
                || snapshot.phase == .ready && snapshot.selectedModelID == nil {
                status = .pendingModel
                return
            }
            if snapshot.phase == .ready {
                status = .ready
                return
            }
        }

        if configuration?.isUsable == true {
            status = .ready
        } else if configuration != nil {
            status = .pendingModel
        } else {
            status = .notConfigured
        }
    }
}

public struct ProviderInlineCredentialPresentation: Equatable, Sendable {
    public let status: ProviderInlineCredentialStatus
    public let showsValidation: Bool
    public let canValidate: Bool
    public let localInputHint: String?

    public init(
        isConfigured: Bool,
        isSelected: Bool,
        isDirty: Bool,
        phase: ProviderSetupPhase,
        hasAPIKey: Bool,
        isReadOnly: Bool,
        inputIssue: ProviderAPIKeyInputIssue? = nil,
        failure: ProviderSetupFailure? = nil
    ) {
        localInputHint = switch inputIssue {
        case .empty: VLMSnapperStrings.providerEnterKey
        case .containsNewline: VLMSnapperStrings.providerKeyContainsNewline
        case .tooLong: VLMSnapperStrings.providerKeyTooLong
        case nil: nil
        }
        let selectedKeyIsDirty = isSelected && isDirty
        if isSelected, phase == .recovering {
            status = .recovering
        } else if isSelected, phase == .validating {
            status = .validating
        } else if isSelected, phase == .failed {
            status = failure == .secureStorage ? .storageFailure : .failed
        } else if selectedKeyIsDirty {
            status = .pending
        } else if isConfigured {
            status = .configured
        } else {
            status = .notConfigured
        }

        showsValidation = status != .recovering && !(status == .storageFailure && isReadOnly)
            && (!isConfigured || selectedKeyIsDirty || status == .validating
                || status == .failed || status == .storageFailure)
        canValidate = showsValidation && selectedKeyIsDirty && hasAPIKey
            && status != .validating && status != .recovering && !isReadOnly && inputIssue == nil
    }
}

public enum ProviderSettingsInitialSelection {
    public static func resolve(
        explicitTarget: ProviderID?,
        currentProvider: ProviderID?
    ) -> ProviderID {
        explicitTarget ?? currentProvider ?? .deepSeek
    }
}

public struct ProviderSettingsReturnContext: Equatable, Sendable {
    private var returnsToOnboarding = false

    public init() {}

    public mutating func beginFromOnboarding() {
        returnsToOnboarding = true
    }

    public mutating func consumeAfterModelSelection() -> Bool {
        consume()
    }

    public mutating func consumeAfterWindowClose() -> Bool {
        consume()
    }

    private mutating func consume() -> Bool {
        guard returnsToOnboarding else { return false }
        returnsToOnboarding = false
        return true
    }
}
