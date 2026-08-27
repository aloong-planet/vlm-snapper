import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("History retention")
struct HistoryRetentionTests {
    @Test("shortening requires confirmation while extending saves without cleanup")
    func shorteningRequiresConfirmation() async throws {
        let preferences = RetentionPreferenceProbe(value: .thirtyDays)
        let cleanup = RetentionCleanupProbe(expiredCount: 4)
        let session = RetentionSettingsSession(preferences: preferences, cleanup: cleanup)

        let shorter = try await session.requestChange(to: .sevenDays)
        #expect(shorter == .confirmationRequired(expiredRecordCount: 4))
        #expect(await preferences.value == .thirtyDays)
        #expect(await cleanup.cleanCalls.isEmpty)

        let summary = try await session.confirmShortening()
        #expect(summary == HistoryDeletionSummary(deleted: 4, failed: 0, skipped: 0))
        #expect(await preferences.value == .sevenDays)
        #expect(await cleanup.cleanCalls == [.sevenDays])

        let longer = try await session.requestChange(to: .ninetyDays)
        #expect(longer == .saved)
        #expect(await preferences.value == .ninetyDays)
        #expect(await cleanup.cleanCalls == [.sevenDays])
    }

    @Test("automatic cleanup runs once at startup and at most every twenty four hours")
    func automaticCleanupUsesTwentyFourHourGate() async {
        let cleanup = RetentionCleanupProbe(expiredCount: 0)
        let scheduler = AutomaticHistoryCleanupScheduler(cleanup: cleanup)
        let start = Date(timeIntervalSince1970: 1_000)

        await scheduler.runAtStartup(retention: .thirtyDays, now: start)
        await scheduler.runAtStartup(retention: .thirtyDays, now: start.addingTimeInterval(10))
        await scheduler.runIfDue(retention: .thirtyDays, now: start.addingTimeInterval(86_399))
        await scheduler.runIfDue(retention: .thirtyDays, now: start.addingTimeInterval(86_400))

        #expect(await cleanup.cleanCalls == [.thirtyDays, .thirtyDays])
    }
}

private actor RetentionPreferenceProbe: RetentionPreferenceStoring {
    var value: HistoryRetentionPeriod

    init(value: HistoryRetentionPeriod) { self.value = value }

    func load() -> HistoryRetentionPeriod { value }
    func save(_ value: HistoryRetentionPeriod) { self.value = value }
}

private actor RetentionCleanupProbe: HistoryCleanupRunning {
    let expiredCount: Int
    private(set) var cleanCalls = [HistoryRetentionPeriod]()

    init(expiredCount: Int) { self.expiredCount = expiredCount }

    func expiredRecordCount(retention: HistoryRetentionPeriod) async throws -> Int {
        expiredCount
    }

    func clean(retention: HistoryRetentionPeriod) async -> HistoryDeletionSummary {
        cleanCalls.append(retention)
        return HistoryDeletionSummary(deleted: expiredCount, failed: 0, skipped: 0)
    }
}
