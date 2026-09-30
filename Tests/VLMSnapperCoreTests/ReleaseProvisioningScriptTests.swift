import Foundation
import Testing

@Suite("Release provisioning script")
struct ReleaseProvisioningScriptTests {
    @Test("a formal release requires an external provisioning profile")
    func formalReleaseRequiresProvisioningProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-release-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRoot.appendingPathComponent("Scripts/release-macos.sh").path,
            "1.0.0",
            "https://updates.aloongplanet.com/vlmsnapper",
            "https://downloads.aloongplanet.com/vlmsnapper",
            "public-key",
            root.appendingPathComponent("output").path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["MACOS_SIGNING_IDENTITY"] = "Developer ID Application: Test"
        environment["MACOS_NOTARY_PROFILE"] = "test-notary"
        environment["SPARKLE_PRIVATE_KEY_FILE"] = root
            .appendingPathComponent("sparkle-private-key").path
        environment["MACOS_PROVISIONING_PROFILE"] = nil
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors

        try process.run()
        process.waitUntilExit()
        let errorText = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )

        #expect(process.terminationStatus == 78)
        #expect(
            errorText?.contains(
                "Missing required release configuration: MACOS_PROVISIONING_PROFILE"
            ) == true
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
