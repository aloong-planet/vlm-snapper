import Foundation
import Testing

@Suite("Release appcast script")
struct ReleaseAppcastScriptTests {
    @Test("Generated appcast stays inside the architecture staging directory")
    func generatedAppcastUsesStagingDirectory() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "vlmsnapper-release-appcast-tests-" + UUID().uuidString
            )
        let invocationDirectory = temporaryRoot.appendingPathComponent("invocation")
        let appcastDirectory = temporaryRoot.appendingPathComponent("appcasts/arm64")
        try fileManager.createDirectory(
            at: invocationDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: appcastDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let fakeTool = temporaryRoot.appendingPathComponent("generate_appcast")
        try """
        #!/bin/bash
        set -euo pipefail
        output=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o)
                    output="$2"
                    shift 2
                    ;;
                *)
                    shift
                    ;;
            esac
        done
        printf '<rss />' > "$output"
        """.write(to: fakeTool, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeTool.path
        )

        let script = repositoryRoot
            .appendingPathComponent("Scripts/generate-release-appcast.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            fakeTool.path,
            temporaryRoot.appendingPathComponent("private-key").path,
            "https://downloads.example/releases/1.0.0",
            "arm64",
            appcastDirectory.path,
        ]
        process.currentDirectoryURL = invocationDirectory
        try process.run()
        process.waitUntilExit()

        let expectedAppcast = appcastDirectory.appendingPathComponent("appcast-arm64.xml")
        let leakedAppcast = invocationDirectory.appendingPathComponent("appcast-arm64.xml")
        #expect(process.terminationStatus == 0)
        #expect(fileManager.fileExists(atPath: expectedAppcast.path))
        #expect(!fileManager.fileExists(atPath: leakedAppcast.path))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
