import Foundation
import Testing
@testable import VLMSnapperCore

// Doubles and helpers the runner tests share.

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
    private var stored: [UUID: StoredOperation] = [:]

    func operation(id: UUID) async throws -> StoredOperation? { stored[id] }
    private(set) var operations: [ProviderOperation] = []
    private(set) var outcomes: [PersistedOperationOutcome] = []
    private(set) var completions: [OperationCompletion] = []
    private(set) var metrics: [PersistedOperationMetrics] = []
    private(set) var currentOutcomes: [UUID: PersistedOperationOutcome] = [:]
    private var failsPreparation: Bool
    private var cancelsPreparation: Bool
    private var failsSuccessfulFinish: Bool
    private let returnsMismatch: Bool
    private let returnsSelectionMismatch: Bool

    init(
        failsPreparation: Bool = false,
        cancelsPreparation: Bool = false,
        failsSuccessfulFinish: Bool = false,
        returnsMismatch: Bool = false,
        returnsSelectionMismatch: Bool = false
    ) {
        self.failsPreparation = failsPreparation
        self.cancelsPreparation = cancelsPreparation
        self.failsSuccessfulFinish = failsSuccessfulFinish
        self.returnsMismatch = returnsMismatch
        self.returnsSelectionMismatch = returnsSelectionMismatch
    }

    func setFailsPreparation(_ value: Bool) {
        failsPreparation = value
    }

    func setFailsSuccessfulFinish(_ value: Bool) {
        failsSuccessfulFinish = value
    }

    func setCancelsPreparation(_ value: Bool) {
        cancelsPreparation = value
    }

    func prepareOperation(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        operation: ProviderOperation
    ) async throws -> PreparedOperation {
        if cancelsPreparation {
            throw CancellationError()
        }
        if failsPreparation {
            throw RunnerProbeError.failed
        }
        operations.append(operation)
        if returnsMismatch {
            return PreparedOperation(
                operationID: UUID(),
                screenshot: ManagedScreenshot(path: "/wrong.png", sha256: "wrong"),
                selection: selection,
                operation: operation
            )
        }
        if returnsSelectionMismatch {
            return PreparedOperation(
                operationID: UUID(),
                screenshot: screenshot,
                selection: ProviderSelection(providerID: selection.providerID, modelID: "another-model"),
                operation: operation
            )
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

/// A provider stream that has started and has not finished, as a request in progress is.
actor RunnerOpenProviderProbe: PreparedOperationStreaming {
    private(set) var streamCount = 0
    private var continuations: [AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation] = []

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        let pair = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        continuations.append(pair.continuation)
        pair.continuation.yield(.sourceDelta("Partial"))
        return pair.stream
    }
}

actor RunnerQueuedProviderProbe: PreparedOperationStreaming {
    private var outputs: [String]

    init(outputs: [String]) {
        self.outputs = outputs
    }

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let output = outputs.removeFirst()
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta(output))
            continuation.yield(
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil))
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

actor RunnerRerunFailureProviderProbe: PreparedOperationStreaming {
    private var streamCount = 0

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        if streamCount == 2 {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ProviderAdapterError.providerUnavailable)
            }
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta("Original result"))
            continuation.yield(
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil))
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
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
    private(set) var streamCount = 0
    private(set) var originalPNGs: [Data] = []
    private(set) var preparedOperations: [PreparedOperation] = []
    private let events: [ProviderStreamEvent]?
    private let error: (any Error)?

    init(
        events: [ProviderStreamEvent]? = nil,
        error: (any Error)? = nil
    ) {
        self.events = events
        self.error = error
    }

    func stream(
        originalPNG: Data,
        preparedOperation: PreparedOperation
    ) async -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        streamCount += 1
        originalPNGs.append(originalPNG)
        preparedOperations.append(preparedOperation)
        let operation = preparedOperation.operation
        return AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if let events {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
                return
            }
            continuation.yield(.sourceDelta("Source"))
            if case .translate = operation {
                continuation.yield(.translationDelta("Translation"))
            }
            continuation.yield(
                .metadata(
                    ProviderResponseMetadata(requestID: nil, usage: nil)
                )
            )
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
