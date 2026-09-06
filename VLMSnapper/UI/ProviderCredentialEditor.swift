import Combine
import Foundation
import VLMSnapperCore

public struct ProviderCredentialSubmission: Sendable {
    public let provider: ProviderID
    public let value: String
    fileprivate let id = UUID()
}

public struct ProviderCredentialLoad: Sendable {
    public let provider: ProviderID
    fileprivate let id = UUID()
}

/// The window's single source of truth for opaque credential text and its baseline.
@MainActor
public final class ProviderCredentialEditor: ObservableObject {
    @Published public private(set) var value: String
    @Published private var submissions: [ProviderID: ProviderCredentialSubmission] = [:]
    private var failedCandidates: [ProviderID: String] = [:]
    @Published public private(set) var isLoading = false
    private var baseline: String?
    private var loadID: UUID?
    @Published public private(set) var provider: ProviderID? = .deepSeek

    public var isSubmitting: Bool {
        provider.map { submissions[$0] != nil } ?? false
    }

    public var isOpen: Bool { provider != nil }

    public func beginLoading(for provider: ProviderID) -> ProviderCredentialLoad {
        self.provider = provider
        baseline = nil
        value = submissions[provider]?.value ?? failedCandidates[provider] ?? ""
        let request = ProviderCredentialLoad(provider: provider)
        loadID = request.id
        isLoading = submissions[provider] == nil && failedCandidates[provider] == nil
        return request
    }

    public func completeLoad(_ request: ProviderCredentialLoad, value: String) {
        guard accepts(request), isLoading, !isSubmitting else { return }
        load(value)
    }

    public func accepts(_ request: ProviderCredentialLoad) -> Bool {
        provider == request.provider && loadID == request.id
    }

    public init(loadedValue: String = "") {
        value = loadedValue
        baseline = loadedValue
    }

    public var isDirty: Bool {
        guard let baseline else { return !value.isEmpty }
        return !value.utf8.elementsEqual(baseline.utf8)
    }

    public func edit(_ value: String) {
        guard isOpen, !isSubmitting, !isLoading else { return }
        if let provider, !self.value.utf8.elementsEqual(value.utf8) {
            failedCandidates[provider] = nil
        }
        self.value = value
    }

    public func load(_ value: String) {
        if let provider { failedCandidates[provider] = nil }
        loadID = nil
        isLoading = false
        baseline = value
        self.value = value
    }

    public func close() {
        loadID = nil
        provider = nil
        baseline = nil
        value = ""
        isLoading = false
    }

    public func configurationWasRemoved(for provider: ProviderID) {
        failedCandidates[provider] = nil
        if self.provider == provider { load("") }
    }

    @discardableResult
    public func submit(
        for provider: ProviderID,
        isReadOnly: Bool,
        operation: (ProviderCredentialSubmission) -> Void
    ) -> Bool {
        guard !isReadOnly, !isSubmitting, !isLoading, self.provider == provider, isDirty,
              ProviderAPIKeyInput.issue(in: value) == nil else { return false }
        let submission = ProviderCredentialSubmission(provider: provider, value: value)
        // Replacement discards the old secret before dispatch, without a rollback copy.
        baseline = nil
        failedCandidates[provider] = nil
        submissions[provider] = submission
        operation(submission)
        return true
    }

    public func complete(_ submission: ProviderCredentialSubmission, succeeded: Bool) {
        guard submissions[submission.provider]?.id == submission.id else { return }
        failedCandidates[submission.provider] = succeeded ? nil : submission.value
        if provider == submission.provider {
            loadID = nil
            baseline = succeeded ? submission.value : nil
            value = submission.value
            isLoading = false
        }
        submissions[submission.provider] = nil
    }
}
