import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Diagnostic log")
struct DiagnosticLogStoreTests {
    @Test("Event encoding omits rejected dynamic identifiers")
    func eventEncodingUsesAllowlist() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLMSnapper-Diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_787_745_600)
        let store = DiagnosticLogStore(directory: root, now: { now })

        try await store.record(
            DiagnosticEvent(
                timestamp: now,
                providerID: .deepSeek,
                modelID: "deepseek-v4-flash-vision-exp",
                stage: .response,
                durationMilliseconds: 842,
                httpStatus: 429,
                providerErrorCode: "rate_limit",
                requestID: "unsafe request id with spaces",
                normalizedErrorCode: "rate_limited"
            )
        )

        let file = try #require(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let line = try String(contentsOf: file, encoding: .utf8)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        #expect(object["provider"] as? String == "deepseek")
        #expect(object["model"] as? String == "deepseek-v4-flash-vision-exp")
        #expect(object["providerErrorCode"] as? String == "rate_limit")
        #expect(object["requestID"] == nil)
        #expect(object["message"] == nil)
    }

    @Test("Cleanup removes only expired managed files")
    func cleanupIsOwnershipScoped() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLMSnapper-Diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("diagnostic-2026-08-10.jsonl")
        let cutoffDay = root.appendingPathComponent("diagnostic-2026-08-20.jsonl")
        let current = root.appendingPathComponent("diagnostic-2026-08-26.jsonl")
        let unrelated = root.appendingPathComponent("notes.jsonl")
        try Data("old".utf8).write(to: old)
        try Data("cutoff".utf8).write(to: cutoffDay)
        try Data("current".utf8).write(to: current)
        try Data("keep".utf8).write(to: unrelated)
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-08-27T12:00:00Z")
        )
        let store = DiagnosticLogStore(directory: root, now: { now })

        let removed = try await store.removeExpiredLogs()

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: cutoffDay.path))
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test("Export passes retained JSONL through a compressor")
    func exportUsesCompressor() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLMSnapper-Diagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_787_745_600)
        let compressor = DiagnosticCompressorProbe()
        let store = DiagnosticLogStore(directory: root, now: { now })
        try await store.record(DiagnosticEvent(timestamp: now, stage: .startup))
        let output = root.appendingPathComponent("export.jsonl.gz")

        try await store.export(to: output, compressor: compressor)

        #expect(await compressor.inputs.count == 1)
        #expect(try Data(contentsOf: output).starts(with: Data("compressed:".utf8)))
    }

    @Test("Gzip compressor emits a gzip stream")
    func gzipCompressorEmitsGzip() async throws {
        let compressed = try await GzipDiagnosticCompressor().compress(Data("hello\n".utf8))

        #expect(compressed.starts(with: Data([0x1f, 0x8b])))
        #expect(compressed.count > 10)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VLMSnapper-Gzip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("diagnostics.jsonl.gz")
        try compressed.write(to: archive)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", archive.path]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(output.fileHandleForReading.readDataToEndOfFile() == Data("hello\n".utf8))
    }
}

private actor DiagnosticCompressorProbe: DiagnosticCompressing {
    private(set) var inputs: [Data] = []

    func compress(_ data: Data) async throws -> Data {
        inputs.append(data)
        return Data("compressed:".utf8) + data
    }
}
