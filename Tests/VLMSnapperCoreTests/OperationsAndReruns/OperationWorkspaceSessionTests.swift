import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Operation workspace session")
struct OperationWorkspaceSessionTests {
    @Test("switching operation tabs changes presentation without starting work")
    func switchingTabsDoesNotStartWork() async {
        let runner = WorkspaceRunnerProbe()
        let session = makeSession(runner: runner)

        await session.select(.translate)

        let snapshot = await session.snapshot()
        #expect(snapshot.selectedOperation == .translate)
        #expect(snapshot.extract.attempt == .neverStarted)
        #expect(snapshot.translate.attempt == .neverStarted)
        #expect(await runner.runCount == 0)
    }

    @Test("one explicit extraction action starts one run and commits its success")
    func explicitExtractionStartsOneRun() async throws {
        let expected = committed("# Captured text")
        let runner = WorkspaceRunnerProbe(events: [
            .sourceDelta("# Captured "),
            .sourceDelta("text"),
            .succeeded(expected),
        ])
        let session = makeSession(runner: runner)

        try await start(session)

        let snapshot = await session.snapshot()
        #expect(await runner.runCount == 1)
        #expect(await runner.operations == [.extractText])
        #expect(snapshot.extract.attempt == .succeeded)
        #expect(snapshot.extract.committedResult == expected)
        #expect(snapshot.extract.sourceDelta.isEmpty)
    }

    @Test("a failed rerun keeps the previous success and discards partial text")
    func failedRerunKeepsPreviousSuccess() async throws {
        let previous = committed("Stable result")
        let session = makeSession(runner: WorkspaceRunnerProbe(runs: [
            .events([.succeeded(previous)]),
            .failure([.sourceDelta("Partial replacement")]),
        ]))
        try await start(session)

        await #expect(throws: WorkspaceRunnerProbe.Failure.failed) {
            try await start(session)
        }

        let snapshot = await session.snapshot()
        #expect(snapshot.extract.committedResult == previous)
        #expect(snapshot.extract.attempt == .failed(code: "operation_failed"))
        #expect(snapshot.extract.sourceDelta.isEmpty)
    }

    @Test("the application gate blocks a second workspace before its runner starts")
    func globalGateBlocksSecondWorkspace() async throws {
        let gate = ActiveOperationGate()
        let firstRunner = SuspendedWorkspaceRunnerProbe()
        let secondRunner = WorkspaceRunnerProbe()
        let first = makeSession(runner: firstRunner, gate: gate)
        let second = makeSession(runner: secondRunner, gate: gate)
        let firstTask = Task { try await start(first) }
        await firstRunner.waitUntilStarted()

        await #expect(throws: OperationWorkspaceSessionError.busy) {
            try await start(second)
        }
        #expect(await secondRunner.runCount == 0)

        await firstRunner.succeed()
        try await firstTask.value
    }

    @Test("closing during a stream cancels the attempt and discards partial text")
    func closingDuringStreamCancelsAttempt() async throws {
        let runner = SuspendedWorkspaceRunnerProbe()
        let session = makeSession(runner: runner)
        let running = Task { try await start(session) }
        await runner.waitUntilStarted()
        await runner.yield(.sourceDelta("Partial"))

        let disposition = await session.close()

        #expect(disposition == .cancelAndHide)
        await #expect(throws: (any Error).self) { try await running.value }
        let snapshot = await session.snapshot()
        #expect(snapshot.extract.attempt == .canceled)
        #expect(snapshot.extract.sourceDelta.isEmpty)
    }

    @Test(
        "closing with an unsaved completed result requires confirmation, and confirming discard clears it",
        arguments: WorkspaceOperationKind.allCases
    )
    func closingAnUnsavedResultAsksAndDiscardingClearsIt(operation: WorkspaceOperationKind) async throws {
        let session = makeSession(runner: WorkspaceRunnerProbe(events: [.resultPersistenceFailed(committed("Copyable result"))]))
        await session.select(operation)
        try await start(session)

        #expect(await session.hasUnsavedResult)
        #expect(await session.close() == .confirmDiscardUnsavedResult)

        await session.discardUnsavedResults()

        let snapshot = await session.snapshot()
        #expect(snapshot.extract.unsavedResult == nil)
        #expect(snapshot.translate.unsavedResult == nil)
        #expect(await !session.hasUnsavedResult)
        #expect(await session.close() != .confirmDiscardUnsavedResult)
    }

    /// The operation a run is for, its last event, and what a new capture should then do with its workspace.
    static let finishedRuns: [(WorkspaceOperationKind, OperationWorkspaceRunEvent, WorkspaceCapturePreparation)] = [
        (.extract, .succeeded(committed("Saved")), .beginCapture),
        (.extract, .resultPersistenceFailed(committed("Unsaved")), .presentWorkspace),
        (.translate, .resultPersistenceFailed(committed("Unsaved")), .presentWorkspace),
    ]

    @Test(
        "a completed workspace retires before a new capture, and an unsaved result keeps its workspace in front",
        arguments: finishedRuns
    )
    func aFinishedRunDecidesTheNextCapture(
        operation: WorkspaceOperationKind,
        event: OperationWorkspaceRunEvent,
        expected: WorkspaceCapturePreparation
    ) async throws {
        let session = makeSession(runner: WorkspaceRunnerProbe(events: [event]))
        await session.select(operation)
        try await start(session)

        #expect(await session.prepareForCapture() == expected)
    }

    @Test("an active request keeps the current workspace in front")
    func activeRequestKeepsWorkspaceForCapture() async throws {
        let runner = SuspendedWorkspaceRunnerProbe()
        let session = makeSession(runner: runner)
        let running = Task { try await start(session) }
        await runner.waitUntilStarted()

        let preparation = await session.prepareForCapture()

        #expect(preparation == .presentWorkspace)
        await runner.succeed()
        try await running.value
    }

    @Test("a failed workspace retires before a new capture")
    func failedWorkspaceRetiresForCapture() async {
        let session = makeSession(runner: WorkspaceRunnerProbe(runs: [.failure([])]))
        await #expect(throws: WorkspaceRunnerProbe.Failure.failed) {
            try await start(session)
        }

        let preparation = await session.prepareForCapture()

        #expect(preparation == .beginCapture)
    }

    @Test("a canceled workspace retires before a new capture")
    func canceledWorkspaceRetiresForCapture() async {
        let runner = SuspendedWorkspaceRunnerProbe()
        let session = makeSession(runner: runner)
        let running = Task { try await start(session) }
        await runner.waitUntilStarted()
        #expect(await session.close() == .cancelAndHide)
        await #expect(throws: (any Error).self) { try await running.value }

        let preparation = await session.prepareForCapture()

        #expect(preparation == .beginCapture)
    }

    @Test("workspace capture preparation is consumed exactly once")
    func workspaceCapturePreparationIsConsumedOnce() async {
        let session = makeSession(runner: WorkspaceRunnerProbe())

        let first = await session.prepareForCapture()
        let second = await session.prepareForCapture()

        #expect(first == .beginCapture)
        #expect(second == .alreadyPrepared)
    }

    @Test("a failed capture restores the prepared workspace")
    func failedCaptureRestoresPreparedWorkspace() async throws {
        let session = makeSession(runner: WorkspaceRunnerProbe(events: [.succeeded(committed("Replacement run"))]))

        #expect(await session.prepareForCapture() == .beginCapture)
        await session.restoreAfterCaptureFailure()
        try await start(session)

        #expect((await session.snapshot()).extract.attempt == .succeeded)
    }

    @Test("a retired workspace cannot start another model request")
    func retiredWorkspaceRejectsAnotherOperation() async {
        let session = makeSession(runner: WorkspaceRunnerProbe())
        _ = await session.prepareForCapture()

        await #expect(throws: OperationWorkspaceSessionError.busy) {
            try await start(session)
        }
    }

    @Test(
        "an unsaved completed result blocks another model operation",
        arguments: [(WorkspaceOperationKind.extract, WorkspaceOperationKind.translate), (.translate, .extract)]
    )
    func unsavedResultBlocksAnotherOperation(unsaved: WorkspaceOperationKind, next: WorkspaceOperationKind) async throws {
        let runner = WorkspaceRunnerProbe(events: [.resultPersistenceFailed(committed("Unsaved"))])
        let session = makeSession(runner: runner)
        await session.select(unsaved)
        try await start(session)
        await session.select(next)

        await #expect(throws: OperationWorkspaceSessionError.unsavedResultRequiresSave) {
            try await start(session)
        }
        #expect(await runner.runCount == 1)
    }

    @Test("closing while waiting for the global gate prevents the request")
    func closingWhileWaitingForGatePreventsRequest() async throws {
        let gate = SuspendedActivityGateProbe()
        let runner = WorkspaceRunnerProbe()
        let session = makeSession(runner: runner, gate: gate)
        let starting = Task { try await start(session) }
        await gate.waitUntilAcquireStarted()

        let disposition = await session.close()
        await gate.resumeAcquire()

        #expect(disposition == .cancelAndHide)
        await #expect(throws: (any Error).self) { try await starting.value }
        #expect(await runner.runCount == 0)
    }

    @Test("tab changes while acquiring the gate do not change the requested operation")
    func tabChangeDoesNotMutatePendingOperation() async throws {
        let gate = SuspendedActivityGateProbe()
        let runner = WorkspaceRunnerProbe(events: [.succeeded(committed("Extracted"))])
        let session = makeSession(runner: runner, gate: gate)
        let starting = Task { try await start(session) }
        await gate.waitUntilAcquireStarted()

        await session.select(.translate)
        await gate.resumeAcquire()
        try await starting.value

        #expect(await runner.operations == [.extractText])
        let snapshot = await session.snapshot()
        #expect(snapshot.extract.attempt == .succeeded)
        #expect(snapshot.translate.attempt == .neverStarted)
    }
}

/// The probes record the operation only, so these tests share one image, selection and language.
private func makeSession(
    runner: any OperationWorkspaceRunning,
    gate: any OperationActivityGating = ActiveOperationGate()
) -> OperationWorkspaceSession {
    OperationWorkspaceSession(originalPNG: Data([1]), runner: runner, activeGate: gate)
}

private func start(_ session: OperationWorkspaceSession) async throws {
    try await session.startSelectedOperation(
        selection: ProviderSelection(providerID: "openai", modelID: "vision"),
        targetLanguage: "en"
    )
}

private func committed(_ text: String) -> WorkspaceCommittedResult {
    WorkspaceCommittedResult(sourceMarkdown: text, translationMarkdown: nil)
}

private actor SuspendedActivityGateProbe: OperationActivityGating {
    private var acquireContinuation: CheckedContinuation<UUID?, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async -> UUID? {
        await withCheckedContinuation { continuation in
            acquireContinuation = continuation
            let currentWaiters = waiters
            waiters.removeAll()
            for waiter in currentWaiters {
                waiter.resume()
            }
        }
    }

    func release(_ lease: UUID) {}

    func waitUntilAcquireStarted() async {
        guard acquireContinuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func resumeAcquire() {
        acquireContinuation?.resume(returning: UUID())
        acquireContinuation = nil
    }
}

private actor WorkspaceRunnerProbe: OperationWorkspaceRunning {
    /// What one run does. Runs take these in order, and the last one repeats.
    enum Run: Sendable {
        case events([OperationWorkspaceRunEvent])
        case failure([OperationWorkspaceRunEvent])
    }

    enum Failure: Error {
        case failed
    }

    private var runs: [Run]
    private(set) var runCount = 0
    private(set) var operations: [ProviderOperation] = []

    init(events: [OperationWorkspaceRunEvent] = []) {
        runs = [.events(events)]
    }

    init(runs: [Run]) {
        self.runs = runs
    }

    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        runCount += 1
        operations.append(operation)
        let run = runs.count > 1 ? runs.removeFirst() : runs[0]
        return AsyncThrowingStream { continuation in
            switch run {
            case let .events(events):
                events.forEach { continuation.yield($0) }
                continuation.finish()
            case let .failure(events):
                events.forEach { continuation.yield($0) }
                continuation.finish(throwing: Failure.failed)
            }
        }
    }
}

private actor SuspendedWorkspaceRunnerProbe: OperationWorkspaceRunning {
    private var continuation: AsyncThrowingStream<OperationWorkspaceRunEvent, Error>
        .Continuation?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed() {
        continuation?.yield(.succeeded(committed("Done")))
        continuation?.finish()
        continuation = nil
    }

    func yield(_ event: OperationWorkspaceRunEvent) {
        continuation?.yield(event)
    }
}
