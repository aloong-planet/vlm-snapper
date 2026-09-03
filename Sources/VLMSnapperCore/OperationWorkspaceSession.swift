import Foundation

public enum WorkspaceOperationKind: String, CaseIterable, Equatable, Sendable {
    case extract
    case translate
}

public enum WorkspaceAttemptState: Equatable, Sendable {
    case neverStarted
    case preparing
    case streaming
    case succeeded
    case failed(code: String)
    case canceled
    case resultPersistenceFailed
}

public enum OperationWorkspaceRunEvent: Equatable, Sendable {
    case sourceDelta(String)
    case translationDelta(String)
    case succeeded(WorkspaceCommittedResult)
    case resultPersistenceFailed(WorkspaceCommittedResult)
}

public protocol OperationWorkspaceRunning: Sendable {
    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) async -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error>

    func retrySavingResult() async throws -> WorkspaceCommittedResult
}

public extension OperationWorkspaceRunning {
    func retrySavingResult() async throws -> WorkspaceCommittedResult {
        throw OperationWorkspaceSessionError.noUnsavedResult
    }
}

public enum OperationWorkspaceSessionError: Error, Equatable {
    case busy
    case incompleteRun
    case noUnsavedResult
    case unsavedResultRequiresSave
}

public struct OperationWorkspaceRunFailure: Error, Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public enum WorkspaceCloseDisposition: Equatable, Sendable {
    case discard
    case cancelAndHide
    case confirmDiscardUnsavedResult
    case hide
}

public enum WorkspaceCapturePreparation: Equatable, Sendable {
    case beginCapture
    case alreadyPrepared
    case presentWorkspace
}

public protocol OperationActivityGating: Sendable {
    func acquire() async -> UUID?
    func release(_ lease: UUID) async
}

public actor ActiveOperationGate: OperationActivityGating {
    private var activeLease: UUID?

    public init() {}

    public func acquire() -> UUID? {
        guard activeLease == nil else {
            return nil
        }
        let lease = UUID()
        activeLease = lease
        return lease
    }

    public func release(_ lease: UUID) {
        guard activeLease == lease else {
            return
        }
        activeLease = nil
    }
}

public struct WorkspaceCommittedResult: Equatable, Sendable {
    public let sourceMarkdown: String
    public let translationMarkdown: String?

    public init(
        sourceMarkdown: String,
        translationMarkdown: String?
    ) {
        self.sourceMarkdown = sourceMarkdown
        self.translationMarkdown = translationMarkdown
    }
}

public struct WorkspaceOperationSlot: Equatable, Sendable {
    public let attempt: WorkspaceAttemptState
    public let committedResult: WorkspaceCommittedResult?
    public let unsavedResult: WorkspaceCommittedResult?
    public let sourceDelta: String
    public let translationDelta: String

    public init(
        attempt: WorkspaceAttemptState = .neverStarted,
        committedResult: WorkspaceCommittedResult? = nil,
        unsavedResult: WorkspaceCommittedResult? = nil,
        sourceDelta: String = "",
        translationDelta: String = ""
    ) {
        self.attempt = attempt
        self.committedResult = committedResult
        self.unsavedResult = unsavedResult
        self.sourceDelta = sourceDelta
        self.translationDelta = translationDelta
    }
}

public struct OperationWorkspaceSnapshot: Equatable, Sendable {
    public let selectedOperation: WorkspaceOperationKind
    public let extract: WorkspaceOperationSlot
    public let translate: WorkspaceOperationSlot

    public init(
        selectedOperation: WorkspaceOperationKind,
        extract: WorkspaceOperationSlot,
        translate: WorkspaceOperationSlot
    ) {
        self.selectedOperation = selectedOperation
        self.extract = extract
        self.translate = translate
    }

    public init(restoring operation: StoredOperation) {
        let selectedOperation: WorkspaceOperationKind = operation.kind == .extract
            ? .extract
            : .translate
        let restoredSlot = WorkspaceOperationSlot(restoring: operation)
        self.init(
            selectedOperation: selectedOperation,
            extract: selectedOperation == .extract ? restoredSlot : WorkspaceOperationSlot(),
            translate: selectedOperation == .translate ? restoredSlot : WorkspaceOperationSlot()
        )
    }
}

private extension WorkspaceOperationSlot {
    init(restoring operation: StoredOperation) {
        let committedResult = operation.sourceMarkdown.map {
            WorkspaceCommittedResult(
                sourceMarkdown: $0,
                translationMarkdown: operation.translationMarkdown
            )
        }
        let attempt: WorkspaceAttemptState = switch operation.status {
        case .succeeded:
            committedResult == nil
                ? .failed(code: "incomplete_output")
                : .succeeded
        case .failed:
            .failed(code: operation.normalizedErrorCode ?? "operation_failed")
        case .canceled:
            .canceled
        case .resultPersistenceFailed:
            .failed(code: operation.normalizedErrorCode ?? "result_persistence_failed")
        case .preparing, .uploading, .streaming, .interrupted:
            .failed(code: operation.normalizedErrorCode ?? "interrupted")
        }
        self.init(attempt: attempt, committedResult: committedResult)
    }
}

public actor OperationWorkspaceSession {
    private let originalPNG: Data
    private let runner: any OperationWorkspaceRunning
    private let activeGate: any OperationActivityGating
    private var selectedOperation: WorkspaceOperationKind = .extract
    private var extract = WorkspaceOperationSlot()
    private var translate = WorkspaceOperationSlot()
    private var activeTask: Task<Void, Error>?
    private var activeOperation: WorkspaceOperationKind?
    private var isStarting = false
    private var startCancelled = false
    private var acceptsOperationStarts = true

    public init(
        originalPNG: Data,
        runner: any OperationWorkspaceRunning,
        activeGate: any OperationActivityGating
    ) {
        self.originalPNG = originalPNG
        self.runner = runner
        self.activeGate = activeGate
    }

    public func select(_ operation: WorkspaceOperationKind) {
        selectedOperation = operation
    }

    public func snapshot() -> OperationWorkspaceSnapshot {
        OperationWorkspaceSnapshot(
            selectedOperation: selectedOperation,
            extract: extract,
            translate: translate
        )
    }

    public func prepareForCapture() -> WorkspaceCapturePreparation {
        guard acceptsOperationStarts else {
            return .alreadyPrepared
        }
        guard activeTask == nil, !isStarting else {
            return .presentWorkspace
        }
        guard extract.unsavedResult == nil, translate.unsavedResult == nil else {
            return .presentWorkspace
        }
        acceptsOperationStarts = false
        return .beginCapture
    }

    public func reserveReplacementWithSavedHistory() -> Bool {
        prepareForCapture() == .beginCapture
    }

    public func startSelectedOperation(
        selection: ProviderSelection,
        targetLanguage: String
    ) async throws {
        guard acceptsOperationStarts else {
            throw OperationWorkspaceSessionError.busy
        }
        guard extract.unsavedResult == nil, translate.unsavedResult == nil else {
            throw OperationWorkspaceSessionError.unsavedResultRequiresSave
        }
        guard activeTask == nil, !isStarting else {
            throw OperationWorkspaceSessionError.busy
        }
        let requestedOperation = selectedOperation
        isStarting = true
        startCancelled = false
        activeOperation = requestedOperation
        guard let lease = await activeGate.acquire() else {
            isStarting = false
            activeOperation = nil
            throw OperationWorkspaceSessionError.busy
        }
        if startCancelled || Task.isCancelled {
            isStarting = false
            activeOperation = nil
            await activeGate.release(lease)
            throw CancellationError()
        }
        let task = Task {
            try await self.runOperation(
                requestedOperation,
                selection: selection,
                targetLanguage: targetLanguage
            )
        }
        activeTask = task
        activeOperation = requestedOperation
        isStarting = false
        do {
            try await task.value
            activeTask = nil
            activeOperation = nil
            await activeGate.release(lease)
        } catch {
            activeTask = nil
            activeOperation = nil
            await activeGate.release(lease)
            throw error
        }
    }

    public func close() -> WorkspaceCloseDisposition {
        if isStarting, let activeOperation {
            startCancelled = true
            let committedResult = slot(for: activeOperation).committedResult
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .canceled,
                    committedResult: committedResult
                ),
                for: activeOperation
            )
            return .cancelAndHide
        }
        if let activeTask, let activeOperation {
            activeTask.cancel()
            let committedResult = slot(for: activeOperation).committedResult
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .canceled,
                    committedResult: committedResult
                ),
                for: activeOperation
            )
            return .cancelAndHide
        }
        if extract.unsavedResult != nil || translate.unsavedResult != nil {
            return .confirmDiscardUnsavedResult
        }
        let hasAnyResult = extract.attempt != .neverStarted
            || translate.attempt != .neverStarted
        return hasAnyResult ? .hide : .discard
    }

    public func discardUnsavedResults() {
        extract = slotByDiscardingUnsavedResult(extract)
        translate = slotByDiscardingUnsavedResult(translate)
    }

    public func retrySavingSelectedResult() async throws {
        let kind = selectedOperation
        guard slot(for: kind).unsavedResult != nil else {
            throw OperationWorkspaceSessionError.noUnsavedResult
        }
        let saved = try await runner.retrySavingResult()
        setSlot(
            WorkspaceOperationSlot(
                attempt: .succeeded,
                committedResult: saved
            ),
            for: kind
        )
    }

    private func slotByDiscardingUnsavedResult(
        _ slot: WorkspaceOperationSlot
    ) -> WorkspaceOperationSlot {
        WorkspaceOperationSlot(
            attempt: slot.attempt,
            committedResult: slot.committedResult,
            sourceDelta: slot.sourceDelta,
            translationDelta: slot.translationDelta
        )
    }

    private func runOperation(
        _ kind: WorkspaceOperationKind,
        selection: ProviderSelection,
        targetLanguage: String
    ) async throws {
        let committedResult = slot(for: kind).committedResult
        setSlot(
            WorkspaceOperationSlot(
                attempt: .preparing,
                committedResult: committedResult
            ),
            for: kind
        )
        let operation: ProviderOperation = switch kind {
        case .extract:
            .extractText
        case .translate:
            .translate(targetLanguage: targetLanguage)
        }
        let events = await runner.run(
            originalPNG: originalPNG,
            operation: operation,
            selection: selection
        )
        do {
            for try await event in events {
                apply(event, to: kind)
            }
        } catch {
            let retained = slot(for: kind).committedResult
            if Task.isCancelled || error is CancellationError {
                setSlot(
                    WorkspaceOperationSlot(
                        attempt: .canceled,
                        committedResult: retained
                    ),
                    for: kind
                )
                throw CancellationError()
            }
            let failureCode = (error as? OperationWorkspaceRunFailure)?.code
                ?? "operation_failed"
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .failed(code: failureCode),
                    committedResult: retained
                ),
                for: kind
            )
            throw error
        }
        if Task.isCancelled || slot(for: kind).attempt == .canceled {
            throw CancellationError()
        }
        let terminalAttempt = slot(for: kind).attempt
        guard terminalAttempt == .succeeded
                || terminalAttempt == .resultPersistenceFailed
        else {
            let retained = slot(for: kind).committedResult
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .failed(code: "incomplete_run"),
                    committedResult: retained
                ),
                for: kind
            )
            throw OperationWorkspaceSessionError.incompleteRun
        }
    }

    private func apply(
        _ event: OperationWorkspaceRunEvent,
        to kind: WorkspaceOperationKind
    ) {
        let current = slot(for: kind)
        guard current.attempt == .preparing || current.attempt == .streaming else {
            return
        }
        switch event {
        case let .sourceDelta(delta):
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .streaming,
                    committedResult: current.committedResult,
                    unsavedResult: current.unsavedResult,
                    sourceDelta: current.sourceDelta + delta,
                    translationDelta: current.translationDelta
                ),
                for: kind
            )
        case let .translationDelta(delta):
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .streaming,
                    committedResult: current.committedResult,
                    unsavedResult: current.unsavedResult,
                    sourceDelta: current.sourceDelta,
                    translationDelta: current.translationDelta + delta
                ),
                for: kind
            )
        case let .succeeded(result):
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .succeeded,
                    committedResult: result
                ),
                for: kind
            )
        case let .resultPersistenceFailed(result):
            setSlot(
                WorkspaceOperationSlot(
                    attempt: .resultPersistenceFailed,
                    committedResult: current.committedResult,
                    unsavedResult: result
                ),
                for: kind
            )
        }
    }

    private func slot(
        for kind: WorkspaceOperationKind
    ) -> WorkspaceOperationSlot {
        switch kind {
        case .extract:
            extract
        case .translate:
            translate
        }
    }

    private func setSlot(
        _ slot: WorkspaceOperationSlot,
        for kind: WorkspaceOperationKind
    ) {
        switch kind {
        case .extract:
            extract = slot
        case .translate:
            translate = slot
        }
    }
}
