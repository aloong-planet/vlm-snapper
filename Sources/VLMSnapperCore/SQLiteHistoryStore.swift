import Foundation
import SQLite3

public enum OperationStatus: String, Equatable, Sendable {
    case preparing
    case uploading
    case streaming
    case succeeded
    case failed
    case canceled
    case interrupted
    case resultPersistenceFailed
}

public enum OperationCompletion: String, CaseIterable, Equatable, Sendable {
    case canceled
    case resultPersistenceFailed
}

public enum OperationProgress: String, CaseIterable, Equatable, Sendable {
    case uploading
    case streaming
}

public enum PersistedOperationOutcome: Equatable, Sendable {
    case succeeded(sourceMarkdown: String, translationMarkdown: String?, segments: [TranslationSegment]? = nil)
    case failed(normalizedErrorCode: String)
}

public enum PersistedOperationKind: String, Equatable, Sendable {
    case extract
    case translate
}

public struct PreparedOperation: Equatable, Sendable {
    public let operationID: UUID
    public let screenshot: ManagedScreenshot
    public let selection: ProviderSelection
    public let operation: ProviderOperation
    public var sourceSegments: [TranslationSegment]? = nil
}

public struct StoredOperation: Equatable, Sendable {
    public let id: UUID
    public let screenshot: ManagedScreenshot
    public let selection: ProviderSelection
    public let status: OperationStatus
    public let sourceMarkdown: String?
    public let translationMarkdown: String?
    public let normalizedErrorCode: String?
    public let kind: PersistedOperationKind
    public let targetLanguage: String?
    public let segments: [TranslationSegment]?

    public init(
        id: UUID,
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        status: OperationStatus,
        sourceMarkdown: String? = nil,
        translationMarkdown: String? = nil,
        normalizedErrorCode: String? = nil,
        kind: PersistedOperationKind = .extract,
        targetLanguage: String? = nil,
        segments: [TranslationSegment]? = nil
    ) {
        self.id = id
        self.screenshot = screenshot
        self.selection = selection
        self.status = status
        self.sourceMarkdown = sourceMarkdown
        self.translationMarkdown = translationMarkdown
        self.normalizedErrorCode = normalizedErrorCode
        self.kind = kind
        self.targetLanguage = targetLanguage
        self.segments = segments
    }
}

public enum SQLiteHistoryStoreError: Error, Equatable {
    case databaseFailure
    case operationNotFound
    case schemaTooNew(found: Int, supported: Int)
}

public actor SQLiteHistoryStore: HistoryPersisting {
    private static let supportedSchemaVersion = 4
    private nonisolated(unsafe) let database: OpaquePointer
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.now = now
        let databaseExisted = FileManager.default.fileExists(atPath: databaseURL.path)
        var connection: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &connection, flags, nil) == SQLITE_OK,
              let connection
        else {
            sqlite3_close(connection)
            throw SQLiteHistoryStoreError.databaseFailure
        }
        database = connection
        do {
            if databaseExisted {
                try Self.prepareExistingDatabase(connection, migrationDate: now())
            }
            try Self.execute("PRAGMA journal_mode = WAL", on: connection)
            try Self.execute("PRAGMA foreign_keys = ON", on: connection)
            if !databaseExisted {
                try Self.execute(
                    """
                    CREATE TABLE metadata (
                        key TEXT PRIMARY KEY NOT NULL,
                        value INTEGER NOT NULL
                    )
                    """,
                    on: connection
                )
                try Self.execute(
                    "INSERT INTO metadata (key, value) VALUES ('schema_version', 4)",
                    on: connection
                )
                try Self.execute(
                    """
                    CREATE TABLE operations (
                        id TEXT PRIMARY KEY NOT NULL,
                        screenshot_path TEXT NOT NULL,
                        screenshot_sha256 TEXT NOT NULL,
                        provider_id TEXT NOT NULL,
                        model_id TEXT NOT NULL,
                        status TEXT NOT NULL,
                        source_markdown TEXT,
                        translation_markdown TEXT,
                        normalized_error_code TEXT
                        , operation_kind TEXT NOT NULL
                        , target_language TEXT
                        , created_at REAL NOT NULL
                        , is_pinned INTEGER NOT NULL DEFAULT 0
                        , first_text_latency_ms INTEGER
                        , total_latency_ms INTEGER
                        , input_tokens INTEGER
                        , output_tokens INTEGER
                        , total_tokens INTEGER
                        , translation_segments TEXT
                    )
                    """,
                    on: connection
                )
            }
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction {
        let prepared = try await prepareOperation(
            screenshot: screenshot,
            selection: selection,
            operation: .extractText
        )
        return PreparedExtraction(
            operationID: prepared.operationID,
            screenshot: prepared.screenshot,
            selection: prepared.selection
        )
    }

    public func prepareOperation(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection,
        operation: ProviderOperation
    ) async throws -> PreparedOperation {
        let operationID = UUID()
        let kind: PersistedOperationKind
        let targetLanguage: String?
        switch operation {
        case .extractText:
            kind = .extract
            targetLanguage = nil
        case let .translate(language):
            kind = .translate
            targetLanguage = language
        }
        let sql = """
            INSERT INTO operations (
                id, screenshot_path, screenshot_sha256, provider_id, model_id, status,
                operation_kind, target_language, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(operationID.uuidString, at: 1, to: statement)
        try Self.bind(screenshot.path, at: 2, to: statement)
        try Self.bind(screenshot.sha256, at: 3, to: statement)
        try Self.bind(selection.providerID, at: 4, to: statement)
        try Self.bind(selection.modelID, at: 5, to: statement)
        try Self.bind(OperationStatus.preparing.rawValue, at: 6, to: statement)
        try Self.bind(kind.rawValue, at: 7, to: statement)
        try Self.bind(targetLanguage, at: 8, to: statement)
        try Self.bind(now().timeIntervalSince1970, at: 9, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        return PreparedOperation(
            operationID: operationID,
            screenshot: screenshot,
            selection: selection,
            operation: operation
        )
    }

    public func operation(id: UUID) async throws -> StoredOperation? {
        let sql = """
            SELECT screenshot_path, screenshot_sha256, provider_id, model_id, status,
                   source_markdown, translation_markdown, normalized_error_code,
                   operation_kind, target_language, translation_segments
            FROM operations WHERE id = ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(id.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE {
                return nil
            }
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard let path = Self.text(at: 0, from: statement),
              let sha256 = Self.text(at: 1, from: statement),
              let providerID = Self.text(at: 2, from: statement),
              let modelID = Self.text(at: 3, from: statement),
              let statusValue = Self.text(at: 4, from: statement),
              let status = OperationStatus(rawValue: statusValue),
              let kindValue = Self.text(at: 8, from: statement),
              let kind = PersistedOperationKind(rawValue: kindValue)
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        return StoredOperation(
            id: id,
            screenshot: ManagedScreenshot(path: path, sha256: sha256),
            selection: ProviderSelection(
                providerID: providerID,
                modelID: modelID
            ),
            status: status,
            sourceMarkdown: Self.text(at: 5, from: statement),
            translationMarkdown: Self.text(at: 6, from: statement),
            normalizedErrorCode: Self.text(at: 7, from: statement),
            kind: kind,
            targetLanguage: Self.text(at: 9, from: statement),
            segments: try Self.decodeSegments(Self.text(at: 10, from: statement))
        )
    }

    public func history(matching query: HistoryQuery) async throws -> [HistoryRecord] {
        try history(matching: query, operationID: nil)
    }

    private func history(
        matching query: HistoryQuery,
        operationID: UUID?
    ) throws -> [HistoryRecord] {
        enum Parameter {
            case text(String)
            case number(Double)
            case integer(Int)
        }
        var predicates = [String]()
        var parameters = [Parameter]()
        if let operationID {
            predicates.append("id = ?")
            parameters.append(.text(operationID.uuidString))
        }
        switch query.kind {
        case .all:
            break
        case .extract:
            predicates.append("operation_kind = ?")
            parameters.append(.text(PersistedOperationKind.extract.rawValue))
        case .translate:
            predicates.append("operation_kind = ?")
            parameters.append(.text(PersistedOperationKind.translate.rawValue))
        }
        if let status = query.status {
            predicates.append("status = ?")
            parameters.append(.text(status.rawValue))
        }
        if let providerID = query.providerID {
            predicates.append("provider_id = ?")
            parameters.append(.text(providerID))
        }
        if let modelID = query.modelID {
            predicates.append("model_id = ?")
            parameters.append(.text(modelID))
        }
        if let targetLanguage = query.targetLanguage {
            predicates.append("target_language = ?")
            parameters.append(.text(targetLanguage))
        }
        if let createdAtOrAfter = query.createdAtOrAfter {
            predicates.append("created_at >= ?")
            parameters.append(.number(createdAtOrAfter.timeIntervalSince1970))
        }
        if let createdBefore = query.createdBefore {
            predicates.append("created_at < ?")
            parameters.append(.number(createdBefore.timeIntervalSince1970))
        }
        if let isPinned = query.isPinned {
            predicates.append("is_pinned = ?")
            parameters.append(.integer(isPinned ? 1 : 0))
        }
        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            predicates.append(
                "(instr(lower(coalesce(source_markdown, '')), lower(?)) > 0 "
                    + "OR instr(lower(coalesce(translation_markdown, '')), lower(?)) > 0)"
            )
            parameters.append(.text(searchText))
            parameters.append(.text(searchText))
        }
        let whereClause = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
        let sql = """
            SELECT id, screenshot_path, screenshot_sha256, provider_id, model_id, status,
                   source_markdown, translation_markdown, normalized_error_code,
                   operation_kind, target_language, created_at, is_pinned,
                   first_text_latency_ms, total_latency_ms,
                   input_tokens, output_tokens, total_tokens, translation_segments
            FROM operations\(whereClause)
            ORDER BY created_at DESC, id DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch parameter {
            case let .text(value):
                try Self.bind(value, at: index, to: statement)
            case let .number(value):
                try Self.bind(value, at: index, to: statement)
            case let .integer(value):
                try Self.bind(value, at: index, to: statement)
            }
        }
        var records = [HistoryRecord]()
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return records
            }
            guard result == SQLITE_ROW,
                  let idValue = Self.text(at: 0, from: statement),
                  let id = UUID(uuidString: idValue),
                  let path = Self.text(at: 1, from: statement),
                  let sha256 = Self.text(at: 2, from: statement),
                  let providerID = Self.text(at: 3, from: statement),
                  let modelID = Self.text(at: 4, from: statement),
                  let statusValue = Self.text(at: 5, from: statement),
                  let status = OperationStatus(rawValue: statusValue),
                  let kindValue = Self.text(at: 9, from: statement),
                  let kind = PersistedOperationKind(rawValue: kindValue)
            else {
                throw SQLiteHistoryStoreError.databaseFailure
            }
            let usage: ProviderTokenUsage?
            if let input = Self.integer(at: 15, from: statement),
               let output = Self.integer(at: 16, from: statement),
               let total = Self.integer(at: 17, from: statement) {
                usage = ProviderTokenUsage(inputTokens: input, outputTokens: output, totalTokens: total)
            } else {
                usage = nil
            }
            records.append(
                HistoryRecord(
                    operation: StoredOperation(
                        id: id,
                        screenshot: ManagedScreenshot(path: path, sha256: sha256),
                        selection: ProviderSelection(providerID: providerID, modelID: modelID),
                        status: status,
                        sourceMarkdown: Self.text(at: 6, from: statement),
                        translationMarkdown: Self.text(at: 7, from: statement),
                        normalizedErrorCode: Self.text(at: 8, from: statement),
                        kind: kind,
                        targetLanguage: Self.text(at: 10, from: statement),
                        segments: try Self.decodeSegments(Self.text(at: 18, from: statement))
                    ),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                    isPinned: sqlite3_column_int(statement, 12) != 0,
                    metrics: PersistedOperationMetrics(
                        firstTextLatencyMilliseconds: Self.integer(at: 13, from: statement),
                        totalLatencyMilliseconds: Self.integer(at: 14, from: statement),
                        usage: usage
                    )
                )
            )
        }
    }

    public func historyRecord(id: UUID) async throws -> HistoryRecord? {
        try history(matching: HistoryQuery(), operationID: id).first
    }

    public func deleteHistoryRecord(id: UUID) async throws -> HistoryRecordDeletionResult {
        guard let operation = try await operation(id: id) else {
            return .missing
        }
        guard !operation.status.isActive else {
            return .active
        }
        let sql = "DELETE FROM operations WHERE id = ? AND status NOT IN ('preparing', 'uploading', 'streaming')"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(id.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        return sqlite3_changes(database) == 1 ? .deleted : .active
    }

    public func finish(
        operationID: UUID,
        as completion: OperationCompletion
    ) async throws {
        let sql = "UPDATE operations SET status = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(completion.rawValue, at: 1, to: statement)
        try Self.bind(operationID.uuidString, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteHistoryStoreError.operationNotFound
        }
    }

    public func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome
    ) async throws {
        try await finish(
            operationID: operationID,
            with: outcome,
            metrics: PersistedOperationMetrics()
        )
    }

    public func finish(
        operationID: UUID,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        let status: OperationStatus
        let sourceMarkdown: String?
        let translationMarkdown: String?
        let normalizedErrorCode: String?
        let segmentsJSON: String?
        switch outcome {
        case let .succeeded(source, translation, segments):
            status = .succeeded
            sourceMarkdown = source
            translationMarkdown = translation
            normalizedErrorCode = nil
            segmentsJSON = try Self.encodeSegments(segments)
        case let .failed(errorCode):
            status = .failed
            sourceMarkdown = nil
            translationMarkdown = nil
            normalizedErrorCode = errorCode
            segmentsJSON = nil
        }

        let sql = """
            UPDATE operations
            SET status = ?, source_markdown = ?, translation_markdown = ?,
                normalized_error_code = ?, first_text_latency_ms = ?,
                total_latency_ms = ?, input_tokens = ?, output_tokens = ?, total_tokens = ?, translation_segments = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(status.rawValue, at: 1, to: statement)
        try Self.bind(sourceMarkdown, at: 2, to: statement)
        try Self.bind(translationMarkdown, at: 3, to: statement)
        try Self.bind(normalizedErrorCode, at: 4, to: statement)
        try Self.bind(metrics.firstTextLatencyMilliseconds, at: 5, to: statement)
        try Self.bind(metrics.totalLatencyMilliseconds, at: 6, to: statement)
        try Self.bind(metrics.usage?.inputTokens, at: 7, to: statement)
        try Self.bind(metrics.usage?.outputTokens, at: 8, to: statement)
        try Self.bind(metrics.usage?.totalTokens, at: 9, to: statement)
        try Self.bind(segmentsJSON, at: 10, to: statement)
        try Self.bind(operationID.uuidString, at: 11, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteHistoryStoreError.operationNotFound
        }
    }

    public func replace(
        operationID: UUID,
        selection: ProviderSelection,
        operation: ProviderOperation,
        with outcome: PersistedOperationOutcome,
        metrics: PersistedOperationMetrics
    ) async throws {
        let kind: PersistedOperationKind
        let targetLanguage: String?
        switch operation {
        case .extractText:
            kind = .extract
            targetLanguage = nil
        case let .translate(language):
            kind = .translate
            targetLanguage = language
        }
        let status: OperationStatus
        let sourceMarkdown: String?
        let translationMarkdown: String?
        let normalizedErrorCode: String?
        let segmentsJSON: String?
        switch outcome {
        case let .succeeded(source, translation, segments):
            status = .succeeded
            sourceMarkdown = source
            translationMarkdown = translation
            normalizedErrorCode = nil
            segmentsJSON = try Self.encodeSegments(segments)
        case let .failed(errorCode):
            status = .failed
            sourceMarkdown = nil
            translationMarkdown = nil
            normalizedErrorCode = errorCode
            segmentsJSON = nil
        }
        let sql = """
            UPDATE operations
            SET provider_id = ?, model_id = ?, status = ?, source_markdown = ?,
                translation_markdown = ?, normalized_error_code = ?,
                operation_kind = ?, target_language = ?, first_text_latency_ms = ?,
                total_latency_ms = ?, input_tokens = ?, output_tokens = ?, total_tokens = ?, translation_segments = ?
            WHERE id = ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(selection.providerID, at: 1, to: statement)
        try Self.bind(selection.modelID, at: 2, to: statement)
        try Self.bind(status.rawValue, at: 3, to: statement)
        try Self.bind(sourceMarkdown, at: 4, to: statement)
        try Self.bind(translationMarkdown, at: 5, to: statement)
        try Self.bind(normalizedErrorCode, at: 6, to: statement)
        try Self.bind(kind.rawValue, at: 7, to: statement)
        try Self.bind(targetLanguage, at: 8, to: statement)
        try Self.bind(metrics.firstTextLatencyMilliseconds, at: 9, to: statement)
        try Self.bind(metrics.totalLatencyMilliseconds, at: 10, to: statement)
        try Self.bind(metrics.usage?.inputTokens, at: 11, to: statement)
        try Self.bind(metrics.usage?.outputTokens, at: 12, to: statement)
        try Self.bind(metrics.usage?.totalTokens, at: 13, to: statement)
        try Self.bind(segmentsJSON, at: 14, to: statement)
        try Self.bind(operationID.uuidString, at: 15, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteHistoryStoreError.operationNotFound
        }
    }

    public func markInFlight(
        operationID: UUID,
        as progress: OperationProgress
    ) async throws {
        let sql = "UPDATE operations SET status = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(progress.rawValue, at: 1, to: statement)
        try Self.bind(operationID.uuidString, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteHistoryStoreError.operationNotFound
        }
    }

    public func setPinned(_ isPinned: Bool, operationID: UUID) async throws {
        let sql = "UPDATE operations SET is_pinned = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        try Self.bind(isPinned ? 1 : 0, at: 1, to: statement)
        try Self.bind(operationID.uuidString, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        guard sqlite3_changes(database) == 1 else {
            throw SQLiteHistoryStoreError.operationNotFound
        }
    }

    public func recoverUnfinishedOperations() async throws -> Int {
        try Self.execute(
            """
            UPDATE operations
            SET status = 'interrupted'
            WHERE status IN ('preparing', 'uploading', 'streaming')
            """,
            on: database
        )
        return Int(sqlite3_changes(database))
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private static func schemaVersion(on database: OpaquePointer) throws -> Int {
        let sql = "SELECT value FROM metadata WHERE key = 'schema_version'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func prepareExistingDatabase(
        _ database: OpaquePointer,
        migrationDate: Date
    ) throws {
        var schemaVersion = try schemaVersion(on: database)
        guard schemaVersion <= supportedSchemaVersion else {
            throw SQLiteHistoryStoreError.schemaTooNew(
                found: schemaVersion,
                supported: supportedSchemaVersion
            )
        }
        guard try quickCheckPasses(on: database) else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        if schemaVersion == 1 {
            guard try hasRequiredOperationColumns(on: database, schemaVersion: 1) else {
                throw SQLiteHistoryStoreError.databaseFailure
            }
            try execute("BEGIN IMMEDIATE", on: database)
            do {
                try execute(
                    "ALTER TABLE operations ADD COLUMN operation_kind TEXT NOT NULL DEFAULT 'extract'",
                    on: database
                )
                try execute(
                    "ALTER TABLE operations ADD COLUMN target_language TEXT",
                    on: database
                )
                try execute(
                    "UPDATE metadata SET value = 2 WHERE key = 'schema_version'",
                    on: database
                )
                try execute("COMMIT", on: database)
                schemaVersion = 2
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        guard try hasRequiredOperationColumns(on: database, schemaVersion: schemaVersion) else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        if schemaVersion == 2 {
            try execute("BEGIN IMMEDIATE", on: database)
            do {
                try execute(
                    "ALTER TABLE operations ADD COLUMN created_at REAL NOT NULL DEFAULT \(migrationDate.timeIntervalSince1970)",
                    on: database
                )
                try execute("ALTER TABLE operations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0", on: database)
                try execute("ALTER TABLE operations ADD COLUMN first_text_latency_ms INTEGER", on: database)
                try execute("ALTER TABLE operations ADD COLUMN total_latency_ms INTEGER", on: database)
                try execute("ALTER TABLE operations ADD COLUMN input_tokens INTEGER", on: database)
                try execute("ALTER TABLE operations ADD COLUMN output_tokens INTEGER", on: database)
                try execute("ALTER TABLE operations ADD COLUMN total_tokens INTEGER", on: database)
                try execute("UPDATE metadata SET value = 3 WHERE key = 'schema_version'", on: database)
                try execute("COMMIT", on: database)
                schemaVersion = 3
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        if schemaVersion == 3 {
            try execute("BEGIN IMMEDIATE", on: database)
            do {
                try execute("ALTER TABLE operations ADD COLUMN translation_segments TEXT", on: database)
                try execute("UPDATE metadata SET value = 4 WHERE key = 'schema_version'", on: database)
                try execute("COMMIT", on: database)
                schemaVersion = 4
            } catch {
                try? execute("ROLLBACK", on: database)
                throw error
            }
        }
        guard schemaVersion == supportedSchemaVersion,
              try hasRequiredOperationColumns(on: database, schemaVersion: 4) else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private static func quickCheckPasses(on database: OpaquePointer) throws -> Bool {
        let sql = "PRAGMA quick_check"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        return text(at: 0, from: statement) == "ok"
    }

    private static func hasRequiredOperationColumns(
        on database: OpaquePointer,
        schemaVersion: Int
    ) throws -> Bool {
        var requiredColumns: Set<String> = [
            "id",
            "screenshot_path",
            "screenshot_sha256",
            "provider_id",
            "model_id",
            "status",
            "source_markdown",
            "translation_markdown",
            "normalized_error_code",
        ]
        if schemaVersion >= 2 {
            requiredColumns.formUnion(["operation_kind", "target_language"])
        }
        if schemaVersion >= 3 {
            requiredColumns.formUnion([
                "created_at", "is_pinned", "first_text_latency_ms", "total_latency_ms",
                "input_tokens", "output_tokens", "total_tokens",
            ])
        }
        if schemaVersion >= 4 { requiredColumns.insert("translation_segments") }
        let sql = "PRAGMA table_info(operations)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        defer { sqlite3_finalize(statement) }
        var foundColumns = Set<String>()
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return requiredColumns.isSubset(of: foundColumns)
            }
            guard result == SQLITE_ROW,
                  let columnName = text(at: 1, from: statement)
            else {
                throw SQLiteHistoryStoreError.databaseFailure
            }
            foundColumns.insert(columnName)
        }
    }

    private static func encodeSegments(_ value: [TranslationSegment]?) throws -> String? {
        try value.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
    }

    private static func decodeSegments(_ value: String?) throws -> [TranslationSegment]? {
        try value.map { try JSONDecoder().decode([TranslationSegment].self, from: Data($0.utf8)) }
    }

    private static func bind(
        _ text: String,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private static func bind(
        _ text: String?,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        guard let text else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw SQLiteHistoryStoreError.databaseFailure
            }
            return
        }
        try bind(text, at: index, to: statement)
    }

    private static func bind(
        _ value: Double,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private static func bind(
        _ value: Int,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
    }

    private static func bind(
        _ value: Int?,
        at index: Int32,
        to statement: OpaquePointer
    ) throws {
        guard let value else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw SQLiteHistoryStoreError.databaseFailure
            }
            return
        }
        try bind(value, at: index, to: statement)
    }

    private static func text(
        at index: Int32,
        from statement: OpaquePointer
    ) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func integer(
        at index: Int32,
        from statement: OpaquePointer
    ) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int64(statement, index))
    }
}
