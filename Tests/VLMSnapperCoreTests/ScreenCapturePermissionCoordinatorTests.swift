import Testing
@testable import VLMSnapperCore

@Suite("Screen capture permission coordinator")
struct ScreenCapturePermissionCoordinatorTests {
    @Test("refreshing status never requests permission")
    func refreshIsPreflightOnly() async throws {
        let authorizer = PermissionAuthorizerProbe(hasAccess: false, requestResult: false)
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: MemoryPermissionRequestHistory()
        )

        #expect(try await coordinator.refreshStatus() == .notRequested)
        #expect(await authorizer.requestCount == 0)
    }

    @Test("the first explicit action records the attempt and requests once")
    func firstExplicitActionRequestsOnce() async throws {
        let history = MemoryPermissionRequestHistory()
        let authorizer = PermissionAuthorizerProbe(hasAccess: false, requestResult: false)
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: history
        )

        #expect(try await coordinator.performPrimaryAction() == .state(.unavailable))
        #expect(await authorizer.requestCount == 1)
        #expect(await history.hasRequestedPermission())
    }

    @Test("a later action opens settings without repeating the system request")
    func unavailableOpensSettingsWithoutRepeatRequest() async throws {
        let history = MemoryPermissionRequestHistory(hasRequested: true)
        let authorizer = PermissionAuthorizerProbe(hasAccess: false, requestResult: true)
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: history
        )

        #expect(try await coordinator.performPrimaryAction() == .openSystemSettings)
        #expect(await authorizer.requestCount == 0)
    }

    @Test("an accepted request requires restart until a later process sees access")
    func acceptedRequestRequiresRestart() async throws {
        let authorizer = PermissionAuthorizerProbe(hasAccess: false, requestResult: true)
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: MemoryPermissionRequestHistory()
        )

        #expect(try await coordinator.performPrimaryAction() == .state(.restartRequired))
        #expect(try await coordinator.refreshStatus() == .restartRequired)
    }

    @Test("preflight access is ready without requesting")
    func preflightAccessIsReady() async throws {
        let authorizer = PermissionAuthorizerProbe(hasAccess: true, requestResult: false)
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: MemoryPermissionRequestHistory(hasRequested: true)
        )

        #expect(try await coordinator.refreshStatus() == .ready)
        #expect(await authorizer.requestCount == 0)
    }

    @Test("overlapping permission actions never open settings during the system request")
    func overlappingActionsAreCoalesced() async throws {
        let authorizer = SuspendedPermissionAuthorizer()
        let coordinator = ScreenCapturePermissionCoordinator(
            authorizer: authorizer,
            requestHistory: MemoryPermissionRequestHistory()
        )
        let firstAction = Task {
            try await coordinator.performPrimaryAction()
        }
        await authorizer.waitUntilRequestStarts()

        #expect(try await coordinator.performPrimaryAction() == .noAction)
        await authorizer.finishRequest(result: false)
        #expect(try await firstAction.value == .state(.unavailable))
        #expect(await authorizer.requestCount == 1)
    }
}

private actor PermissionAuthorizerProbe: ScreenCapturePermissionAuthorizing {
    let hasAccess: Bool
    let requestResult: Bool
    private(set) var requestCount = 0

    init(hasAccess: Bool, requestResult: Bool) {
        self.hasAccess = hasAccess
        self.requestResult = requestResult
    }

    func preflightScreenCaptureAccess() -> Bool {
        hasAccess
    }

    func requestScreenCaptureAuthorization() -> Bool {
        requestCount += 1
        return requestResult
    }
}

private actor MemoryPermissionRequestHistory: PermissionRequestHistoryStoring {
    private var hasRequested: Bool

    init(hasRequested: Bool = false) {
        self.hasRequested = hasRequested
    }

    func hasRequestedPermission() -> Bool {
        hasRequested
    }

    func markPermissionRequested() {
        hasRequested = true
    }
}

private actor SuspendedPermissionAuthorizer: ScreenCapturePermissionAuthorizing {
    private var requestStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var requestContinuation: CheckedContinuation<Bool, Never>?
    private(set) var requestCount = 0

    func preflightScreenCaptureAccess() -> Bool {
        false
    }

    func requestScreenCaptureAuthorization() async -> Bool {
        requestCount += 1
        requestStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func waitUntilRequestStarts() async {
        guard !requestStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishRequest(result: Bool) {
        requestContinuation?.resume(returning: result)
        requestContinuation = nil
    }
}
