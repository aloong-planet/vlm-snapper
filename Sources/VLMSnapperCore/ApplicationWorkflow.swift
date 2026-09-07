import Foundation

public enum CaptureEntryPoint: Sendable, CaseIterable {
    case shortcut
    case menu
}

/// Shared production admission for native capture entry points and result runs.
/// The native application supplies screen/window effects only after admission.
@MainActor
public final class ApplicationWorkflow {
    private let coordinator: ProviderConfigurationCoordinator

    public init(coordinator: ProviderConfigurationCoordinator) {
        self.coordinator = coordinator
    }

    @discardableResult
    public func capture(
        from source: CaptureEntryPoint,
        replacing owner: UUID? = nil,
        presentProvider: (ProviderID) -> Void,
        presentOperation: () -> Void = {},
        perform: (UUID) async -> Bool
    ) async -> Bool {
        let lease: UUID
        do { lease = try await coordinator.beginCaptureActivity(replacing: owner) }
        catch {
            switch await coordinator.currentActivity() {
            case let .credential(provider): presentProvider(provider)
            case .modelRequest: presentOperation()
            case .capture, nil: break
            }
            return false
        }
        guard !Task.isCancelled else {
            if lease != owner { await coordinator.release(lease) }
            return false
        }
        let accepted = await perform(lease)
        if !accepted, lease != owner { await coordinator.release(lease) }
        return accepted
    }

    @discardableResult
    public func performOperation(
        continuingCapture owner: UUID? = nil,
        operation: () async throws -> Void
    ) async throws -> Bool {
        let lease: UUID
        do {
            if let owner {
                try await coordinator.transitionCaptureToModelRequest(owner)
                lease = owner
            } else {
                lease = try await coordinator.beginRequestConfigurationFreeze()
            }
        } catch { return false }
        do {
            try Task.checkCancellation()
            try await operation()
        } catch {
            await coordinator.release(lease)
            throw error
        }
        await coordinator.release(lease)
        return true
    }
}
