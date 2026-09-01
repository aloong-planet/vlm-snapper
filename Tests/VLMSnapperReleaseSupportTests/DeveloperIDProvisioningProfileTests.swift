import Foundation
import Testing
@testable import VLMSnapperReleaseSupport

@Suite("Developer ID provisioning profile")
struct DeveloperIDProvisioningProfileTests {
    @Test("a matching distribution profile derives the exact signing identity")
    func matchingProfileDerivesExactIdentity() throws {
        let certificate = Data([0x01, 0x02, 0x03])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                developerCertificates: [certificate]
            )
        )

        let metadata = try profile.validatedSigningMetadata(
            bundleIdentifier: "com.loong.vlmsnapper",
            signingCertificateDER: certificate,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(metadata.profileUUID == "profile-uuid")
        #expect(metadata.appIDPrefix == "RHQ28XS7D9")
        #expect(metadata.teamIdentifier == "RHQ28XS7D9")
        #expect(metadata.applicationIdentifier == "RHQ28XS7D9.com.loong.vlmsnapper")
        #expect(metadata.keychainAccessGroup == "RHQ28XS7D9.com.loong.vlmsnapper")
    }

    @Test("effective entitlements preserve the sandbox and add exact identity claims")
    func effectiveEntitlementsAddExactIdentityClaims() throws {
        let certificate = Data([0x01, 0x02, 0x03])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                developerCertificates: [certificate]
            )
        )
        let metadata = try profile.validatedSigningMetadata(
            bundleIdentifier: "com.loong.vlmsnapper",
            signingCertificateDER: certificate,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let base = try PropertyListSerialization.data(
            fromPropertyList: ["com.apple.security.app-sandbox": true],
            format: .xml,
            options: 0
        )

        let data = try metadata.effectiveEntitlements(basePropertyListData: base)
        let entitlements = try #require(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(
            entitlements["com.apple.application-identifier"] as? String
                == "RHQ28XS7D9.com.loong.vlmsnapper"
        )
        #expect(
            entitlements["com.apple.developer.team-identifier"] as? String
                == "RHQ28XS7D9"
        )
        #expect(
            entitlements["keychain-access-groups"] as? [String]
                == ["RHQ28XS7D9.com.loong.vlmsnapper"]
        )
    }

    @Test("an expired profile is rejected")
    func expiredProfileIsRejected() throws {
        let certificate = Data([0x01])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                expirationDate: Date(timeIntervalSince1970: 1_700_000_000),
                developerCertificates: [certificate]
            )
        )

        #expect(throws: DeveloperIDProvisioningProfileError.expired) {
            try profile.validatedSigningMetadata(
                bundleIdentifier: "com.loong.vlmsnapper",
                signingCertificateDER: certificate,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    @Test("a profile for another bundle identifier is rejected")
    func wrongBundleIdentifierIsRejected() throws {
        let certificate = Data([0x01])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                applicationIdentifier: "RHQ28XS7D9.com.loong.transfer",
                developerCertificates: [certificate]
            )
        )

        #expect(
            throws: DeveloperIDProvisioningProfileError.bundleIdentifierMismatch
        ) {
            try profile.validatedSigningMetadata(
                bundleIdentifier: "com.loong.vlmsnapper",
                signingCertificateDER: certificate,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    @Test("a profile that excludes the signing certificate is rejected")
    func unauthorizedCertificateIsRejected() throws {
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                developerCertificates: [Data([0x01])]
            )
        )

        #expect(
            throws: DeveloperIDProvisioningProfileError
                .signingCertificateNotAuthorized
        ) {
            try profile.validatedSigningMetadata(
                bundleIdentifier: "com.loong.vlmsnapper",
                signingCertificateDER: Data([0x02]),
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    @Test("a profile without an authorizing Keychain group is rejected")
    func unauthorizedKeychainGroupIsRejected() throws {
        let certificate = Data([0x01])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                developerCertificates: [certificate],
                keychainAccessGroups: ["OTHERTEAM.*"]
            )
        )

        #expect(
            throws: DeveloperIDProvisioningProfileError
                .keychainAccessGroupNotAuthorized
        ) {
            try profile.validatedSigningMetadata(
                bundleIdentifier: "com.loong.vlmsnapper",
                signingCertificateDER: certificate,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    @Test("a device-specific profile is rejected")
    func deviceSpecificProfileIsRejected() throws {
        let certificate = Data([0x01])
        let profile = try DeveloperIDProvisioningProfile(
            decodedPropertyListData: try profileData(
                provisionsAllDevices: false,
                developerCertificates: [certificate]
            )
        )

        #expect(
            throws: DeveloperIDProvisioningProfileError.notDeveloperIDDistribution
        ) {
            try profile.validatedSigningMetadata(
                bundleIdentifier: "com.loong.vlmsnapper",
                signingCertificateDER: certificate,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }
    }

    @Test("base entitlements cannot hard-code profile-managed identity keys")
    func baseEntitlementsCannotContainManagedIdentity() throws {
        let metadata = DeveloperIDSigningMetadata(
            profileUUID: "profile-uuid",
            appIDPrefix: "RHQ28XS7D9",
            teamIdentifier: "RHQ28XS7D9",
            applicationIdentifier: "RHQ28XS7D9.com.loong.vlmsnapper",
            keychainAccessGroup: "RHQ28XS7D9.com.loong.vlmsnapper"
        )
        let base = try PropertyListSerialization.data(
            fromPropertyList: [
                "com.apple.application-identifier": "hard-coded-value",
            ],
            format: .xml,
            options: 0
        )

        #expect(
            throws: DeveloperIDProvisioningProfileError
                .managedEntitlementAlreadyPresent(
                    "com.apple.application-identifier"
                )
        ) {
            try metadata.effectiveEntitlements(basePropertyListData: base)
        }
    }

    private func profileData(
        expirationDate: Date = Date(timeIntervalSince1970: 2_400_000_000),
        applicationIdentifier: String = "RHQ28XS7D9.com.loong.vlmsnapper",
        provisionsAllDevices: Bool = true,
        developerCertificates: [Data],
        keychainAccessGroups: [String] = ["RHQ28XS7D9.*"]
    ) throws -> Data {
        let profile: [String: Any] = [
            "UUID": "profile-uuid",
            "ExpirationDate": expirationDate,
            "Platform": ["OSX"],
            "ProvisionsAllDevices": provisionsAllDevices,
            "ApplicationIdentifierPrefix": ["RHQ28XS7D9"],
            "TeamIdentifier": ["RHQ28XS7D9"],
            "DeveloperCertificates": developerCertificates,
            "DER-Encoded-Profile": Data([0x30, 0x82]),
            "Entitlements": [
                "com.apple.application-identifier":
                    applicationIdentifier,
                "com.apple.developer.team-identifier": "RHQ28XS7D9",
                "keychain-access-groups": keychainAccessGroups,
            ],
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: profile,
            format: .xml,
            options: 0
        )
    }
}
