import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("History deletion coordinator")
struct HistoryDeletionCoordinatorTests {
    @Test("a batch continues after file failure and skips active and pinned records")
    func batchContinuesAndReportsEveryDisposition() async {
        let failed = makeRecord(id: UUID(), status: .failed)
        let deleted = makeRecord(id: UUID(), status: .succeeded)
        let active = makeRecord(id: UUID(), status: .streaming)
        let pinned = makeRecord(id: UUID(), status: .succeeded, isPinned: true)
        let store = DeletionHistoryProbe(records: [failed, deleted, active, pinned])
        let screenshots = DeletionScreenshotProbe(failingPaths: [failed.operation.screenshot.path])
        let coordinator = HistoryDeletionCoordinator(
            historyStore: store,
            screenshotStore: screenshots
        )

        let summary = await coordinator.delete(
            recordIDs: [failed.id, deleted.id, active.id, pinned.id],
            includePinned: false
        )

        #expect(summary == HistoryDeletionSummary(deleted: 1, failed: 1, skipped: 2))
        #expect(await store.remainingIDs == Set([failed.id, active.id, pinned.id]))
        #expect(await screenshots.attemptedPaths == [
            failed.operation.screenshot.path,
            deleted.operation.screenshot.path,
        ])
    }

    @Test("missing or replaced screenshots never block internal history deletion")
    func unavailableScreenshotsOnlyDeleteInternalRecords() async {
        let missing = makeRecord(id: UUID(), status: .failed)
        let replaced = makeRecord(id: UUID(), status: .succeeded)
        let store = DeletionHistoryProbe(records: [missing, replaced])
        let screenshots = DeletionScreenshotProbe(
            errors: [
                missing.operation.screenshot.path: ScreenshotStoreError.missingFile,
                replaced.operation.screenshot.path: ScreenshotStoreError.ownershipMismatch,
            ]
        )
        let coordinator = HistoryDeletionCoordinator(
            historyStore: store,
            screenshotStore: screenshots
        )

        let summary = await coordinator.delete(
            recordIDs: [missing.id, replaced.id],
            includePinned: false
        )

        #expect(summary == HistoryDeletionSummary(deleted: 2, failed: 0, skipped: 0))
        #expect(await store.remainingIDs.isEmpty)
    }

    private func makeRecord(
        id: UUID,
        status: OperationStatus,
        isPinned: Bool = false
    ) -> HistoryRecord {
        HistoryRecord(
            operation: StoredOperation(
                id: id,
                screenshot: ManagedScreenshot(path: "/Pictures/\(id).png", sha256: "sha"),
                selection: ProviderSelection(providerID: "openai", modelID: "vision"),
                status: status
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            isPinned: isPinned
        )
    }
}

private actor DeletionHistoryProbe: HistoryRecordManaging {
    private var records: [UUID: HistoryRecord]

    init(records: [HistoryRecord]) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    var remainingIDs: Set<UUID> { Set(records.keys) }

    func historyRecord(id: UUID) async throws -> HistoryRecord? { records[id] }

    func deleteHistoryRecord(id: UUID) async throws -> HistoryRecordDeletionResult {
        guard let record = records[id] else { return .missing }
        if record.operation.status.isActive { return .active }
        records[id] = nil
        return .deleted
    }
}

private actor DeletionScreenshotProbe: ScreenshotPersisting {
    private let errors: [String: ScreenshotStoreError]
    private(set) var attemptedPaths = [String]()

    init(
        failingPaths: Set<String> = [],
        errors: [String: ScreenshotStoreError] = [:]
    ) {
        var combined = errors
        for path in failingPaths {
            combined[path] = .unsafePath
        }
        self.errors = combined
    }

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        throw ScreenshotStoreError.unsafePath
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        attemptedPaths.append(screenshot.path)
        if let error = errors[screenshot.path] { throw error }
    }
}
