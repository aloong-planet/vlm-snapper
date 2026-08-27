import Foundation

public enum LoginItemState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

public protocol LoginItemServicing: Sendable {
    func status() async -> LoginItemState
    func register() async throws
    func unregister() async throws
    func openSystemSettings() async
}

public protocol LoginItemPreferenceStoring: Sendable {
    func load() async -> Bool?
    func save(_ value: Bool) async
}

public actor LoginItemCoordinator {
    private let service: any LoginItemServicing
    private let preference: any LoginItemPreferenceStoring

    public init(
        service: any LoginItemServicing,
        preference: any LoginItemPreferenceStoring
    ) {
        self.service = service
        self.preference = preference
    }

    public func configureAtPrimaryLaunch() async throws -> LoginItemState {
        let storedPreference = await preference.load()
        let shouldEnable = storedPreference ?? true
        if storedPreference == nil {
            await preference.save(true)
        }
        return try await apply(shouldEnable)
    }

    public func setEnabled(_ enabled: Bool) async throws -> LoginItemState {
        await preference.save(enabled)
        return try await apply(enabled)
    }

    public func openSystemSettings() async {
        await service.openSystemSettings()
    }

    private func apply(_ enabled: Bool) async throws -> LoginItemState {
        let current = await service.status()
        if enabled {
            switch current {
            case .enabled, .requiresApproval, .unavailable:
                return current
            case .disabled:
                try await service.register()
                return await service.status()
            }
        } else {
            switch current {
            case .disabled, .unavailable:
                return current
            case .enabled, .requiresApproval:
                try await service.unregister()
                return await service.status()
            }
        }
    }
}

public final class UserDefaultsLoginItemPreferenceStore: LoginItemPreferenceStoring, @unchecked Sendable {
    private static let key = "loginItemEnabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> Bool? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return defaults.bool(forKey: Self.key)
    }

    public func save(_ value: Bool) async {
        defaults.set(value, forKey: Self.key)
    }
}
