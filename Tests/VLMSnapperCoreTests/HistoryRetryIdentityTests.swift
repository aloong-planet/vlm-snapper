import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Restored history retry identity")
struct HistoryRetryIdentityTests {
    @Test
    func restoredTranslationKeepsLanguageAndMetadata() async throws {
        try await withHistory { store, screenshots, record, png in
            let provider = RetryProvider()
            let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshots,
                historyStore: store, provider: provider, restoring: record.operation)
            let selection = ProviderSelection(providerID: "gemini", modelID: "new-model")
            _ = try await collectRetry(await runner.run(originalPNG: png,
                operation: .translate(targetLanguage: "en"), selection: selection))
            let updated = try #require(try await store.historyRecord(id: record.id))
            #expect(updated.operation.targetLanguage == "ja")
            #expect(await provider.operations == [.translate(targetLanguage: "ja")])
            #expect(updated.operation.sourceMarkdown == "New source")
            #expect(updated.operation.translationMarkdown == "New translation")
            #expect(updated.operation.selection.providerID == "gemini")
            #expect(updated.operation.selection.modelID == "new-model")
            #expect(updated.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(updated.isPinned)
            #expect(updated.operation.screenshot == record.operation.screenshot)
            #expect(updated.metrics.usage == ProviderTokenUsage(inputTokens: 7, outputTokens: 3, totalTokens: 10))
            #expect(try await store.history(matching: HistoryQuery(searchText: "Archived")).isEmpty)
            #expect(try await store.history(matching: HistoryQuery(providerID: "gemini", searchText: "New source")).map(\.id) == [record.id])
        }
    }

    @Test(arguments: [false, true])
    func restoredRetryRejectsMissingRecordOrChangedImage(removeRecord: Bool) async throws {
        try await withHistory { store, screenshots, record, png in
            let provider = RetryProvider()
            let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshots,
                historyStore: store, provider: provider, restoring: record.operation)
            if removeRecord {
                #expect(try await store.deleteHistoryRecord(id: record.id) == .deleted)
            } else {
                try Data("replacement".utf8).write(to: URL(fileURLWithPath: record.operation.screenshot.path))
            }
            await #expect(throws: OperationWorkspaceRunFailure.self) {
                _ = try await collectRetry(await runner.run(originalPNG: png,
                    operation: .translate(targetLanguage: "ja"), selection: record.operation.selection))
            }
            #expect(await provider.operations.isEmpty)
            #expect(try await store.history(matching: HistoryQuery()).count == (removeRecord ? 0 : 1))
            if !removeRecord {
                #expect(try await store.historyRecord(id: record.id) == record)
            }
        }
    }

    @Test
    func deletingTargetBeforeCommitCannotRecreateIt() async throws {
        try await withHistory { store, screenshots, record, png in
            let provider = RetryProvider(beforeCompletion: {
                _ = try await store.deleteHistoryRecord(id: record.id)
            })
            let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshots,
                historyStore: store, provider: provider, restoring: record.operation)
            let session = OperationWorkspaceSession(originalPNG: png, runner: runner,
                activeGate: ActiveOperationGate(), restoring: record.operation)
            try await session.startSelectedOperation(selection: record.operation.selection, targetLanguage: "ja")
            let snapshot = await session.snapshot()
            #expect(snapshot.translate.attempt == .resultPersistenceFailed)
            #expect(snapshot.translate.persistenceFailureCode == "history_record_unavailable")
            #expect(snapshot.translate.unsavedResult?.sourceMarkdown == "New source")
            #expect(snapshot.translate.committedResult?.sourceMarkdown == "Archived source")
            await #expect(throws: (any Error).self) { try await session.retrySavingSelectedResult() }
            #expect(try await store.history(matching: HistoryQuery()).isEmpty)
            #expect(await provider.operations.count == 1)
            #expect(await session.close() == .confirmDiscardUnsavedResult)
            #expect(await session.preventsHistoryDiscard)
            await session.discardUnsavedResults()
            #expect(await !session.preventsHistoryDiscard)
        }
    }

    @Test
    func pinChangedDuringRetryAndUnrelatedRowsSurviveCommit() async throws {
        try await withHistory { store, screenshots, record, png in
            let other = try await store.prepareExtraction(screenshot: record.operation.screenshot,
                selection: record.operation.selection)
            try await store.finish(operationID: other.operationID,
                with: .succeeded(sourceMarkdown: "Unrelated", translationMarkdown: nil))
            let originalOther = try await store.historyRecord(id: other.operationID)
            let provider = RetryProvider(beforeCompletion: { try await store.setPinned(false, operationID: record.id) })
            let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshots,
                historyStore: store, provider: provider, restoring: record.operation)
            for _ in 0..<2 {
                _ = try await collectRetry(await runner.run(originalPNG: png,
                    operation: .translate(targetLanguage: "ja"), selection: record.operation.selection))
            }
            #expect(try await store.historyRecord(id: record.id)?.isPinned == false)
            #expect(try await store.historyRecord(id: other.operationID) == originalOther)
            #expect(try await store.history(matching: HistoryQuery()).count == 2)
            let reopened = try SQLiteHistoryStore(databaseURL: URL(fileURLWithPath: record.operation.screenshot.path)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("history.sqlite"))
            #expect(try await reopened.operation(id: record.id)?.sourceMarkdown == "New source")
            #expect(try await screenshots.loadIfOwned(record.operation.screenshot) == png)
            let imageDirectory = URL(fileURLWithPath: record.operation.screenshot.path).deletingLastPathComponent()
            #expect(try FileManager.default.contentsOfDirectory(atPath: imageDirectory.path).filter { $0.hasSuffix(".png") }.count == 1)
        }
    }

    @Test(arguments: [OperationStatus.succeeded, .failed, .canceled, .interrupted])
    func failedOrCanceledRetryPreservesEntireArchivedRecord(status: OperationStatus) async throws {
        try await withHistory { store, screenshots, record, png in
            switch status {
            case .failed:
                try await store.finish(operationID: record.id, with: .failed(normalizedErrorCode: "transport"))
            case .canceled:
                try await store.finish(operationID: record.id, as: .canceled)
            case .interrupted:
                try await store.markInFlight(operationID: record.id, as: .uploading)
                _ = try await store.recoverUnfinishedOperations()
            default: break
            }
            let original = try #require(try await store.historyRecord(id: record.id))
            for cancellation in [false, true] {
                let provider = RetryProvider(beforeCompletion: {
                    if cancellation { throw CancellationError() }
                    throw OperationWorkspaceRunFailure(code: "transport")
                })
                let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshots,
                    historyStore: store, provider: provider, restoring: original.operation)
                let session = OperationWorkspaceSession(originalPNG: png, runner: runner,
                    activeGate: ActiveOperationGate(), restoring: original.operation)
                await #expect(throws: (any Error).self) {
                    try await session.startSelectedOperation(selection: original.operation.selection, targetLanguage: "ja")
                }
                #expect(try await store.historyRecord(id: record.id) == original)
                #expect(try await store.history(matching: HistoryQuery()).count == 1)
                #expect(await session.snapshot().translate.committedResult?.sourceMarkdown == original.operation.sourceMarkdown)
                #expect(try await store.recoverUnfinishedOperations() == 0)
                #expect(await provider.operations.count == 1)
            }
        }
    }
}

private func withHistory(
    _ body: (SQLiteHistoryStore, FileSystemScreenshotStore, HistoryRecord, Data) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try SQLiteHistoryStore(databaseURL: root.appendingPathComponent("history.sqlite"),
        now: { Date(timeIntervalSince1970: 1_800_000_000) })
    let screenshots = FileSystemScreenshotStore(rootDirectory: root.appendingPathComponent("Pictures", isDirectory: true))
    let png = Data([0x89, 0x50, 0x4e, 0x47])
    let screenshot = try await screenshots.save(originalPNG: png)
    let prepared = try await store.prepareOperation(screenshot: screenshot,
        selection: ProviderSelection(providerID: "deepseek", modelID: "old-model"),
        operation: .translate(targetLanguage: "ja"))
    try await store.finish(operationID: prepared.operationID,
        with: .succeeded(sourceMarkdown: "Archived source", translationMarkdown: "Archived translation"))
    try await store.setPinned(true, operationID: prepared.operationID)
    let record = try #require(try await store.historyRecord(id: prepared.operationID))
    try await body(store, screenshots, record, png)
}

private func collectRetry(
    _ stream: AsyncThrowingStream<OperationWorkspaceRunEvent, Error>
) async throws -> [OperationWorkspaceRunEvent] {
    var result: [OperationWorkspaceRunEvent] = []
    for try await event in stream { result.append(event) }
    return result
}

private actor RetryProvider: PreparedOperationStreaming {
    private(set) var operations: [ProviderOperation] = []
    private let beforeCompletion: @Sendable () async throws -> Void
    init(beforeCompletion: @escaping @Sendable () async throws -> Void = {}) {
        self.beforeCompletion = beforeCompletion
    }
    func stream(originalPNG: Data, preparedOperation: PreparedOperation) async
        -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        operations.append(preparedOperation.operation)
        do { try await beforeCompletion() }
        catch { return AsyncThrowingStream { $0.finish(throwing: error) } }
        return AsyncThrowingStream { continuation in
            continuation.yield(.sourceDelta("New source"))
            if case .translate = preparedOperation.operation {
                continuation.yield(.translationDelta("New translation"))
            }
            continuation.yield(.metadata(ProviderResponseMetadata(requestID: nil,
                usage: ProviderTokenUsage(inputTokens: 7, outputTokens: 3, totalTokens: 10))))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
