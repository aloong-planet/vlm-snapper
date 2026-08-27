import Foundation
import VLMSnapperProcessShim

public enum DiagnosticRequestStage: String, Codable, Sendable {
    case startup
    case request
    case response
    case persistence
    case cleanup
    case update
}

public struct DiagnosticEvent: Sendable {
    public let timestamp: Date
    public let providerID: ProviderID?
    public let modelID: String?
    public let stage: DiagnosticRequestStage
    public let durationMilliseconds: Int?
    public let httpStatus: Int?
    public let providerErrorCode: String?
    public let requestID: String?
    public let normalizedErrorCode: String?

    public init(
        timestamp: Date,
        providerID: ProviderID? = nil,
        modelID: String? = nil,
        stage: DiagnosticRequestStage,
        durationMilliseconds: Int? = nil,
        httpStatus: Int? = nil,
        providerErrorCode: String? = nil,
        requestID: String? = nil,
        normalizedErrorCode: String? = nil
    ) {
        self.timestamp = timestamp
        self.providerID = providerID
        self.modelID = modelID
        self.stage = stage
        self.durationMilliseconds = durationMilliseconds
        self.httpStatus = httpStatus
        self.providerErrorCode = providerErrorCode
        self.requestID = requestID
        self.normalizedErrorCode = normalizedErrorCode
    }
}

public protocol DiagnosticCompressing: Sendable {
    func compress(_ data: Data) async throws -> Data
}

public enum DiagnosticCompressionError: Error, Equatable {
    case gzip(Int32)
}

public struct GzipDiagnosticCompressor: DiagnosticCompressing {
    public init() {}

    public func compress(_ data: Data) async throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        var errorCode: Int32 = 0
        let succeeded = data.withUnsafeBytes { bytes in
            VLMSnapperGzipCompress(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count,
                &output,
                &outputLength,
                &errorCode
            )
        }
        guard succeeded, let output else {
            throw DiagnosticCompressionError.gzip(errorCode)
        }
        defer { VLMSnapperFreeBuffer(output) }
        return Data(bytes: output, count: outputLength)
    }
}

public actor DiagnosticLogStore {
    private static let retentionSeconds: TimeInterval = 7 * 24 * 60 * 60
    private let directory: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder

    public init(
        directory: URL,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.now = now
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func record(_ event: DiagnosticEvent) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoded = try encoder.encode(SanitizedDiagnosticEvent(event))
        var line = encoded
        line.append(0x0A)
        let fileURL = directory.appendingPathComponent(fileName(for: event.timestamp))
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func removeExpiredLogs() throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let cutoff = Self.utcCalendar.startOfDay(
            for: now().addingTimeInterval(-Self.retentionSeconds)
        )
        var removed = 0
        for fileURL in try managedFiles() {
            guard let date = date(from: fileURL.lastPathComponent), date < cutoff else {
                continue
            }
            try FileManager.default.removeItem(at: fileURL)
            removed += 1
        }
        return removed
    }

    public func export(
        to outputURL: URL,
        compressor: any DiagnosticCompressing = GzipDiagnosticCompressor()
    ) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        _ = try removeExpiredLogs()
        var combined = Data()
        for fileURL in try managedFiles().sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            combined.append(try Data(contentsOf: fileURL))
        }
        let compressed = try await compressor.compress(combined)
        try compressed.write(to: outputURL, options: .atomic)
    }

    private func managedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { date(from: $0.lastPathComponent) != nil }
    }

    private func fileName(for date: Date) -> String {
        "diagnostic-\(Self.dayFormatter.string(from: date)).jsonl"
    }

    private func date(from fileName: String) -> Date? {
        guard fileName.hasPrefix("diagnostic-"), fileName.hasSuffix(".jsonl") else {
            return nil
        }
        let start = fileName.index(fileName.startIndex, offsetBy: 11)
        let end = fileName.index(fileName.endIndex, offsetBy: -6)
        guard start < end else { return nil }
        return Self.dayFormatter.date(from: String(fileName[start..<end]))
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct SanitizedDiagnosticEvent: Encodable {
    let timestamp: Date
    let provider: String?
    let model: String?
    let stage: String
    let durationMilliseconds: Int?
    let httpStatus: Int?
    let providerErrorCode: String?
    let requestID: String?
    let normalizedErrorCode: String?

    init(_ event: DiagnosticEvent) {
        timestamp = event.timestamp
        provider = event.providerID?.rawValue
        model = Self.sanitize(event.modelID)
        stage = event.stage.rawValue
        durationMilliseconds = event.durationMilliseconds
        httpStatus = event.httpStatus
        providerErrorCode = Self.sanitize(event.providerErrorCode)
        requestID = Self.sanitize(event.requestID)
        normalizedErrorCode = Self.sanitize(event.normalizedErrorCode)
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value, (1...128).contains(value.utf8.count) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:/-"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
}
