import CryptoKit
import Foundation
import Security

public enum DeveloperIDProfilePreparationError: Error, Equatable {
    case profileDecodeFailed(Int32, String)
    case signingIdentityNotFound(String)
    case outputAlreadyExists(String)
}

extension DeveloperIDProfilePreparationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .profileDecodeFailed(status, message):
            "Provisioning profile CMS decoding failed (status \(status)): \(message)"
        case let .signingIdentityNotFound(identity):
            "The signing identity was not found in the active Keychain search list: \(identity)"
        case let .outputAlreadyExists(path):
            "Refusing to replace an existing signing output: \(path)"
        }
    }
}

public struct DeveloperIDProfilePreparation {
    public init() {}

    public func prepare(
        profileURL: URL,
        bundleIdentifier: String,
        signingIdentity: String,
        baseEntitlementsURL: URL,
        outputEntitlementsURL: URL,
        outputMetadataURL: URL,
        now: Date = Date()
    ) throws {
        let fileManager = FileManager.default
        for outputURL in [outputEntitlementsURL, outputMetadataURL]
        where fileManager.fileExists(atPath: outputURL.path) {
            throw DeveloperIDProfilePreparationError
                .outputAlreadyExists(outputURL.path)
        }
        let decodedProfile = try decodeProfile(at: profileURL)
        let profileData = try Data(contentsOf: profileURL)
        let certificate = try signingCertificateDER(named: signingIdentity)
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: decodedProfile
        )
        let metadata = try profile.validatedSigningMetadata(
            bundleIdentifier: bundleIdentifier,
            signingCertificateDER: certificate,
            now: now
        )
        let baseEntitlements = try Data(contentsOf: baseEntitlementsURL)
        let effectiveEntitlements = try metadata.effectiveEntitlements(
            basePropertyListData: baseEntitlements
        )
        try effectiveEntitlements.write(
            to: outputEntitlementsURL,
            options: .atomic
        )
        do {
            try metadata.propertyListData(
                profileSHA256: SHA256.hash(data: profileData)
                    .map { String(format: "%02x", $0) }
                    .joined()
            ).write(
                to: outputMetadataURL,
                options: .atomic
            )
        } catch {
            try? fileManager.removeItem(at: outputEntitlementsURL)
            throw error
        }
    }

    private func decodeProfile(at url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["cms", "-D", "-i", url.path]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw DeveloperIDProfilePreparationError.profileDecodeFailed(
                process.terminationStatus,
                message
            )
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private func signingCertificateDER(named identityName: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnRef: kCFBooleanTrue as Any,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let identities = result as? [SecIdentity]
        else {
            throw DeveloperIDProfilePreparationError
                .signingIdentityNotFound(identityName)
        }
        for identity in identities {
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
                  let certificate,
                  SecCertificateCopySubjectSummary(certificate) as String?
                    == identityName
            else {
                continue
            }
            return SecCertificateCopyData(certificate) as Data
        }
        throw DeveloperIDProfilePreparationError.signingIdentityNotFound(identityName)
    }
}

private extension DeveloperIDSigningMetadata {
    func propertyListData(profileSHA256: String) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "ProfileUUID": profileUUID,
                "ProfileSHA256": profileSHA256,
                "AppIDPrefix": appIDPrefix,
                "TeamIdentifier": teamIdentifier,
                "ApplicationIdentifier": applicationIdentifier,
                "KeychainAccessGroup": keychainAccessGroup,
            ],
            format: .xml,
            options: 0
        )
    }
}
