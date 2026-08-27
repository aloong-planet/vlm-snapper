import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("File provider metadata store")
struct FileProviderMetadataStoreTests {
    @Test("provider metadata survives reopening without storing an API key")
    func metadataSurvivesReopeningWithoutAPIKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let state = ProviderMetadataState(
            configurations: [
                .deepSeek: ProviderConfiguration(
                    models: [
                        ProviderModelState(id: "deepseek-v4-flash-vision-exp"),
                    ],
                    fetchedAt: Date(timeIntervalSince1970: 1_787_731_200),
                    selectedModelID: "deepseek-v4-flash-vision-exp"
                ),
            ],
            currentProvider: .deepSeek
        )

        let store = FileProviderMetadataStore(fileURL: fileURL)
        try await store.save(state)

        let reopened = FileProviderMetadataStore(fileURL: fileURL)
        #expect(try await reopened.load() == state)
        let persistedText = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!persistedText.localizedCaseInsensitiveContains("apiKey"))
        #expect(!persistedText.localizedCaseInsensitiveContains("secret"))
    }

    @Test("a symbolic link in the metadata directory ancestry is rejected")
    func symbolicLinkAncestorIsRejected() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = container.appendingPathComponent("target", isDirectory: true)
        let alias = container.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: target,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: container) }
        let fileURL = alias
            .appendingPathComponent("VLMSnapper", isDirectory: true)
            .appendingPathComponent("providers.json")
        let store = FileProviderMetadataStore(fileURL: fileURL)

        do {
            try await store.save(ProviderMetadataState())
            Issue.record("Expected the symbolic-link ancestor to be rejected")
        } catch {
            #expect(error as? FileProviderMetadataStoreError == .unsafePath)
        }
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("VLMSnapper").path))
    }

    @Test("invalid metadata is reported without overwriting its bytes")
    func invalidMetadataIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("providers.json")
        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: fileURL)
        let store = FileProviderMetadataStore(fileURL: fileURL)

        do {
            _ = try await store.load()
            Issue.record("Expected invalid metadata to be rejected")
        } catch {
            #expect(error as? FileProviderMetadataStoreError == .invalidData)
        }
        #expect(try Data(contentsOf: fileURL) == invalidData)
    }
}
