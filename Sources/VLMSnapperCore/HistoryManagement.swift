import Foundation

public enum HistoryOperationKindFilter: Equatable, Sendable {
    case all
    case extract
    case translate
}

public struct HistoryQuery: Equatable, Sendable {
    public let kind: HistoryOperationKindFilter
    public let status: OperationStatus?
    public let providerID: String?
    public let modelID: String?
    public let targetLanguage: String?
    public let createdAtOrAfter: Date?
    public let createdBefore: Date?
    public let isPinned: Bool?
    public let searchText: String

    public init(
        kind: HistoryOperationKindFilter = .all,
        status: OperationStatus? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        targetLanguage: String? = nil,
        createdAtOrAfter: Date? = nil,
        createdBefore: Date? = nil,
        isPinned: Bool? = nil,
        searchText: String = ""
    ) {
        self.kind = kind
        self.status = status
        self.providerID = providerID
        self.modelID = modelID
        self.targetLanguage = targetLanguage
        self.createdAtOrAfter = createdAtOrAfter
        self.createdBefore = createdBefore
        self.isPinned = isPinned
        self.searchText = searchText
    }
}

public struct PersistedOperationMetrics: Equatable, Sendable {
    public let firstTextLatencyMilliseconds: Int?
    public let totalLatencyMilliseconds: Int?
    public let usage: ProviderTokenUsage?

    public init(
        firstTextLatencyMilliseconds: Int? = nil,
        totalLatencyMilliseconds: Int? = nil,
        usage: ProviderTokenUsage? = nil
    ) {
        self.firstTextLatencyMilliseconds = firstTextLatencyMilliseconds
        self.totalLatencyMilliseconds = totalLatencyMilliseconds
        self.usage = usage
    }
}

public struct HistoryRecord: Equatable, Sendable, Identifiable {
    public let operation: StoredOperation
    public let createdAt: Date
    public let isPinned: Bool
    public let metrics: PersistedOperationMetrics

    public var id: UUID { operation.id }

    public init(
        operation: StoredOperation,
        createdAt: Date,
        isPinned: Bool,
        metrics: PersistedOperationMetrics = PersistedOperationMetrics()
    ) {
        self.operation = operation
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.metrics = metrics
    }
}

public extension OperationStatus {
    var isActive: Bool {
        switch self {
        case .preparing, .uploading, .streaming:
            true
        case .succeeded, .failed, .canceled, .interrupted, .resultPersistenceFailed:
            false
        }
    }
}

public enum HistoryRecordDeletionResult: Equatable, Sendable {
    case deleted
    case active
    case missing
}

public protocol HistoryRecordManaging: Sendable {
    func historyRecord(id: UUID) async throws -> HistoryRecord?
    func deleteHistoryRecord(id: UUID) async throws -> HistoryRecordDeletionResult
}

public struct HistoryDeletionSummary: Equatable, Sendable {
    public let deleted: Int
    public let failed: Int
    public let skipped: Int

    public init(deleted: Int, failed: Int, skipped: Int) {
        self.deleted = deleted
        self.failed = failed
        self.skipped = skipped
    }
}

public actor HistoryDeletionCoordinator {
    private let historyStore: any HistoryRecordManaging
    private let screenshotStore: any ScreenshotPersisting

    public init(
        historyStore: any HistoryRecordManaging,
        screenshotStore: any ScreenshotPersisting
    ) {
        self.historyStore = historyStore
        self.screenshotStore = screenshotStore
    }

    public func delete(
        recordIDs: [UUID],
        includePinned: Bool
    ) async -> HistoryDeletionSummary {
        var deleted = 0
        var failed = 0
        var skipped = 0
        for id in recordIDs {
            do {
                guard let record = try await historyStore.historyRecord(id: id) else {
                    deleted += 1
                    continue
                }
                guard !record.operation.status.isActive,
                      includePinned || !record.isPinned else {
                    skipped += 1
                    continue
                }
                do {
                    try await screenshotStore.discardIfOwned(record.operation.screenshot)
                } catch ScreenshotStoreError.missingFile {
                    // The original file is already unavailable; only internal history is removed.
                } catch ScreenshotStoreError.ownershipMismatch {
                    // A replacement at the same path is user data and must remain untouched.
                } catch {
                    failed += 1
                    continue
                }
                switch try await historyStore.deleteHistoryRecord(id: id) {
                case .deleted, .missing:
                    deleted += 1
                case .active:
                    skipped += 1
                }
            } catch {
                failed += 1
            }
        }
        return HistoryDeletionSummary(deleted: deleted, failed: failed, skipped: skipped)
    }
}
