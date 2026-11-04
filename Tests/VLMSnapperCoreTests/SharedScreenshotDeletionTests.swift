import Foundation
import SQLite3
import Testing
@testable import VLMSnapperCore

/// v1-core::REQ-014 on the real history database and screenshot store: operations on one capture share
/// its file, as `PersistedOperationWorkspaceRunner` saves it once per capture.
@Suite("Deleting records that share a screenshot")
struct SharedScreenshotDeletionTests {
    @Test("the file stays until the last record that uses it is deleted")
    func fileStaysUntilLastRecord() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let first = try await fixture.addRecord(.extractText)
        let second = try await fixture.addRecord(.translate(targetLanguage: "ja"))

        let summary = await fixture.deletion.delete(recordIDs: [first], includePinned: true)

        #expect(summary == HistoryDeletionSummary(deleted: 1, failed: 0, skipped: 0))
        #expect(try await fixture.store.operation(id: first) == nil)
        #expect(try await fixture.screenshots.loadIfOwned(fixture.screenshot) == fixture.png)

        let last = await fixture.deletion.delete(recordIDs: [second], includePinned: true)

        #expect(last == HistoryDeletionSummary(deleted: 1, failed: 0, skipped: 0))
        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))
    }

    @Test("deleting every record of a screenshot in one batch removes the file")
    func batchRemovesFile() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let first = try await fixture.addRecord(.extractText)
        let second = try await fixture.addRecord(.translate(targetLanguage: "ja"))

        let summary = await fixture.deletion.delete(recordIDs: [first, second], includePinned: true)

        #expect(summary == HistoryDeletionSummary(deleted: 2, failed: 0, skipped: 0))
        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))
    }

    @Test("a record skipped by a batch keeps the file and is reported")
    func skippedRecordKeepsFile() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let pinned = try await fixture.addRecord(.extractText)
        let plain = try await fixture.addRecord(.translate(targetLanguage: "ja"))
        try await fixture.store.setPinned(true, operationID: pinned)

        let summary = await fixture.deletion.delete(recordIDs: [plain, pinned], includePinned: false)

        #expect(summary == HistoryDeletionSummary(deleted: 1, failed: 0, skipped: 1))
        #expect(try await fixture.screenshots.loadIfOwned(fixture.screenshot) == fixture.png)
        #expect(try await fixture.store.operation(id: pinned) != nil)
    }

    @Test("a record on another screenshot does not keep this one")
    func otherScreenshotDoesNotCount() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let record = try await fixture.addRecord(.extractText)
        let other = try await fixture.screenshots.save(originalPNG: Data([0x89, 0x51]))
        _ = try await fixture.addRecord(.extractText, on: other)

        _ = await fixture.deletion.delete(recordIDs: [record], includePinned: true)

        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    // Two captures of the same pixels: the digest matches and the files are separate.
    @Test("a record on a file with the same contents does not keep this one")
    func sameContentsInAnotherFileDoesNotCount() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let record = try await fixture.addRecord(.extractText)
        let other = try await fixture.screenshots.save(originalPNG: fixture.png)
        #expect(other.sha256 == fixture.screenshot.sha256)
        #expect(other.path != fixture.screenshot.path)
        _ = try await fixture.addRecord(.extractText, on: other)

        _ = await fixture.deletion.delete(recordIDs: [record], includePinned: true)

        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    // A record from before a replacement at the same path: same path, another digest.
    @Test("a record on the same path with other contents does not keep this file")
    func samePathWithOtherContentsDoesNotCount() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let record = try await fixture.addRecord(.extractText)
        let replaced = ManagedScreenshot(path: fixture.screenshot.path, sha256: "another-digest")
        _ = try await fixture.addRecord(.extractText, on: replaced)

        _ = await fixture.deletion.delete(recordIDs: [record], includePinned: true)

        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))
    }

    @Test("when the last record cannot be deleted the file is gone, the failure is reported, and deleting again clears it")
    func failedDeleteOfLastRecord() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        let first = try await fixture.addRecord(.extractText)
        let second = try await fixture.addRecord(.translate(targetLanguage: "ja"))
        try fixture.failDeletes(of: second)

        let summary = await fixture.deletion.delete(recordIDs: [first, second], includePinned: true)

        #expect(summary == HistoryDeletionSummary(deleted: 1, failed: 1, skipped: 0))
        #expect(try await fixture.store.operation(id: first) == nil)
        #expect(try await fixture.store.operation(id: second) != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.screenshot.path))

        try fixture.allowDeletes()
        let retried = await fixture.deletion.delete(recordIDs: [second], includePinned: true)

        #expect(retried == HistoryDeletionSummary(deleted: 1, failed: 0, skipped: 0))
        #expect(try await fixture.store.operation(id: second) == nil)
    }

    @Test("automatic cleanup of one expired record leaves the file for the record that remains")
    func cleanupKeepsSharedFile() async throws {
        let fixture = try await SharedScreenshotFixture()
        defer { fixture.remove() }
        fixture.clock.date = Date().addingTimeInterval(-90 * 86_400)
        let expired = try await fixture.addRecord(.extractText)
        fixture.clock.date = Date()
        let current = try await fixture.addRecord(.translate(targetLanguage: "ja"))
        let cleanup = HistoryCleanupCoordinator(historyStore: fixture.store, deletionCoordinator: fixture.deletion)

        let summary = await cleanup.clean(retention: .sevenDays)

        #expect(summary == HistoryDeletionSummary(deleted: 1, failed: 0, skipped: 0))
        #expect(try await fixture.store.operation(id: expired) == nil)
        #expect(try await fixture.store.operation(id: current) != nil)
        #expect(try await fixture.screenshots.loadIfOwned(fixture.screenshot) == fixture.png)
    }
}

private final class SharedScreenshotClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var date: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private struct SharedScreenshotFixture {
    let root: URL
    let clock = SharedScreenshotClock()
    let store: SQLiteHistoryStore
    let screenshots: FileSystemScreenshotStore
    let deletion: HistoryDeletionCoordinator
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let screenshot: ManagedScreenshot

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let clock = self.clock
        store = try SQLiteHistoryStore(
            databaseURL: root.appendingPathComponent("history.sqlite"),
            now: { clock.date }
        )
        screenshots = FileSystemScreenshotStore(rootDirectory: root.appendingPathComponent("Pictures", isDirectory: true))
        deletion = HistoryDeletionCoordinator(historyStore: store, screenshotStore: screenshots)
        screenshot = try await screenshots.save(originalPNG: png)
    }

    func addRecord(_ operation: ProviderOperation, on file: ManagedScreenshot? = nil) async throws -> UUID {
        let prepared = try await store.prepareOperation(
            screenshot: file ?? screenshot,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision"),
            operation: operation
        )
        let translation: String? = if case .translate = operation { "Translation" } else { nil }
        try await store.finish(
            operationID: prepared.operationID,
            with: .succeeded(sourceMarkdown: "Source", translationMarkdown: translation)
        )
        return prepared.operationID
    }

    /// A real database error on deleting one record, as a locked or damaged database gives.
    func failDeletes(of id: UUID) throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        try #require(sqlite3_open(root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK)
        let sql = "CREATE TRIGGER fail_delete BEFORE DELETE ON operations WHEN OLD.id = '\(id.uuidString)' "
            + "BEGIN SELECT RAISE(FAIL, 'fixture'); END"
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    func allowDeletes() throws {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        try #require(sqlite3_open(root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK)
        try #require(sqlite3_exec(database, "DROP TRIGGER fail_delete", nil, nil, nil) == SQLITE_OK)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
