import Foundation

public enum HistoryRetentionPeriod: Int, CaseIterable, Equatable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case sixtyDays = 60
    case ninetyDays = 90
    case oneHundredEightyDays = 180
}

public protocol RetentionPreferenceStoring: Sendable {
    func load() async -> HistoryRetentionPeriod
    func save(_ value: HistoryRetentionPeriod) async
}

public actor UserDefaultsRetentionPreferenceStore: RetentionPreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "historyRetentionDays"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> HistoryRetentionPeriod {
        HistoryRetentionPeriod(rawValue: defaults.integer(forKey: key)) ?? .thirtyDays
    }

    public func save(_ value: HistoryRetentionPeriod) {
        defaults.set(value.rawValue, forKey: key)
    }
}

public protocol HistoryCleanupRunning: Sendable {
    func expiredRecordCount(retention: HistoryRetentionPeriod) async throws -> Int
    func clean(retention: HistoryRetentionPeriod) async -> HistoryDeletionSummary
}

public enum RetentionChangeDisposition: Equatable, Sendable {
    case saved
    case confirmationRequired(expiredRecordCount: Int)
}

public enum RetentionSettingsError: Error, Equatable {
    case noPendingShortening
}

public actor RetentionSettingsSession {
    private let preferences: any RetentionPreferenceStoring
    private let cleanup: any HistoryCleanupRunning
    private var pendingShortening: HistoryRetentionPeriod?

    public init(
        preferences: any RetentionPreferenceStoring,
        cleanup: any HistoryCleanupRunning
    ) {
        self.preferences = preferences
        self.cleanup = cleanup
    }

    public func requestChange(
        to value: HistoryRetentionPeriod
    ) async throws -> RetentionChangeDisposition {
        let current = await preferences.load()
        guard value.rawValue < current.rawValue else {
            pendingShortening = nil
            await preferences.save(value)
            return .saved
        }
        let count = try await cleanup.expiredRecordCount(retention: value)
        pendingShortening = value
        return .confirmationRequired(expiredRecordCount: count)
    }

    public func cancelShortening() {
        pendingShortening = nil
    }

    public func confirmShortening() async throws -> HistoryDeletionSummary {
        guard let pendingShortening else {
            throw RetentionSettingsError.noPendingShortening
        }
        self.pendingShortening = nil
        await preferences.save(pendingShortening)
        return await cleanup.clean(retention: pendingShortening)
    }
}

public actor AutomaticHistoryCleanupScheduler {
    private let cleanup: any HistoryCleanupRunning
    private var didRunAtStartup = false
    private var lastRun: Date?

    public init(cleanup: any HistoryCleanupRunning) {
        self.cleanup = cleanup
    }

    public func runAtStartup(retention: HistoryRetentionPeriod, now: Date) async {
        guard !didRunAtStartup else { return }
        didRunAtStartup = true
        _ = await cleanup.clean(retention: retention)
        lastRun = now
    }

    public func runIfDue(retention: HistoryRetentionPeriod, now: Date) async {
        guard let lastRun, now.timeIntervalSince(lastRun) >= 86_400 else { return }
        _ = await cleanup.clean(retention: retention)
        self.lastRun = now
    }
}

public protocol HistoryQuerying: Sendable {
    func history(matching query: HistoryQuery) async throws -> [HistoryRecord]
}

public actor HistoryCleanupCoordinator: HistoryCleanupRunning {
    private let historyStore: any HistoryQuerying
    private let deletionCoordinator: HistoryDeletionCoordinator
    private let now: @Sendable () -> Date

    public init(
        historyStore: any HistoryQuerying,
        deletionCoordinator: HistoryDeletionCoordinator,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.historyStore = historyStore
        self.deletionCoordinator = deletionCoordinator
        self.now = now
    }

    public func expiredRecordCount(retention: HistoryRetentionPeriod) async throws -> Int {
        try await expiredRecords(retention: retention).count
    }

    public func clean(retention: HistoryRetentionPeriod) async -> HistoryDeletionSummary {
        do {
            let records = try await expiredRecords(retention: retention)
            return await deletionCoordinator.delete(
                recordIDs: records.map(\.id),
                includePinned: false
            )
        } catch {
            return HistoryDeletionSummary(deleted: 0, failed: 1, skipped: 0)
        }
    }

    private func expiredRecords(
        retention: HistoryRetentionPeriod
    ) async throws -> [HistoryRecord] {
        let cutoff = now().addingTimeInterval(-Double(retention.rawValue) * 86_400)
        return try await historyStore.history(
            matching: HistoryQuery(createdBefore: cutoff, isPinned: false)
        ).filter { !$0.operation.status.isActive }
    }
}

extension SQLiteHistoryStore: HistoryQuerying {}
