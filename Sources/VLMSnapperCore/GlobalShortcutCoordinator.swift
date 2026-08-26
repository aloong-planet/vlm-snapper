import Foundation

public struct GlobalShortcutModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}

public struct GlobalShortcut: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: GlobalShortcutModifiers

    public init(
        keyCode: UInt32,
        modifiers: GlobalShortcutModifiers
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultCapture = GlobalShortcut(
        keyCode: 1,
        modifiers: [.option, .shift]
    )
}

public enum GlobalShortcutError: Error, Equatable {
    case primaryModifierRequired
    case unsupportedKey
}

public enum GlobalShortcutRegistrationError: Error, Equatable {
    case conflict
    case registrationFailed(status: Int32)
}

@MainActor
public protocol GlobalShortcutRegistration: AnyObject {
    func unregister()
}

@MainActor
public protocol GlobalShortcutRegistrationBackend: AnyObject {
    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration
}

@MainActor
public final class GlobalShortcutCoordinator {
    private static let reservedKeyCodes: Set<UInt32> = [
        36, 53, 76, 123, 124, 125, 126,
    ]

    private let backend: any GlobalShortcutRegistrationBackend
    private let onTrigger: @MainActor @Sendable () -> Void
    private var registration: (any GlobalShortcutRegistration)?
    public private(set) var currentShortcut: GlobalShortcut?

    public init(
        backend: any GlobalShortcutRegistrationBackend,
        onTrigger: @escaping @MainActor @Sendable () -> Void
    ) {
        self.backend = backend
        self.onTrigger = onTrigger
    }

    isolated deinit {
        registration?.unregister()
    }

    public func replaceShortcut(with shortcut: GlobalShortcut) throws {
        try validate(shortcut)
        guard shortcut != currentShortcut else {
            return
        }
        let newRegistration = try backend.register(
            shortcut,
            handler: onTrigger
        )
        let oldRegistration = registration
        registration = newRegistration
        currentShortcut = shortcut
        oldRegistration?.unregister()
    }

    public func unregister() {
        registration?.unregister()
        registration = nil
        currentShortcut = nil
    }

    private func validate(_ shortcut: GlobalShortcut) throws {
        let primaryModifiers: GlobalShortcutModifiers = [
            .command, .option, .control,
        ]
        guard !shortcut.modifiers.intersection(primaryModifiers).isEmpty else {
            throw GlobalShortcutError.primaryModifierRequired
        }
        guard !Self.reservedKeyCodes.contains(shortcut.keyCode) else {
            throw GlobalShortcutError.unsupportedKey
        }
    }
}
