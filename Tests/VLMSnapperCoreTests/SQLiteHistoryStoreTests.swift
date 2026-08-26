import Foundation
import SQLite3
import Testing
@testable import VLMSnapperCore

@Suite("SQLite history store")
struct SQLiteHistoryStoreTests {
    @Test("a typed translation operation persists its target language")
    func typedTranslationPersistsTargetLanguage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteHistoryStore(
            databaseURL: directory.appendingPathComponent("history.sqlite")
        )

        let prepared = try await store.prepareOperation(
            screenshot: ManagedScreenshot(path: "/Pictures/result.png", sha256: "sha"),
            selection: ProviderSelection(providerID: "gemini", modelID: "vision"),
            operation: .translate(targetLanguage: "en")
        )

        let operation = try await store.operation(id: prepared.operationID)
        #expect(operation?.kind == .translate)
        #expect(operation?.targetLanguage == "en")
    }

    @Test("a prepared extraction survives reopening the database")
    func preparedExtractionSurvivesReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-153000.png",
            sha256: "persisted-sha256"
        )
        let selection = ProviderSelection(
            providerID: "openai",
            modelID: "gpt-vision"
        )

        let prepared: PreparedExtraction
        do {
            let store = try SQLiteHistoryStore(databaseURL: databaseURL)
            prepared = try await store.prepareExtraction(
                screenshot: screenshot,
                selection: selection
            )
        }

        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await reopened.operation(id: prepared.operationID)
        #expect(
            operation == StoredOperation(
                id: prepared.operationID,
                screenshot: screenshot,
                selection: selection,
                status: .preparing
            )
        )
    }

    @Test("a succeeded extraction remains succeeded after reopening")
    func succeededExtractionSurvivesReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let prepared = try await store.prepareExtraction(
            screenshot: ManagedScreenshot(path: "/Pictures/VLMSnapper/result.png", sha256: "sha"),
            selection: ProviderSelection(providerID: "gemini", modelID: "gemini-vision")
        )

        try await store.finish(
            operationID: prepared.operationID,
            with: .succeeded(sourceMarkdown: "Recognized text", translationMarkdown: nil)
        )

        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await reopened.operation(id: prepared.operationID)
        #expect(operation?.status == .succeeded)
    }

    @Test(
        "other terminal completions persist their exact status",
        arguments: [
            (OperationCompletion.canceled, "canceled"),
            (OperationCompletion.resultPersistenceFailed, "resultPersistenceFailed"),
        ]
    )
    func otherTerminalCompletionsPersistExactStatus(
        completion: OperationCompletion,
        expectedStatus: String
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SQLiteHistoryStore(
            databaseURL: directory.appendingPathComponent("history.sqlite")
        )
        let prepared = try await store.prepareExtraction(
            screenshot: ManagedScreenshot(path: "/Pictures/VLMSnapper/result.png", sha256: "sha"),
            selection: ProviderSelection(providerID: "openai", modelID: "gpt-vision")
        )

        try await store.finish(operationID: prepared.operationID, as: completion)

        let operation = try await store.operation(id: prepared.operationID)
        #expect(operation?.status.rawValue == expectedStatus)
    }

    @Test("an uploading extraction remains uploading after reopening")
    func uploadingExtractionSurvivesReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let prepared = try await store.prepareExtraction(
            screenshot: ManagedScreenshot(path: "/Pictures/VLMSnapper/upload.png", sha256: "sha"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "deepseek-vision")
        )

        try await store.markInFlight(operationID: prepared.operationID, as: .uploading)

        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await reopened.operation(id: prepared.operationID)
        #expect(operation?.status == .uploading)
    }

    @Test("startup recovery interrupts only unfinished operations")
    func startupRecoveryInterruptsOnlyUnfinishedOperations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)

        let preparing = try await makeOperation(in: store, suffix: "preparing")
        let uploading = try await makeOperation(in: store, suffix: "uploading")
        try await store.markInFlight(operationID: uploading.operationID, as: .uploading)
        let streaming = try await makeOperation(in: store, suffix: "streaming")
        try await store.markInFlight(operationID: streaming.operationID, as: .streaming)
        let succeeded = try await makeOperation(in: store, suffix: "succeeded")
        try await store.finish(
            operationID: succeeded.operationID,
            with: .succeeded(sourceMarkdown: "Complete", translationMarkdown: nil)
        )

        let recoveredCount = try await store.recoverUnfinishedOperations()

        #expect(recoveredCount == 3)
        #expect(try await store.operation(id: preparing.operationID)?.status == .interrupted)
        #expect(try await store.operation(id: uploading.operationID)?.status == .interrupted)
        #expect(try await store.operation(id: streaming.operationID)?.status == .interrupted)
        #expect(try await store.operation(id: succeeded.operationID)?.status == .succeeded)
    }

    @Test("a newer schema version blocks opening the history store")
    func newerSchemaVersionBlocksOpeningHistoryStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        try makeDatabase(at: databaseURL, schemaVersion: 3)
        let bytesBeforeOpen = try Data(contentsOf: databaseURL)

        do {
            _ = try SQLiteHistoryStore(databaseURL: databaseURL)
            Issue.record("Expected a newer schema to block the history store")
        } catch {
            #expect(
                error as? SQLiteHistoryStoreError == .schemaTooNew(found: 3, supported: 2)
            )
        }
        #expect(try Data(contentsOf: databaseURL) == bytesBeforeOpen)
    }

    @Test("version-one rows migrate to typed extraction operations")
    func versionOneRowsMigrateToExtraction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let operationID = UUID()
        try makeDatabase(
            at: databaseURL,
            schemaVersion: 1,
            operationsSQL: """
                id TEXT PRIMARY KEY NOT NULL,
                screenshot_path TEXT NOT NULL,
                screenshot_sha256 TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                model_id TEXT NOT NULL,
                status TEXT NOT NULL,
                source_markdown TEXT,
                translation_markdown TEXT,
                normalized_error_code TEXT
                """
        )
        try executeSQL(
            """
            INSERT INTO operations (
                id, screenshot_path, screenshot_sha256, provider_id, model_id, status
            ) VALUES (
                '\(operationID.uuidString)', '/Pictures/legacy.png', 'sha',
                'openai', 'vision', 'succeeded'
            )
            """,
            at: databaseURL
        )

        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await store.operation(id: operationID)

        #expect(operation?.kind == .extract)
        #expect(operation?.targetLanguage == nil)
    }

    @Test("a corrupted database is blocked without changing its bytes")
    func corruptedDatabaseIsBlockedWithoutChangingItsBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let corruptBytes = Data("not-a-sqlite-database".utf8)
        try corruptBytes.write(to: databaseURL)

        #expect(throws: SQLiteHistoryStoreError.self) {
            _ = try SQLiteHistoryStore(databaseURL: databaseURL)
        }
        #expect(try Data(contentsOf: databaseURL) == corruptBytes)
    }

    @Test("an incomplete version-one schema is blocked without modification")
    func incompleteVersionOneSchemaIsBlockedWithoutModification() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        try makeDatabase(at: databaseURL, schemaVersion: 1, operationsSQL: "id TEXT")
        let bytesBeforeOpen = try Data(contentsOf: databaseURL)

        #expect(throws: SQLiteHistoryStoreError.self) {
            _ = try SQLiteHistoryStore(databaseURL: databaseURL)
        }
        #expect(try Data(contentsOf: databaseURL) == bytesBeforeOpen)
    }

    @Test("reset preserves a corrupted database before creating an empty store")
    func resetPreservesCorruptedDatabaseBeforeCreatingEmptyStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let corruptBytes = Data("recover-this-database".utf8)
        try corruptBytes.write(to: databaseURL)
        let walBytes = Data("recover-this-wal".utf8)
        try walBytes.write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
        let shmBytes = Data("recover-this-shm".utf8)
        try shmBytes.write(to: URL(fileURLWithPath: databaseURL.path + "-shm"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let resetter = HistoryDatabaseResetter(
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_787_725_812) }
        )

        let recoveryURL = try resetter.reset(databaseAt: databaseURL)

        #expect(recoveryURL.lastPathComponent == "history-recovery-20260826-143012.sqlite")
        #expect(try Data(contentsOf: recoveryURL) == corruptBytes)
        #expect(try Data(contentsOf: URL(fileURLWithPath: recoveryURL.path + "-wal")) == walBytes)
        #expect(try Data(contentsOf: URL(fileURLWithPath: recoveryURL.path + "-shm")) == shmBytes)
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        let resetStore = try SQLiteHistoryStore(databaseURL: databaseURL)
        #expect(try await resetStore.operation(id: UUID()) == nil)
    }

    @Test("reset never overwrites an existing recovery file from the same second")
    func resetNeverOverwritesExistingRecoveryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let corruptBytes = Data("new-recovery".utf8)
        try corruptBytes.write(to: databaseURL)
        let existingRecovery = directory
            .appendingPathComponent("history-recovery-20260826-143012.sqlite")
        let existingBytes = Data("existing-recovery".utf8)
        try existingBytes.write(to: existingRecovery)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let resetter = HistoryDatabaseResetter(
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_787_725_812) }
        )

        let recoveryURL = try resetter.reset(databaseAt: databaseURL)

        #expect(recoveryURL.lastPathComponent == "history-recovery-20260826-143012-2.sqlite")
        #expect(try Data(contentsOf: existingRecovery) == existingBytes)
        #expect(try Data(contentsOf: recoveryURL) == corruptBytes)
    }

    @Test("a successful result survives reopening the database")
    func successfulResultSurvivesReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let prepared = try await makeOperation(in: store, suffix: "translated")

        try await store.finish(
            operationID: prepared.operationID,
            with: .succeeded(
                sourceMarkdown: "# Original\n\nHello",
                translationMarkdown: "# Translation\n\nBonjour"
            )
        )

        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await reopened.operation(id: prepared.operationID)
        #expect(operation?.status == .succeeded)
        #expect(operation?.sourceMarkdown == "# Original\n\nHello")
        #expect(operation?.translationMarkdown == "# Translation\n\nBonjour")
        #expect(operation?.normalizedErrorCode == nil)
    }

    @Test("a normalized failure reason survives reopening the database")
    func normalizedFailureReasonSurvivesReopeningDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        let store = try SQLiteHistoryStore(databaseURL: databaseURL)
        let prepared = try await makeOperation(in: store, suffix: "failed")

        try await store.finish(
            operationID: prepared.operationID,
            with: .failed(normalizedErrorCode: "authentication")
        )

        let reopened = try SQLiteHistoryStore(databaseURL: databaseURL)
        let operation = try await reopened.operation(id: prepared.operationID)
        #expect(operation?.status == .failed)
        #expect(operation?.normalizedErrorCode == "authentication")
        #expect(operation?.sourceMarkdown == nil)
        #expect(operation?.translationMarkdown == nil)
    }

    private func makeOperation(
        in store: SQLiteHistoryStore,
        suffix: String
    ) async throws -> PreparedExtraction {
        try await store.prepareExtraction(
            screenshot: ManagedScreenshot(
                path: "/Pictures/VLMSnapper/\(suffix).png",
                sha256: "sha-\(suffix)"
            ),
            selection: ProviderSelection(providerID: "openai", modelID: "gpt-vision")
        )
    }

    private func makeDatabase(
        at url: URL,
        schemaVersion: Int,
        operationsSQL: String? = nil
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_close(database) }
        var sql = """
            CREATE TABLE metadata (key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL);
            INSERT INTO metadata (key, value) VALUES ('schema_version', \(schemaVersion));
            """
        if let operationsSQL {
            sql += "CREATE TABLE operations (\(operationsSQL));"
        }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private func executeSQL(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }
}
