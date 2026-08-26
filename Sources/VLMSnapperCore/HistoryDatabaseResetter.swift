import Foundation

public struct HistoryDatabaseResetter: Sendable {
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    public func reset(databaseAt databaseURL: URL) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw SQLiteHistoryStoreError.databaseFailure
        }
        let recoveryURL = availableRecoveryURL(for: databaseURL, fileManager: fileManager)
        let suffixes = ["", "-wal", "-shm"]
        var movedFiles: [(source: URL, destination: URL)] = []

        do {
            for suffix in suffixes {
                let source = URL(fileURLWithPath: databaseURL.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else {
                    continue
                }
                let destination = URL(fileURLWithPath: recoveryURL.path + suffix)
                try fileManager.moveItem(at: source, to: destination)
                movedFiles.append((source, destination))
            }
            let store = try SQLiteHistoryStore(databaseURL: databaseURL)
            _ = store
            return recoveryURL
        } catch {
            for suffix in suffixes {
                let createdFile = URL(fileURLWithPath: databaseURL.path + suffix)
                try? fileManager.removeItem(at: createdFile)
            }
            for movedFile in movedFiles.reversed() {
                try? fileManager.moveItem(
                    at: movedFile.destination,
                    to: movedFile.source
                )
            }
            throw error
        }
    }

    private func availableRecoveryURL(
        for databaseURL: URL,
        fileManager: FileManager
    ) -> URL {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now()
        )
        let timestamp = String(
            format: "%04d%02d%02d-%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        let directory = databaseURL.deletingLastPathComponent()
        let stem = databaseURL.deletingPathExtension().lastPathComponent
        let pathExtension = databaseURL.pathExtension
        var sequence = 1

        while true {
            let suffix = sequence == 1 ? "" : "-\(sequence)"
            let filename = "\(stem)-recovery-\(timestamp)\(suffix)"
            let candidate = directory
                .appendingPathComponent(filename)
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            sequence += 1
        }
    }
}
