import Testing
@testable import VLMSnapperCore

@Suite("Login item")
struct LoginItemCoordinatorTests {
    @Test("Default enablement rereads approval state")
    func defaultEnablementRereadsStatus() async throws {
        let service = LoginItemServiceProbe(
            statuses: [.disabled, .requiresApproval]
        )
        let preference = LoginItemPreferenceProbe(value: nil)
        let coordinator = LoginItemCoordinator(service: service, preference: preference)

        let state = try await coordinator.configureAtPrimaryLaunch()

        #expect(state == .requiresApproval)
        #expect(await service.registerCalls == 1)
        #expect(await preference.value == true)
    }

    @Test("Disabled user preference survives the next launch")
    func disabledPreferenceSurvivesLaunch() async throws {
        let service = LoginItemServiceProbe(
            statuses: [.enabled, .disabled, .disabled]
        )
        let preference = LoginItemPreferenceProbe(value: true)
        let coordinator = LoginItemCoordinator(service: service, preference: preference)

        #expect(try await coordinator.setEnabled(false) == .disabled)
        #expect(await preference.value == false)

        let nextCoordinator = LoginItemCoordinator(service: service, preference: preference)
        #expect(try await nextCoordinator.configureAtPrimaryLaunch() == .disabled)
        #expect(await service.registerCalls == 0)
        #expect(await service.unregisterCalls == 1)
    }
}

private actor LoginItemServiceProbe: LoginItemServicing {
    private var statuses: [LoginItemState]
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    init(statuses: [LoginItemState]) {
        self.statuses = statuses
    }

    func status() -> LoginItemState {
        statuses.count > 1 ? statuses.removeFirst() : statuses[0]
    }

    func register() throws {
        registerCalls += 1
    }

    func unregister() throws {
        unregisterCalls += 1
    }

    func openSystemSettings() {}
}

private actor LoginItemPreferenceProbe: LoginItemPreferenceStoring {
    var value: Bool?

    init(value: Bool?) {
        self.value = value
    }

    func load() -> Bool? { value }
    func save(_ value: Bool) { self.value = value }
}
