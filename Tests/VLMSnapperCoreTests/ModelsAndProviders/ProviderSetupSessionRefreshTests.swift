import Foundation
import Testing
@testable import VLMSnapperCore

// What these tests leave to installed-app checks is in the header of ProviderSetupSessionTests.swift.
extension ProviderSetupSessionTests {
    @Test("concurrent refresh activations retain one busy owner until the external request finishes")
    func concurrentRefreshKeepsBusyOwner() async throws {
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 { group.addTask { await session.refreshModels() } }
            await lister.waitUntilRefreshing()
            for _ in 0..<31 { await group.next() }
            #expect(await session.snapshot().refreshingProvider == .deepSeek)
            #expect(await session.snapshot().phase == .ready)
            #expect(await lister.requests == 2)
            await lister.finish()
        }
        #expect(await session.snapshot().refreshingProvider == nil)
        #expect(await session.snapshot().blocksConfigurationChanges == false)
    }

    @Test("opening a stale card refreshes it once and shows it busy, and a load alone does not")
    func openingAStaleCardRefreshesOnce() async throws {
        let clock = SessionClock()
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)

        await session.load()
        #expect(await lister.requests == 1, "only the validation's")

        let opening = Task { await session.cardOpened(.deepSeek) }
        await lister.waitUntilRefreshing()
        let busy = await session.snapshot()
        #expect(busy.refreshingProvider == .deepSeek)
        #expect(busy.phase == .ready)
        #expect(busy.availableModelIDs == ["model"])
        #expect(busy.selectedModelID == "model")
        await lister.finish()
        await opening.value
        #expect(await session.snapshot().refreshingProvider == nil)
        #expect(await lister.requests == 2)

        await session.cardOpened(.deepSeek)
        #expect(await lister.requests == 2)
    }

    @Test("a cache refreshes from exactly 24 hours", arguments: [(86_399.0, 0), (86_400.0, 1)])
    func cacheAgeBoundary(age: TimeInterval, expectedRequests: Int) async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count
        clock.advance(by: age)

        await session.cardOpened(.deepSeek)

        #expect(await lister.requests.count - before == expectedRequests)
    }

    @Test("opening a card with no key does nothing")
    func openingACardWithNoKeyDoesNothing() async throws {
        let lister = SessionModelLister()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: lister))
        await session.load()

        await session.cardOpened(.deepSeek)

        #expect(await lister.requests.isEmpty)
        let snapshot = await session.snapshot()
        #expect(snapshot.failure == nil)
        #expect(snapshot.modelRefreshFailure == nil)
        #expect(snapshot.phase == .awaitingValidation)
    }

    @Test("a key with no configuration recovers once, and opening adds nothing")
    func recoveryIsTheMissingCacheRefresh() async throws {
        let lister = SessionModelLister()
        let storage = SessionTestStorage()
        await storage.replaceCredential(ProviderCredential(generation: UUID(), apiKey: "fixture-key"), for: .openAI)
        let session = ProviderSetupSession(
            selectedProvider: .deepSeek, boundary: makeCoordinator(modelLister: lister, storage: storage)
        )

        await session.selectProvider(.openAI)
        await session.cardOpened(.openAI)

        #expect(await lister.requests == [.openAI])
        #expect(await session.snapshot().phase == .selectingModel)
    }

    @Test("an opening before its card's load refreshes when the load ends")
    func openingBeforeLoad() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.openAI, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count

        await session.cardOpened(.openAI)
        await session.selectProvider(.openAI)
        #expect(await lister.requests.count == before)

        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before + 1)
        #expect(await lister.requests.last == .openAI)

        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before + 1)
    }

    @Test("an opening after its card's load refreshes at once, and the load's own check adds nothing")
    func openingAfterLoad() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.openAI, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.selectProvider(.openAI)
        let before = await lister.requests.count

        await session.cardOpened(.openAI)
        await session.checkOpenedCardCache()

        #expect(await lister.requests.count == before + 1)
    }

    @Test("an opening during its card's load waits for the load to end")
    func openingDuringLoad() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let storage = SessionTestStorage()
        let coordinator = makeCoordinator(modelLister: lister, storage: storage, now: { clock.now })
        try await configure(.openAI, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count

        await storage.suspendNextRead()
        let load = Task { await session.selectProvider(.openAI) }
        await storage.waitUntilReading()
        await session.cardOpened(.openAI)
        #expect(await lister.requests.count == before)
        await storage.finishReading()
        await load.value
        #expect(await lister.requests.count == before)

        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before + 1)
    }

    @Test("a load with no opening refreshes nothing, and leaving the page drops an opening")
    func aLoadIsNotAnOpening() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.openAI, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count

        await session.selectProvider(.openAI)
        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before)

        await session.selectProvider(.deepSeek)
        await session.cardOpened(.openAI)
        await session.cardOpened(nil)
        await session.selectProvider(.openAI)
        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before)
    }

    @Test("opening a stale card during a capture or a request refreshes nothing", arguments: [false, true])
    func noRefreshDuringAnActivity(isRequest: Bool) async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count
        let lease = try await isRequest ? coordinator.beginRequestConfigurationFreeze() : coordinator.beginCaptureActivity()

        await session.cardOpened(.deepSeek)

        #expect(await lister.requests.count == before)
        let snapshot = await session.snapshot()
        #expect(snapshot.failure == nil)
        #expect(snapshot.modelRefreshFailure == nil)
        #expect(snapshot.phase == .ready)
        #expect(snapshot.selectedModelID == "model")

        await coordinator.release(lease)
        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before, "ending the work starts nothing")
    }

    @Test("opening a stale card during a validation refreshes nothing", arguments: [ProviderID.deepSeek, .openAI])
    func noRefreshDuringAValidation(validating provider: ProviderID) async throws {
        let clock = SessionClock()
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let validation = Task { await session.validate(apiKey: "new-key", for: provider) }
        await lister.waitUntilRefreshing()

        await session.cardOpened(.deepSeek)

        #expect(await lister.requests == 2, "only the two validations'")
        let snapshot = await session.snapshot()
        #expect(snapshot.failure == nil)
        #expect(snapshot.modelRefreshFailure == nil)
        #expect(snapshot.phase == (provider == .deepSeek ? .validating : .ready))
        #expect(snapshot.selectedModelID == (provider == .deepSeek ? nil : "model"))

        await lister.finish()
        _ = await validation.value
        await session.checkOpenedCardCache()
        #expect(await lister.requests == 2, "ending the work starts nothing")
    }

    @Test("opening a stale card during a refresh starts nothing and shows no failure", arguments: [ProviderID.deepSeek, .openAI])
    func noRefreshDuringARefresh(opened provider: ProviderID) async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        try await configure(.openAI, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count
        await lister.holdNextRequest()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilHeld()

        if provider != .deepSeek { await session.selectProvider(provider) }
        await session.cardOpened(provider)

        #expect(await lister.requests.count == before + 1)
        let snapshot = await session.snapshot()
        #expect(snapshot.failure == nil)
        #expect(snapshot.modelRefreshFailure == nil)
        #expect(snapshot.phase == .ready)
        #expect(snapshot.selectedModelID == "model")

        await lister.finishHeld()
        await refresh.value
        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before + 1, "ending the work starts nothing")
    }

    @Test("a failed automatic refresh keeps the card, and only the next opening tries again")
    func failedAutomaticRefreshKeepsTheCard() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let before = await lister.requests.count
        await lister.fail(with: ProviderModelListError.requestRejected(statusCode: 503))

        await session.cardOpened(.deepSeek)

        let failed = await session.snapshot()
        #expect(failed.modelRefreshFailure == .unavailable)
        #expect(failed.failure == nil)
        #expect(failed.phase == .ready)
        #expect(failed.availableModelIDs == ["model"])
        #expect(failed.selectedModelID == "model")
        await session.checkOpenedCardCache()
        #expect(await lister.requests.count == before + 1)

        await lister.fail(with: nil)
        await session.cardOpened(.deepSeek)
        #expect(await lister.requests.count == before + 2)
        #expect(await session.snapshot().modelRefreshFailure == nil)
    }

    @Test("a key rejected during an automatic refresh says so")
    func automaticRefreshRejectedKey() async throws {
        let clock = SessionClock()
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister, now: { clock.now })
        try await configure(.deepSeek, on: coordinator)
        clock.advance(by: aDay)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        await lister.fail(with: ProviderModelListError.authenticationRejected)

        await session.cardOpened(.deepSeek)

        #expect(await session.snapshot().failure == .invalidConfiguration)
        #expect(await session.snapshot().phase == .failed)
    }

    @Test("a card changed during the cache read does not refresh", arguments: [false, true])
    func cardChangedDuringCacheRead(changes: Bool) async throws {
        let boundary = SuspendedCacheReadBoundary()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let opening = Task { await session.cardOpened(.deepSeek) }
        await boundary.waitUntilReading()

        if changes { await session.selectProvider(.openAI) }
        await boundary.finishReading()
        await opening.value

        #expect(await boundary.refreshes == (changes ? [] : [.deepSeek]))
    }

    /// A load empties the card until it ends, so checking then would find nothing to refresh and lose the opening.
    @Test("a load that begins during the cache read keeps the opening for when it ends")
    func loadDuringCacheRead() async throws {
        let boundary = SuspendedCacheReadBoundary()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let opening = Task { await session.cardOpened(.deepSeek) }
        await boundary.waitUntilReading()
        await boundary.holdNextLoad()
        let load = Task { await session.selectProvider(.deepSeek) }
        await boundary.waitUntilLoading()

        await boundary.finishReading()
        await opening.value
        #expect(await boundary.refreshes.isEmpty)

        await boundary.finishLoading()
        await load.value
        await session.checkOpenedCardCache()
        #expect(await boundary.refreshes == [.deepSeek])
    }

    /// An opening's check and its load's check are separate tasks, so both can be reading when the first one refreshes.
    @Test("two checks during one cache read refresh once")
    func twoChecksDuringOneCacheRead() async throws {
        let boundary = SuspendedCacheReadBoundary()
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: boundary)
        await session.load()
        let opening = Task { await session.cardOpened(.deepSeek) }
        await boundary.waitUntilReading()

        await session.checkOpenedCardCache()
        #expect(await boundary.refreshes == [.deepSeek])

        await boundary.finishReading()
        await opening.value
        #expect(await boundary.refreshes == [.deepSeek])
    }

    /// `load` would wait for the capture to end, which is what hung in the box before (v1-core failure mode 56).
    @Test("a request's refresh shows on the open card while the capture is held")
    func requestRefreshShowsDuringCapture() async throws {
        let lister = SessionModelLister()
        let coordinator = makeCoordinator(modelLister: lister)
        try await configure(.deepSeek, on: coordinator)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let capture = try await coordinator.beginCaptureActivity()
        try await coordinator.transitionCaptureToModelRequest(capture)
        await lister.list(["replacement"])

        try await coordinator.refreshModelsForRequest(provider: .deepSeek)
        await session.reloadConfiguration(of: .deepSeek)

        let snapshot = await session.snapshot()
        #expect(snapshot.availableModelIDs == ["replacement"])
        #expect(snapshot.selectedModelID == nil)
        #expect(snapshot.phase == .selectingModel)
        #expect(await coordinator.currentActivity() == .modelRequest)
    }

    @Test("a completed refresh that removes the selected model requires explicit reselection")
    func refreshedModelRemoval() async throws {
        let lister = SuspendedRefreshModelLister(refreshedModels: ["replacement"])
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        #expect(await session.snapshot().selectedModelID == "model")
        await session.selectProvider(.openAI)
        await lister.finish()
        await refresh.value
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .selectingModel)
        #expect(await session.snapshot().availableModelIDs == ["replacement"])
        #expect(await session.snapshot().selectedModelID == nil)
        #expect(await session.snapshot().canFinish == false)
        #expect(await session.snapshot().refreshingProvider == nil)
        await session.selectModel("replacement")
        #expect(await session.snapshot().phase == .ready)
    }

    @Test("returning to a refreshing card preserves its model and a network failure is not a credential failure", arguments: [false, true])
    func refreshSurvivesCardSwitchAndNetworkFailure(fails: Bool) async throws {
        let lister = SuspendedRefreshModelLister(fails: fails)
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        await session.selectProvider(.openAI)
        #expect(await session.snapshot().refreshingProvider == .deepSeek)
        #expect(await session.snapshot().isReadOnly == false)
        #expect(await session.snapshot().blocksConfigurationChanges)
        await session.selectProvider(.deepSeek)
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().availableModelIDs == ["model"])
        #expect(await session.snapshot().selectedModelID == "model")
        await lister.finish()
        await refresh.value
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().failure == nil)
        #expect(await session.snapshot().selectedModelID == "model")
        #expect(await session.snapshot().blocksConfigurationChanges == false)
        #expect(try await coordinator.apiKey(for: .deepSeek) == "fixture-key")
        #expect(await session.snapshot().refreshingProvider == nil)
        #expect(await session.snapshot().modelRefreshFailure == (fails ? .unavailable : nil))
        #expect(await lister.requests == 2)
        await session.refreshModels()
        #expect(await session.snapshot().modelRefreshFailure == nil)
        #expect(await lister.requests == 3)
    }

    @Test("model refresh keeps configured content visible while conflicting changes stay blocked")
    func refreshPreservesConfiguredContent() async throws {
        let lister = SuspendedRefreshModelLister()
        let coordinator = makeCoordinator(modelLister: lister)
        _ = try await coordinator.validateAndSaveKey("fixture-key", for: .deepSeek)
        _ = try await coordinator.selectModel("model", for: .deepSeek)
        let session = ProviderSetupSession(selectedProvider: .deepSeek, boundary: coordinator)
        await session.load()
        let refresh = Task { await session.refreshModels() }
        await lister.waitUntilRefreshing()
        let busy = await session.snapshot()
        #expect(busy.phase == .ready)
        #expect(busy.availableModelIDs == ["model"])
        #expect(busy.selectedModelID == "model")
        #expect(busy.failure == nil)
        #expect(busy.blocksConfigurationChanges)
        #expect(busy.refreshingProvider == .deepSeek)
        await session.refreshModels()
        #expect(await session.validate(apiKey: "conflicting-key", for: .openAI) == false)
        await lister.finish()
        await refresh.value
        #expect(await lister.requests == 2)
        #expect(await session.snapshot().phase == .ready)
        #expect(await session.snapshot().blocksConfigurationChanges == false)
    }
}

private actor SuspendedRefreshModelLister: ProviderModelListing {
    private let fails: Bool
    private let refreshedModels: [String]
    private(set) var requests = 0
    private var pending: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(fails: Bool = false, refreshedModels: [String] = ["model"]) {
        self.fails = fails
        self.refreshedModels = refreshedModels
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        requests += 1
        if requests == 2 {
            await withCheckedContinuation { continuation in
                pending = continuation
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
            if fails { throw ProviderModelListError.requestRejected(statusCode: 503) }
        }
        return requests == 1 ? ["model"] : refreshedModels
    }

    func waitUntilRefreshing() async {
        if pending != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish() { pending?.resume(); pending = nil }
}

private final class SessionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_787_731_200)

    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current.addTimeInterval(seconds) } }
}

private actor SessionModelLister: ProviderModelListing {
    private(set) var requests: [ProviderID] = []
    private var models = ["model"]
    private var error: (any Error)?

    private var holdsNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    func list(_ models: [String]) { self.models = models }
    func fail(with error: (any Error)?) { self.error = error }
    func holdNextRequest() { holdsNext = true }

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func finishHeld() {
        held?.resume()
        held = nil
    }

    func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        requests.append(provider)
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                heldWaiters.forEach { $0.resume() }
                heldWaiters.removeAll()
            }
        }
        if let error { throw error }
        return models
    }
}

/// Holds the first read of the cache's age until told, so a card can change or load during it, and can hold a load.
private actor SuspendedCacheReadBoundary: ProviderSetupConfiguring {
    private(set) var refreshes: [ProviderID] = []
    private var holdsNextRead = true
    private var holdsNextLoad = false
    private var pendingRead: CheckedContinuation<Void, Never>?
    private var pendingLoad: CheckedContinuation<Void, Never>?
    private var readWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    func shouldRefreshModelsOnSettingsOpen(for provider: ProviderID) async -> Bool {
        if holdsNextRead {
            holdsNextRead = false
            await withCheckedContinuation { continuation in
                pendingRead = continuation
                readWaiters.forEach { $0.resume() }
                readWaiters.removeAll()
            }
        }
        return true
    }

    func waitUntilReading() async {
        if pendingRead != nil { return }
        await withCheckedContinuation { readWaiters.append($0) }
    }

    func finishReading() {
        pendingRead?.resume()
        pendingRead = nil
    }

    func holdNextLoad() { holdsNextLoad = true }

    func waitUntilLoading() async {
        if pendingLoad != nil { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    func finishLoading() {
        pendingLoad?.resume()
        pendingLoad = nil
    }

    func currentActivity() async -> ProviderWorkflowActivity? { nil }

    func configurationState() -> ProviderMetadataState { state }

    func reconcileCredentialState(
        for provider: ProviderID, onRecovery: @escaping @Sendable () async -> Void
    ) async -> ProviderMetadataState {
        if holdsNextLoad {
            holdsNextLoad = false
            await withCheckedContinuation { continuation in
                pendingLoad = continuation
                loadWaiters.forEach { $0.resume() }
                loadWaiters.removeAll()
            }
        }
        return state
    }

    func validateAndSaveKey(_ apiKey: String, for provider: ProviderID) -> ProviderConfiguration { configuration }

    func refreshModels(for provider: ProviderID) -> ProviderConfiguration {
        refreshes.append(provider)
        return configuration
    }

    func selectModel(_ modelID: String, for provider: ProviderID) -> ProviderConfiguration { configuration }

    private var configuration: ProviderConfiguration {
        ProviderConfiguration(models: [ProviderModelState(id: "model")], fetchedAt: Date(), selectedModelID: "model")
    }

    private var state: ProviderMetadataState {
        ProviderMetadataState(configurations: [.deepSeek: configuration, .openAI: configuration])
    }
}
