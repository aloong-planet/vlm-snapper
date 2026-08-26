import Testing
@testable import VLMSnapperCore

@Suite("Global shortcut coordinator")
@MainActor
struct GlobalShortcutCoordinatorTests {
    @Test("the default shortcut is Option Shift S")
    func defaultShortcut() {
        #expect(GlobalShortcut.defaultCapture.keyCode == 1)
        #expect(GlobalShortcut.defaultCapture.modifiers == [.option, .shift])
    }

    @Test("shortcuts without Command Option or Control are rejected")
    func rejectsUnsafeShortcut() {
        let backend = ShortcutBackendProbe()
        let coordinator = GlobalShortcutCoordinator(backend: backend) {}

        #expect(throws: GlobalShortcutError.primaryModifierRequired) {
            try coordinator.replaceShortcut(
                with: GlobalShortcut(keyCode: 1, modifiers: [.shift])
            )
        }
        #expect(backend.registeredShortcuts.isEmpty)
    }

    @Test("escape return and arrow keys are rejected even with modifiers")
    func rejectsReservedKeys() {
        let backend = ShortcutBackendProbe()
        let coordinator = GlobalShortcutCoordinator(backend: backend) {}

        for keyCode: UInt32 in [53, 36, 76, 123, 124, 125, 126] {
            #expect(throws: GlobalShortcutError.unsupportedKey) {
                try coordinator.replaceShortcut(
                    with: GlobalShortcut(keyCode: keyCode, modifiers: [.command])
                )
            }
        }
    }

    @Test("a failed replacement keeps the old registration active")
    func failedReplacementKeepsOldRegistration() throws {
        let backend = ShortcutBackendProbe()
        let coordinator = GlobalShortcutCoordinator(backend: backend) {}
        try coordinator.replaceShortcut(with: .defaultCapture)
        let firstRegistration = backend.registrations[0]
        backend.nextError = .conflict

        #expect(throws: GlobalShortcutRegistrationError.conflict) {
            try coordinator.replaceShortcut(
                with: GlobalShortcut(keyCode: 8, modifiers: [.control, .option])
            )
        }

        #expect(coordinator.currentShortcut == .defaultCapture)
        #expect(firstRegistration.unregisterCount == 0)
    }

    @Test("a successful replacement activates immediately then unregisters the old shortcut")
    func successfulReplacementIsAtomic() throws {
        let backend = ShortcutBackendProbe()
        let coordinator = GlobalShortcutCoordinator(backend: backend) {}
        try coordinator.replaceShortcut(with: .defaultCapture)
        let firstRegistration = backend.registrations[0]
        let replacement = GlobalShortcut(
            keyCode: 8,
            modifiers: [.control, .option]
        )

        try coordinator.replaceShortcut(with: replacement)

        #expect(coordinator.currentShortcut == replacement)
        #expect(firstRegistration.unregisterCount == 1)
        #expect(backend.registeredShortcuts == [.defaultCapture, replacement])
    }

    @Test("destroying the coordinator unregisters its active shortcut")
    func coordinatorDestructionUnregistersShortcut() throws {
        let backend = ShortcutBackendProbe()
        var coordinator: GlobalShortcutCoordinator? = GlobalShortcutCoordinator(
            backend: backend
        ) {}
        try coordinator?.replaceShortcut(with: .defaultCapture)
        let registration = backend.registrations[0]

        coordinator = nil

        #expect(registration.unregisterCount == 1)
    }
}

@MainActor
private final class ShortcutBackendProbe: GlobalShortcutRegistrationBackend {
    var nextError: GlobalShortcutRegistrationError?
    private(set) var registeredShortcuts: [GlobalShortcut] = []
    private(set) var registrations: [ShortcutRegistrationProbe] = []

    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        if let nextError {
            self.nextError = nil
            throw nextError
        }
        registeredShortcuts.append(shortcut)
        let registration = ShortcutRegistrationProbe()
        registrations.append(registration)
        return registration
    }
}

@MainActor
private final class ShortcutRegistrationProbe: GlobalShortcutRegistration {
    private(set) var unregisterCount = 0

    func unregister() {
        unregisterCount += 1
    }
}
