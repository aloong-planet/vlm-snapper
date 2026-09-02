import Foundation

public enum ProviderTimeoutKind: Equatable, Sendable {
    case firstText
    case stalled
    case total
}

public struct ProviderStreamTimeouts: Equatable, Sendable {
    public let firstText: Duration
    public let stalled: Duration
    public let total: Duration

    public init(
        firstText: Duration = .seconds(10),
        stalled: Duration = .seconds(10),
        total: Duration = .seconds(90)
    ) {
        self.firstText = firstText
        self.stalled = stalled
        self.total = total
    }
}

public protocol ProviderTimeoutClock: Sendable {
    func sleep(for duration: Duration, kind: ProviderTimeoutKind) async throws
}

public struct ContinuousProviderTimeoutClock: ProviderTimeoutClock {
    public init() {}

    public func sleep(for duration: Duration, kind: ProviderTimeoutKind) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

actor ProviderStreamTimeoutCoordinator {
    private let continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    private let clock: any ProviderTimeoutClock
    private let timeouts: ProviderStreamTimeouts
    private var active = true
    private var hasReceivedText = false
    private var textTimer: Task<Void, Never>?
    private var totalTimer: Task<Void, Never>?

    init(
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation,
        clock: any ProviderTimeoutClock,
        timeouts: ProviderStreamTimeouts
    ) {
        self.continuation = continuation
        self.clock = clock
        self.timeouts = timeouts
    }

    func startTotal() {
        totalTimer = timer(for: .total, duration: timeouts.total)
    }

    func startFirstText() {
        guard active else {
            return
        }
        textTimer = timer(for: .firstText, duration: timeouts.firstText)
    }

    func receivedActivity(includesText: Bool) {
        guard active else {
            return
        }
        if includesText {
            hasReceivedText = true
        }
        textTimer?.cancel()
        if hasReceivedText {
            textTimer = timer(for: .stalled, duration: timeouts.stalled)
        } else {
            textTimer = timer(for: .firstText, duration: timeouts.firstText)
        }
    }

    func complete() {
        guard active else {
            return
        }
        active = false
        cancelTimers()
        continuation.finish()
    }

    func fail(_ error: ProviderAdapterError) {
        guard active else {
            return
        }
        active = false
        cancelTimers()
        continuation.finish(throwing: error)
    }

    private func timer(for kind: ProviderTimeoutKind, duration: Duration) -> Task<Void, Never> {
        Task { [clock] in
            do {
                try await clock.sleep(for: duration, kind: kind)
                timeout(kind)
            } catch {
                // Cancellation is the normal way a superseded deadline ends.
            }
        }
    }

    private func timeout(_ kind: ProviderTimeoutKind) {
        switch kind {
        case .firstText:
            fail(.firstTextTimeout)
        case .stalled:
            fail(.streamStalled)
        case .total:
            fail(.totalTimeout)
        }
    }

    private func cancelTimers() {
        textTimer?.cancel()
        totalTimer?.cancel()
        textTimer = nil
        totalTimer = nil
    }
}
