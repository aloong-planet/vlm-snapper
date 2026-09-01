import Foundation
import Testing
@testable import VLMSnapperReleaseSupport

@Suite("Developer ID profile preparation")
struct DeveloperIDProfilePreparationTests {
    @Test("preparation refuses to replace an existing signing output")
    func existingOutputIsRejectedBeforeKeychainAccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-profile-preparation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("entitlements.plist")
        try Data("existing".utf8).write(to: output)

        #expect(
            throws: DeveloperIDProfilePreparationError
                .outputAlreadyExists(output.path)
        ) {
            try DeveloperIDProfilePreparation().prepare(
                profileURL: root.appendingPathComponent("missing.provisionprofile"),
                bundleIdentifier: "com.loong.vlmsnapper",
                signingIdentity: "missing identity",
                baseEntitlementsURL: root.appendingPathComponent("base.plist"),
                outputEntitlementsURL: output,
                outputMetadataURL: root.appendingPathComponent("metadata.plist")
            )
        }
    }
}
