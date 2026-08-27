import Foundation
import VLMSnapperHotKeyShim

@MainActor
public final class CarbonGlobalShortcutBackend:
    GlobalShortcutRegistrationBackend
{
    private var nextID: UInt32 = 0
    private var handlers: [UInt32: @MainActor @Sendable () -> Void] = [:]
    private var registrar: VLMHotKeyRegistrarRef?

    public init() throws {
        var status: Int32 = 0
        registrar = VLMHotKeyRegistrarCreate(
            vlmHotKeyCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &status
        )
        guard registrar != nil else {
            throw GlobalShortcutRegistrationError.registrationFailed(
                status: status
            )
        }
    }

    isolated deinit {
        VLMHotKeyRegistrarDestroy(registrar)
    }

    public func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        guard let registrar else {
            throw GlobalShortcutRegistrationError.registrationFailed(status: -1)
        }
        nextID &+= 1
        if nextID == 0 {
            nextID = 1
        }
        let registrationID = nextID
        var registration: VLMHotKeyRegistrationRef?
        let status = VLMHotKeyRegistrarRegister(
            registrar,
            shortcut.keyCode,
            UInt32(shortcut.modifiers.rawValue),
            registrationID,
            &registration
        )
        if status == VLMHotKeyConflictStatus() {
            throw GlobalShortcutRegistrationError.conflict
        }
        guard status == 0, let registration else {
            throw GlobalShortcutRegistrationError.registrationFailed(
                status: status
            )
        }
        handlers[registrationID] = handler
        return CarbonGlobalShortcutRegistration(
            backend: self,
            registrationID: registrationID,
            registration: registration
        )
    }

    fileprivate func unregister(
        registrationID: UInt32,
        registration: VLMHotKeyRegistrationRef
    ) {
        handlers.removeValue(forKey: registrationID)
        guard let registrar else {
            return
        }
        VLMHotKeyRegistrarUnregister(registrar, registration)
    }

    fileprivate func handle(registrationID: UInt32) {
        handlers[registrationID]?()
    }
}

@MainActor
private final class CarbonGlobalShortcutRegistration:
    GlobalShortcutRegistration
{
    private weak var backend: CarbonGlobalShortcutBackend?
    private let registrationID: UInt32
    private var registration: VLMHotKeyRegistrationRef?

    init(
        backend: CarbonGlobalShortcutBackend,
        registrationID: UInt32,
        registration: VLMHotKeyRegistrationRef
    ) {
        self.backend = backend
        self.registrationID = registrationID
        self.registration = registration
    }

    func unregister() {
        guard let registration else {
            return
        }
        self.registration = nil
        backend?.unregister(
            registrationID: registrationID,
            registration: registration
        )
    }
}

private let vlmHotKeyCallback: VLMHotKeyCallback = {
    registrationID, context in
    guard let context else {
        return
    }
    let backend = Unmanaged<CarbonGlobalShortcutBackend>
        .fromOpaque(context)
        .takeUnretainedValue()
    Task { @MainActor [weak backend] in
        backend?.handle(registrationID: registrationID)
    }
}
