import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Release manifest")
struct ReleaseManifestTests {
    @Test("Noncanonical versions cannot be released", arguments: [
        "", "51", "1.2", "1.2.3.4", "01.2.3", "1.2.3-ci", "1.2.3\n",
    ])
    func invalidVersionIsRejected(version: String) throws {
        let valid = validManifest()
        let manifest = ReleaseManifest(
            version: version,
            bundleIdentifier: valid.bundleIdentifier,
            sparklePublicKey: valid.sparklePublicKey,
            artifacts: valid.artifacts
        )
        #expect(throws: ReleaseManifestError.invalidVersion) {
            try manifest.validateForFormalRelease()
        }
    }

    @Test("A legacy manifest with an independent build number cannot be released")
    func independentBuildNumberIsRejected() throws {
        let data = try JSONEncoder().encode(validManifest())
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["buildVersion"] = "51"
        let decoded = try JSONDecoder().decode(
            ReleaseManifest.self,
            from: JSONSerialization.data(withJSONObject: fields)
        )

        #expect(throws: ReleaseManifestError.mismatchedBuildVersion) {
            try decoded.validateForFormalRelease()
        }
    }

    @Test("A complete three-architecture release manifest is accepted")
    func completeManifestIsAccepted() throws {
        let manifest = ReleaseManifest(
            version: "1.0.0",
            bundleIdentifier: "com.loong.vlmsnapper",
            sparklePublicKey: Data(repeating: 7, count: 32).base64EncodedString(),
            artifacts: DistributionArchitecture.allCases.map { architecture in
                DistributionArtifact(
                    architecture: architecture,
                    feedURL: URL(
                        string: "https://downloads.aloongplanet.com/vlmsnapper/appcast-\(architecture.rawValue).xml"
                    )!,
                    dmgFileName: "VLMSnapper-1.0.0-mac-\(architecture.rawValue).dmg"
                )
            }
        )

        try manifest.validateForFormalRelease()
        #expect(manifest.buildVersion == "1.0.0")
    }

    @Test("A formal release rejects an insecure architecture feed")
    func insecureFeedIsRejected() throws {
        let manifest = validManifest(replacing: .arm64) { artifact in
            DistributionArtifact(
                architecture: artifact.architecture,
                feedURL: URL(string: "http://downloads.aloongplanet.com/appcast-arm64.xml")!,
                dmgFileName: artifact.dmgFileName
            )
        }

        #expect(throws: ReleaseManifestError.insecureFeed(.arm64)) {
            try manifest.validateForFormalRelease()
        }
    }

    @Test("A formal release rejects an artifact name from another architecture")
    func crossArchitectureArtifactNameIsRejected() throws {
        let manifest = validManifest(replacing: .x64) { artifact in
            DistributionArtifact(
                architecture: artifact.architecture,
                feedURL: artifact.feedURL,
                dmgFileName: "VLMSnapper-1.0.0-mac-arm64.dmg"
            )
        }

        #expect(throws: ReleaseManifestError.invalidArtifactName(.x64)) {
            try manifest.validateForFormalRelease()
        }
    }

    @Test("A formal release rejects a malformed Sparkle public key")
    func malformedSparklePublicKeyIsRejected() throws {
        let valid = validManifest()
        let manifest = ReleaseManifest(
            version: valid.version,
            bundleIdentifier: valid.bundleIdentifier,
            sparklePublicKey: "placeholder",
            artifacts: valid.artifacts
        )

        #expect(throws: ReleaseManifestError.invalidSparklePublicKey) {
            try manifest.validateForFormalRelease()
        }
    }

    private func validManifest(
        replacing architecture: DistributionArchitecture? = nil,
        with replacement: (DistributionArtifact) -> DistributionArtifact = { $0 }
    ) -> ReleaseManifest {
        ReleaseManifest(
            version: "1.0.0",
            bundleIdentifier: "com.loong.vlmsnapper",
            sparklePublicKey: Data(repeating: 7, count: 32).base64EncodedString(),
            artifacts: DistributionArchitecture.allCases.map { candidate in
                let artifact = DistributionArtifact(
                    architecture: candidate,
                    feedURL: URL(
                        string: "https://downloads.aloongplanet.com/vlmsnapper/appcast-\(candidate.rawValue).xml"
                    )!,
                    dmgFileName: "VLMSnapper-1.0.0-mac-\(candidate.rawValue).dmg"
                )
                return candidate == architecture ? replacement(artifact) : artifact
            }
        )
    }
}
