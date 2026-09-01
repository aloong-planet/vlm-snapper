import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Managed screenshot root")
struct ManagedScreenshotRootTests {
    @Test("a sandbox Pictures proxy resolves to a direct user Pictures path")
    func sandboxPicturesProxyResolvesToDirectUserPicturesPath() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let containerData = base.appendingPathComponent("Container/Data", isDirectory: true)
        let userPictures = base.appendingPathComponent("Pictures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: containerData,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: userPictures,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let sandboxPicturesProxy = containerData.appendingPathComponent(
            "Pictures",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: sandboxPicturesProxy,
            withDestinationURL: userPictures
        )

        let root = ManagedScreenshotRoot.directURL(
            for: sandboxPicturesProxy
        )
        let store = FileSystemScreenshotStore(rootDirectory: root)
        let managed = try await store.save(
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47])
        )

        let expectedRoot = userPictures.appendingPathComponent(
            "VLMSnapper",
            isDirectory: true
        )
        #expect(root == expectedRoot.standardizedFileURL)
        #expect(managed.path.hasPrefix(expectedRoot.path + "/"))
        #expect(!managed.path.hasPrefix(containerData.path + "/"))
    }
}
