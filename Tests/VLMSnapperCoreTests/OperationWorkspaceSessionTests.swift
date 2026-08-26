import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Operation workspace session")
struct OperationWorkspaceSessionTests {
    @Test("switching operation tabs changes presentation without starting work")
    func switchingTabsDoesNotStartWork() async {
        let runner = WorkspaceRunnerProbe(events: [])
        let session = OperationWorkspaceSession(
            originalPNG: Data([0x89, 0x50]),
            runner: runner,
            activeGate: ActiveOperationGate()
        )

        await session.select(.translate)

        let snapshot = await session.snapshot()
        #expect(snapshot.selectedOperation == .translate)
        #expect(snapshot.extract.attempt == .neverStarted)
        #expect(snapshot.translate.attempt == .neverStarted)
        #expect(await runner.runCount == 0)
    }

    @Test("one explicit extraction action starts one run and commits its success")
    func explicitExtractionStartsOneRun() async throws {
        let expected = WorkspaceCommittedResult(
            sourceMarkdown: "# Captured text",
            translationMarkdown: nil
        )
        let runner = WorkspaceRunnerProbe(events: [
            .sourceDelta("# Captured "),
            .sourceDelta("text"),
            .succeeded(expected),
        ])
        let session = OperationWorkspaceSession(
            originalPNG: Data([0x89, 0x50]),
            runner: runner,
            activeGate: ActiveOperationGate()
        )

        try await session.startSelectedOperation(
            selection: ProviderSelection(
                providerID: "openai",
                modelID: "gpt-5.2"
            ),
            targetLanguage: "zh-Hans"
        )

        let snapshot = await session.snapshot()
        #expect(await runner.runCount == 1)
        #expect(await runner.operations == [.extractText])
        #expect(snapshot.extract.attempt == .succeeded)
        #expect(snapshot.extract.committedResult == expected)
        #expect(snapshot.extract.sourceDelta.isEmpty)
    }

    @Test("a failed rerun keeps the previous success and discards partial text")
    func failedRerunKeepsPreviousSuccess() async throws {
        let previous = WorkspaceCommittedResult(
            sourceMarkdown: "Stable result",
            translationMarkdown: nil
        )
        let runner = SequencedWorkspaceRunnerProbe(runs: [
            .events([.succeeded(previous)]),
            .failure([.sourceDelta("Partial replacement")]),
        ])
        let session = OperationWorkspaceSession(
            originalPNG: Data([0x89, 0x50]),
            runner: runner,
            activeGate: ActiveOperationGate()
        )
        let selection = ProviderSelection(
            providerID: "gemini",
            modelID: "gemini-2.5-flash"
        )
        try await session.startSelectedOperation(
            selection: selection,
            targetLanguage: "zh-Hans"
        )

        await #expect(throws: WorkspaceRunnerProbeError.failed) {
            try await session.startSelectedOperation(
                selection: selection,
                targetLanguage: "zh-Hans"
            )
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
        let secondRunner = WorkspaceRunnerProbe(events: [])
        let first = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: firstRunner,
            activeGate: gate
        )
        let second = OperationWorkspaceSession(
            originalPNG: Data([2]),
            runner: secondRunner,
            activeGate: gate
        )
        let selection = ProviderSelection(
            providerID: "deepseek",
            modelID: "deepseek-v4-flash-vision-exp"
        )
        let firstTask = Task {
            try await first.startSelectedOperation(
                selection: selection,
                targetLanguage: "en"
            )
        }
        await firstRunner.waitUntilStarted()

        await #expect(throws: OperationWorkspaceSessionError.busy) {
            try await second.startSelectedOperation(
                selection: selection,
                targetLanguage: "en"
            )
        }
        #expect(await secondRunner.runCount == 0)

        await firstRunner.succeed()
        try await firstTask.value
    }

    @Test("closing during a stream cancels the attempt and discards partial text")
    func closingDuringStreamCancelsAttempt() async throws {
        let runner = SuspendedWorkspaceRunnerProbe()
        let session = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: runner,
            activeGate: ActiveOperationGate()
        )
        let running = Task {
            try await session.startSelectedOperation(
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "gpt-5.2"
                ),
                targetLanguage: "en"
            )
        }
        await runner.waitUntilStarted()
        await runner.yield(.sourceDelta("Partial"))

        let disposition = await session.close()

        #expect(disposition == .cancelAndHide)
        do {
            try await running.value
            Issue.record("Expected the running attempt to terminate")
        } catch {}
        let snapshot = await session.snapshot()
        #expect(snapshot.extract.attempt == .canceled)
        #expect(snapshot.extract.sourceDelta.isEmpty)
    }

    @Test("closing with an unsaved completed result requires confirmation")
    func closingUnsavedResultRequiresConfirmation() async throws {
        let result = WorkspaceCommittedResult(
            sourceMarkdown: "Copyable result",
            translationMarkdown: nil
        )
        let session = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: WorkspaceRunnerProbe(events: [
                .resultPersistenceFailed(result),
            ]),
            activeGate: ActiveOperationGate()
        )
        try await session.startSelectedOperation(
            selection: ProviderSelection(providerID: "openai", modelID: "vision"),
            targetLanguage: "en"
        )

        let disposition = await session.close()

        #expect(disposition == .confirmDiscardUnsavedResult)
    }

    @Test("an unsaved completed result blocks another model operation")
    func unsavedResultBlocksAnotherOperation() async throws {
        let runner = WorkspaceRunnerProbe(events: [
            .resultPersistenceFailed(
                WorkspaceCommittedResult(
                    sourceMarkdown: "Unsaved",
                    translationMarkdown: nil
                )
            ),
        ])
        let session = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: runner,
            activeGate: ActiveOperationGate()
        )
        let selection = ProviderSelection(providerID: "openai", modelID: "vision")
        try await session.startSelectedOperation(
            selection: selection,
            targetLanguage: "en"
        )
        await session.select(.translate)

        await #expect(
            throws: OperationWorkspaceSessionError.unsavedResultRequiresSave
        ) {
            try await session.startSelectedOperation(
                selection: selection,
                targetLanguage: "en"
            )
        }
        #expect(await runner.runCount == 1)
    }

    @Test("closing while waiting for the global gate prevents the request")
    func closingWhileWaitingForGatePreventsRequest() async throws {
        let gate = SuspendedActivityGateProbe()
        let runner = WorkspaceRunnerProbe(events: [])
        let session = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: runner,
            activeGate: gate
        )
        let starting = Task {
            try await session.startSelectedOperation(
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "vision"
                ),
                targetLanguage: "en"
            )
        }
        await gate.waitUntilAcquireStarted()

        let disposition = await session.close()
        await gate.resumeAcquire()

        #expect(disposition == .cancelAndHide)
        do {
            try await starting.value
            Issue.record("Expected the pending start to cancel")
        } catch {}
        #expect(await runner.runCount == 0)
    }

    @Test("tab changes while acquiring the gate do not change the requested operation")
    func tabChangeDoesNotMutatePendingOperation() async throws {
        let gate = SuspendedActivityGateProbe()
        let runner = WorkspaceRunnerProbe(events: [
            .succeeded(
                WorkspaceCommittedResult(
                    sourceMarkdown: "Extracted",
                    translationMarkdown: nil
                )
            ),
        ])
        let session = OperationWorkspaceSession(
            originalPNG: Data([1]),
            runner: runner,
            activeGate: gate
        )
        let starting = Task {
            try await session.startSelectedOperation(
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "vision"
                ),
                targetLanguage: "en"
            )
        }
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
    let events: [OperationWorkspaceRunEvent]
    private(set) var runCount = 0
    private(set) var operations: [ProviderOperation] = []

    init(events: [OperationWorkspaceRunEvent]) {
        self.events = events
    }

    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        runCount += 1
        operations.append(operation)
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private enum SequencedWorkspaceRun: Sendable {
    case events([OperationWorkspaceRunEvent])
    case failure([OperationWorkspaceRunEvent])
}

private enum WorkspaceRunnerProbeError: Error {
    case failed
}

private actor SequencedWorkspaceRunnerProbe: OperationWorkspaceRunning {
    private var runs: [SequencedWorkspaceRun]

    init(runs: [SequencedWorkspaceRun]) {
        self.runs = runs
    }

    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        let run = runs.removeFirst()
        return AsyncThrowingStream { continuation in
            switch run {
            case let .events(events):
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            case let .failure(events):
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish(throwing: WorkspaceRunnerProbeError.failed)
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
        continuation?.yield(
            .succeeded(
                WorkspaceCommittedResult(
                    sourceMarkdown: "Done",
                    translationMarkdown: nil
                )
            )
        )
        continuation?.finish()
        continuation = nil
    }

    func yield(_ event: OperationWorkspaceRunEvent) {
        continuation?.yield(event)
    }
}
