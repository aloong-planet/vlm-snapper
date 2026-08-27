import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Primary instance")
struct PrimaryInstanceCoordinatorTests {
    @Test("Secondary activation exits before protected initialization")
    func secondarySkipsProtectedInitialization() async throws {
        let lock = PrimaryInstanceLockProbe(acquires: false)
        let messaging = PrimaryInstanceMessagingProbe()
        let initialization = CallCounter()
        let coordinator = PrimaryInstanceCoordinator(lock: lock, messaging: messaging)

        let role = try await coordinator.start(
            onActivation: {},
            initializePrimary: { await initialization.increment() }
        )

        #expect(role == .secondary)
        #expect(await messaging.activationRequests == 1)
        #expect(await messaging.observerRegistrations == 0)
        #expect(await initialization.value == 0)
    }

    @Test("Primary holds lease, observes activation, and initializes once")
    func primaryInitializesOnce() async throws {
        let lock = PrimaryInstanceLockProbe(acquires: true)
        let messaging = PrimaryInstanceMessagingProbe()
        let initialization = CallCounter()
        let activation = CallCounter()
        let coordinator = PrimaryInstanceCoordinator(lock: lock, messaging: messaging)

        let role = try await coordinator.start(
            onActivation: { await activation.increment() },
            initializePrimary: { await initialization.increment() }
        )
        await messaging.deliverActivation()

        #expect(role == .primary)
        #expect(await messaging.observerRegistrations == 1)
        #expect(await initialization.value == 1)
        #expect(await activation.value == 1)
    }

    @Test("POSIX lease excludes a second owner and releases on deinit")
    func posixLeaseIsExclusiveAndRecoverable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLMSnapper-Primary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = POSIXPrimaryInstanceLock(
            lockFileURL: directory.appendingPathComponent("primary.lock")
        )
        var firstLease: (any PrimaryInstanceLease)? = try lock.acquire()

        #expect(firstLease != nil)
        #expect(try lock.acquire() == nil)

        firstLease = nil
        #expect(try lock.acquire() != nil)
    }
}

private final class PrimaryInstanceLeaseProbe: PrimaryInstanceLease, @unchecked Sendable {}

private actor PrimaryInstanceLockProbe: PrimaryInstanceLocking {
    let acquires: Bool

    init(acquires: Bool) {
        self.acquires = acquires
    }

    func acquire() -> (any PrimaryInstanceLease)? {
        acquires ? PrimaryInstanceLeaseProbe() : nil
    }
}

private actor PrimaryInstanceMessagingProbe: PrimaryInstanceMessaging {
    private(set) var activationRequests = 0
    private(set) var observerRegistrations = 0
    private var handler: (@Sendable () async -> Void)?

    func beginObserving(_ handler: @escaping @Sendable () async -> Void) {
        observerRegistrations += 1
        self.handler = handler
    }

    func requestActivation() {
        activationRequests += 1
    }

    func deliverActivation() async {
        await handler?()
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
