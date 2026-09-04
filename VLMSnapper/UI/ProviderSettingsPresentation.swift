import VLMSnapperCore

public enum ProviderInlineCredentialStatus: Equatable, Sendable {
    case notConfigured
    case pending
    case validating
    case configured
    case failed
}

public enum ProviderInlineCardStatus: Equatable, Sendable {
    case notConfigured
    case pendingValidation
    case validating
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
            if snapshot.phase == .validating {
                status = .validating
                return
            }
            if snapshot.phase == .failed {
                status = .failed
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

    public init(
        isConfigured: Bool,
        isSelected: Bool,
        isDirty: Bool,
        phase: ProviderSetupPhase,
        hasAPIKey: Bool,
        isReadOnly: Bool
    ) {
        let selectedKeyIsDirty = isSelected && isDirty
        if isSelected, phase == .validating {
            status = .validating
        } else if isSelected, phase == .failed {
            status = .failed
        } else if selectedKeyIsDirty {
            status = .pending
        } else if isConfigured {
            status = .configured
        } else {
            status = .notConfigured
        }

        showsValidation = !isConfigured || selectedKeyIsDirty
            || status == .validating || status == .failed
        canValidate = showsValidation && hasAPIKey
            && status != .validating && !isReadOnly
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
