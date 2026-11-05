import Foundation
import Testing
@testable import VLMSnapperCore

// Doubles and helpers the runner tests share.

/// A runner over doubles. A test passes the ones it reads, and each default is a run that goes well.
func makeRunner(
    screenshotStore: any ScreenshotPersisting & ManagedScreenshotLoading = RunnerScreenshotStoreProbe(),
    history: any OperationHistoryWriting = RunnerHistoryProbe(),
    provider: any PreparedOperationStreaming = RunnerProviderProbe(),
    visionCompatibility: (any VisionCompatibilityRecording)? = nil,
    modelListRefresh: (any UnavailableModelRefreshing)? = nil,
    restoring operation: StoredOperation? = nil,
    now: @escaping @Sendable () -> Date = Date.init
) -> PersistedOperationWorkspaceRunner {
    PersistedOperationWorkspaceRunner(
        screenshotStore: screenshotStore,
        historyStore: history,
        provider: provider,
        visionCompatibility: visionCompatibility,
        modelListRefresh: modelListRefresh,
        restoring: operation,
        now: now
    )
}

/// One extraction of the same screenshot, for tests where the operation and image are not what they check.
func extract(
    on runner: PersistedOperationWorkspaceRunner,
    providerID: String = "deepseek"
) async throws -> [OperationWorkspaceRunEvent] {
    try await collect(await runner.run(
        originalPNG: Data([1]),
        operation: .extractText,
        selection: ProviderSelection(providerID: providerID, modelID: "vision")
    ))
}

/// A record saved for the screenshot `extract(on:)` uses, as a runner opened on existing history finds it.
func savedRecord(
    of operation: ProviderOperation
) async throws -> (screenshotStore: RunnerScreenshotStoreProbe, history: RunnerHistoryProbe, stored: StoredOperation) {
    let screenshotStore = RunnerScreenshotStoreProbe()
    let history = RunnerHistoryProbe()
    let screenshot = try await screenshotStore.save(originalPNG: Data([1]))
    let prepared = try await history.prepareOperation(
        screenshot: screenshot,
        selection: ProviderSelection(providerID: "gemini", modelID: "vision"),
        operation: operation
    )
    return (screenshotStore, history, try #require(try await history.operation(id: prepared.operationID)))
}

actor RunnerVisionRecorderProbe: VisionCompatibilityRecording {
    enum Call: Equatable {
        case success(ProviderID, String)
        case failure(ProviderID, String, VisionFailureEvidence)
    }

    private(set) var calls: [Call] = []
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func recordVisionSuccess(provider: ProviderID, modelID: String) async throws {
        calls.append(.success(provider, modelID))
        if fails { throw ProviderConfigurationError.modelNotFound }
    }

    func recordVisionFailure(
        provider: ProviderID,
        modelID: String,
        evidence: VisionFailureEvidence
    ) async throws {
        calls.append(.failure(provider, modelID, evidence))
        if fails { throw ProviderConfigurationError.modelNotFound }
    }
}

actor RunnerEndFlag {
    private(set) var value = false
    func mark() { value = true }
}

actor RunnerModelListProbe: UnavailableModelRefreshing {
    private(set) var providers: [ProviderID] = []
    private let fails: Bool
    private let suspends: Bool
    private let gate = AsyncStream<Void>.makeStream()
    private var calledWaiters: [CheckedContinuation<Void, Never>] = []

    init(fails: Bool = false, suspends: Bool = false) {
        self.fails = fails
        self.suspends = suspends
    }

    func waitUntilCalled() async {
        guard providers.isEmpty else { return }
        await withCheckedContinuation { calledWaiters.append($0) }
    }

    func finish() { gate.continuation.finish() }

    func refreshModelsForRequest(provider: ProviderID) async throws {
        providers.append(provider)
        calledWaiters.forEach { $0.resume() }
        calledWaiters.removeAll()
        // Ends on `finish` or on cancellation, as a canceled list request does.
        if suspends { for await _ in gate.stream {} }
        try Task.checkCancellation()
        if fails { throw ProviderModelListError.invalidResponse }
    }
}

func collect(
    _ stream: AsyncThrowingStream<OperationWorkspaceRunEvent, Error>
) async throws -> [OperationWorkspaceRunEvent] {
    var events: [OperationWorkspaceRunEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

actor RunnerScreenshotStoreProbe: ScreenshotPersisting, ManagedScreenshotLoading {
    private(set) var saveCount = 0
    private(set) var discardCount = 0
    private var png = Data()

    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data { png }

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        saveCount += 1
        png = originalPNG
        return ManagedScreenshot(path: "/Pictures/shared.png", sha256: "sha")
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        discardCount += 1
    }
}

actor RunnerHistoryProbe: OperationHistoryWriting {
    /// What a prepared record can differ in from what was asked for.
    enum Mismatch: Sendable {
        case screenshot
        case selection
    }

    private var stored: [UUID: StoredOperation] = [:]

    func operation(id: UUID) async throws -> StoredOperation? { stored[id] }
    private(set) var operations: [ProviderOperation] = []
    private(set) var outcomes: [PersistedOperationOutcome] = []
    private(set) var completions: [OperationCompletion] = []
    private(set) var metrics: [PersistedOperationMetrics] = []
    private(set) var currentOutcomes: [UUID: PersistedOperationOutcome] = [:]
    private var preparationError: (any Error)?
    private var failsSuccessfulFinish: Bool
    private let mismatch: Mismatch?

    init(
        preparationError: (any Error)? = nil,
        failsSuccessfulFinish: Bool = false,
        mismatch: Mismatch? = nil
    ) {
        self.preparationError = preparationError
        self.failsSuccessfulFinish = failsSuccessfulFinish
        self.mismatch = mismatch
    }

    func setPreparationError(_ error: (any Error)?) {
        preparationError = error
    }

    func setFailsSuccessfulFinish(_ value: Bool) {
        failsSuccessfulFinish = value
    }

    func prepareOperation(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        operation: ProviderOperation
    ) async throws -> PreparedOperation {
        if let preparationError {
            throw preparationError
        }
        operations.append(operation)
        switch mismatch {
        case .screenshot:
            return PreparedOperation(
                operationID: UUID(),
                screenshot: ManagedScreenshot(path: "/wrong.png", sha256: "wrong"),
                selection: selection,
                operation: operation
            )
        case .selection:
            return PreparedOperation(
                operationID: UUID(),
                screenshot: screenshot,
                selection: ProviderSelection(providerID: selection.providerID, modelID: "another-model"),
                operation: operation
            )
        case nil:
            break
        }
        let id = UUID()
        let targetLanguage: String?
        switch operation {
        case .extractText: targetLanguage = nil
        case let .translate(language): targetLanguage = language
        }
        stored[id] = StoredOperation(id: id, screenshot: screenshot, selection: selection,
            status: .succeeded, kind: targetLanguage == nil ? .extract : .translate,
            targetLanguage: targetLanguage)
        return PreparedOperation(
            operationID: id,
            screenshot: screenshot,
            selection: selection,
            operation: operation
        )
    }

    func markInFlight(
        operationID: UUID,
        as progress: OperationProgress
    ) async throws {}

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome
    ) async throws {
        if failsSuccessfulFinish, case .succeeded = outcome {
            throw RunnerProbeError.failed
        }
        outcomes.append(outcome)
        currentOutcomes[operationID] = outcome
    }

    func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        try await finish(operationID: operationID, with: outcome)
        self.metrics.append(metrics)
    }

    func replace(
        operationID: UUID,
        selection: ProviderSelection,
        operation: ProviderOperation,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        try await finish(
            operationID: operationID,
            with: outcome,
            metrics: metrics
        )
    }

    func finish(
        operationID: UUID,
        as completion: OperationCompletion
    ) async throws {
        completions.append(completion)
    }
}

struct RunnerFailingScreenshotStoreProbe: ScreenshotPersisting, ManagedScreenshotLoading {
    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data { Data() }
    func save(originalPNG: Data) async throws -> ManagedScreenshot { throw ScreenshotStoreError.unsafePath }
    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {}
}

final class RunnerClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(values: [Date]) { self.values = values }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

enum RunnerProbeError: Error {
    case failed
}

actor RunnerProviderProbe: PreparedOperationStreaming {
    /// What one stream does. Streams take these in order, and the last one repeats.
    enum Run: Sendable {
        /// Source text, a translation if the operation is one, then completion.
        case standard
        case events([ProviderStreamEvent])
        case failure(any Error)
        /// A stream that has started and has not finished, as a request in progress is.
        case open

        static func text(_ output: String) -> Run {
            .events([
                .sourceDelta(output),
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)),
                .completed,
            ])
        }
    }

    private(set) var streamCount = 0
    private(set) var originalPNGs: [Data] = []
    private(set) var preparedOperations: [PreparedOperation] = []
    private var runs: [Run]
    private var openStreams: [AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation] = []

    init(runs: [Run] = [.standard]) {
        self.runs = runs
    }

    init(events: [ProviderStreamEvent]) {
        runs = [.events(events)]
    }

    init(error: any Error) {
        runs = [.failure(error)]
    }

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        originalPNGs.append(originalPNG)
        preparedOperations.append(preparedOperation)
        let run = runs.count > 1 ? runs.removeFirst() : runs[0]
        let (stream, continuation) = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        switch run {
        case .standard:
            continuation.yield(.sourceDelta("Source"))
            if case .translate = preparedOperation.operation {
                continuation.yield(.translationDelta("Translation"))
            }
            continuation.yield(.metadata(ProviderResponseMetadata(requestID: nil, usage: nil)))
            continuation.yield(.completed)
            continuation.finish()
        case let .events(events):
            events.forEach { continuation.yield($0) }
            continuation.finish()
        case let .failure(error):
            continuation.finish(throwing: error)
        case .open:
            continuation.yield(.sourceDelta("Partial"))
            openStreams.append(continuation)
        }
        return stream
    }
}
