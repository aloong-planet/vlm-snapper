import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("File system screenshot store")
struct FileSystemScreenshotStoreTests {
    @Test("a newly created root supports load and discard regardless of its URL directory hint", arguments: [false, true])
    func newRootRoundTrip(directoryHint: Bool) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileSystemScreenshotStore(rootDirectory:
            base.appendingPathComponent("Pictures", isDirectory: directoryHint))
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        let saved = try await store.save(originalPNG: png)
        #expect(try await store.loadIfOwned(saved) == png)
        try await store.discardIfOwned(saved)
        #expect(!FileManager.default.fileExists(atPath: saved.path))
    }

    @Test("saving an original PNG preserves its bytes, local timestamp name, and SHA-256")
    func savingOriginalPNGPreservesBytesNameAndDigest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let png = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let store = FileSystemScreenshotStore(
            rootDirectory: root,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_787_725_812) }
        )

        let managed = try await store.save(originalPNG: png)

        let expectedURL = root
            .appendingPathComponent("2026-08", isDirectory: true)
            .appendingPathComponent("vlmsnapper-20260826-143012.png")
        #expect(managed.path == expectedURL.path)
        #expect(managed.sha256 == "431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460")
        #expect(try Data(contentsOf: expectedURL) == png)
    }

    @Test("screenshots created in the same second use a suffix without overwriting")
    func sameSecondScreenshotsUseSuffixWithoutOverwriting() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let firstPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        let secondPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x02])
        let store = FileSystemScreenshotStore(
            rootDirectory: root,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_787_725_812) }
        )

        let first = try await store.save(originalPNG: firstPNG)
        let second = try await store.save(originalPNG: secondPNG)

        let month = root.appendingPathComponent("2026-08", isDirectory: true)
        #expect(first.path == month.appendingPathComponent("vlmsnapper-20260826-143012.png").path)
        #expect(second.path == month.appendingPathComponent("vlmsnapper-20260826-143012-2.png").path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: first.path)) == firstPNG)
        #expect(try Data(contentsOf: URL(fileURLWithPath: second.path)) == secondPNG)
    }

    @Test("a symbolic-link screenshot root is rejected without writing through it")
    func symbolicLinkRootIsRejected() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: external)
        }
        let root = base.appendingPathComponent("VLMSnapper", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: root,
            withDestinationURL: external
        )
        let store = FileSystemScreenshotStore(rootDirectory: root)

        do {
            _ = try await store.save(originalPNG: Data([0x89, 0x50, 0x4E, 0x47]))
            Issue.record("Expected a symbolic-link root to be rejected")
        } catch {
            #expect(error as? ScreenshotStoreError == .unsafePath)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    @Test("a symbolic link in the screenshot root ancestry is rejected")
    func symbolicLinkAncestorIsRejected() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: external)
        }
        let linkedParent = base.appendingPathComponent("Pictures", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: external
        )
        let root = linkedParent.appendingPathComponent("VLMSnapper", isDirectory: true)
        let store = FileSystemScreenshotStore(rootDirectory: root)

        do {
            _ = try await store.save(originalPNG: Data([0x89, 0x50, 0x4E, 0x47]))
            Issue.record("Expected a symbolic-link ancestor to be rejected")
        } catch {
            #expect(error as? ScreenshotStoreError == .unsafePath)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    @Test("a symbolic-link month directory is rejected")
    func symbolicLinkMonthDirectoryIsRejected() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("VLMSnapper", isDirectory: true)
        let external = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("2026-08", isDirectory: true),
            withDestinationURL: external
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let store = FileSystemScreenshotStore(
            rootDirectory: root,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_787_725_812) }
        )

        do {
            _ = try await store.save(originalPNG: Data([0x89, 0x50, 0x4E, 0x47]))
            Issue.record("Expected a symbolic-link month directory to be rejected")
        } catch {
            #expect(error as? ScreenshotStoreError == .unsafePath)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    @Test("a managed path replaced by a symbolic link is neither loaded nor deleted")
    func symbolicLinkScreenshotIsNeitherLoadedNorDeleted() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("VLMSnapper", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0xAA])
        let managed = try await store.save(originalPNG: png)
        let managedURL = URL(fileURLWithPath: managed.path)
        let externalURL = base.appendingPathComponent("external.png")
        try FileManager.default.moveItem(at: managedURL, to: externalURL)
        try FileManager.default.createSymbolicLink(
            at: managedURL,
            withDestinationURL: externalURL
        )

        do {
            _ = try await store.loadIfOwned(managed)
            Issue.record("Expected a symbolic-link screenshot to be rejected")
        } catch {
            #expect(error as? ScreenshotStoreError == .ownershipMismatch)
        }
        do {
            try await store.discardIfOwned(managed)
            Issue.record("Expected a symbolic-link screenshot to be preserved")
        } catch {
            #expect(error as? ScreenshotStoreError == .ownershipMismatch)
        }
        #expect(try Data(contentsOf: externalURL) == png)
        #expect(FileManager.default.fileExists(atPath: managedURL.path))
    }

    @Test("discarding a matching managed screenshot removes its PNG")
    func discardingMatchingManagedScreenshotRemovesPNG() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let managed = try await store.save(
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x06])
        )

        try await store.discardIfOwned(managed)

        #expect(!FileManager.default.fileExists(atPath: managed.path))
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: managed.path).deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }

    @Test("loading a matching managed screenshot returns its original PNG")
    func loadingMatchingManagedScreenshotReturnsOriginalPNG() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x07])
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let managed = try await store.save(originalPNG: png)

        let loaded = try await store.loadIfOwned(managed)

        #expect(loaded == png)
    }

    @Test("loading a deleted managed screenshot reports a missing file")
    func loadingDeletedManagedScreenshotReportsMissingFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let managed = try await store.save(
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x08])
        )
        try FileManager.default.removeItem(atPath: managed.path)

        do {
            _ = try await store.loadIfOwned(managed)
            Issue.record("Expected the deleted PNG to be reported as missing")
        } catch {
            #expect(error as? ScreenshotStoreError == .missingFile)
        }

        #expect(!FileManager.default.fileExists(atPath: managed.path))
    }

    @Test("a replaced screenshot is neither returned nor deleted")
    func replacedScreenshotIsNeitherReturnedNorDeleted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("VLMSnapper", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let managed = try await store.save(
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x09])
        )
        let replacement = Data([0x89, 0x50, 0x4E, 0x47, 0xFF])
        let file = URL(fileURLWithPath: managed.path)
        try replacement.write(to: file, options: .atomic)

        do {
            _ = try await store.loadIfOwned(managed)
            Issue.record("Expected replacement data to be rejected")
        } catch {
            #expect(error as? ScreenshotStoreError == .ownershipMismatch)
        }
        do {
            try await store.discardIfOwned(managed)
            Issue.record("Expected replacement data to be preserved")
        } catch {
            #expect(error as? ScreenshotStoreError == .ownershipMismatch)
        }

        #expect(try Data(contentsOf: file) == replacement)
    }
}
