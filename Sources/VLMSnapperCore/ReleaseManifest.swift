import Foundation

public enum DistributionArchitecture: String, CaseIterable, Codable, Sendable {
    case universal
    case arm64
    case x64
}

public struct DistributionArtifact: Codable, Equatable, Sendable {
    public let architecture: DistributionArchitecture
    public let feedURL: URL
    public let dmgFileName: String

    public init(
        architecture: DistributionArchitecture,
        feedURL: URL,
        dmgFileName: String
    ) {
        self.architecture = architecture
        self.feedURL = feedURL
        self.dmgFileName = dmgFileName
    }
}

public enum ReleaseManifestError: Error, Equatable {
    case incompleteArchitectureSet
    case invalidSparklePublicKey
    case insecureFeed(DistributionArchitecture)
    case invalidArtifactName(DistributionArchitecture)
}

public struct ReleaseManifest: Codable, Equatable, Sendable {
    public let version: String
    public let buildVersion: String
    public let bundleIdentifier: String
    public let sparklePublicKey: String
    public let artifacts: [DistributionArtifact]

    public init(
        version: String,
        buildVersion: String,
        bundleIdentifier: String,
        sparklePublicKey: String,
        artifacts: [DistributionArtifact]
    ) {
        self.version = version
        self.buildVersion = buildVersion
        self.bundleIdentifier = bundleIdentifier
        self.sparklePublicKey = sparklePublicKey
        self.artifacts = artifacts
    }

    public func validateForFormalRelease() throws {
        guard let publicKey = Data(base64Encoded: sparklePublicKey),
              publicKey.count == 32 else {
            throw ReleaseManifestError.invalidSparklePublicKey
        }
        guard Set(artifacts.map(\.architecture)) == Set(DistributionArchitecture.allCases),
              artifacts.count == DistributionArchitecture.allCases.count else {
            throw ReleaseManifestError.incompleteArchitectureSet
        }
        for artifact in artifacts where artifact.feedURL.scheme?.lowercased() != "https" {
            throw ReleaseManifestError.insecureFeed(artifact.architecture)
        }
        for artifact in artifacts {
            let expectedName = "VLMSnapper-\(version)-mac-\(artifact.architecture.rawValue).dmg"
            guard artifact.dmgFileName == expectedName else {
                throw ReleaseManifestError.invalidArtifactName(artifact.architecture)
            }
        }
    }
}
