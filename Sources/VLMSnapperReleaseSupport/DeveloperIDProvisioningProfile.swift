import Foundation

public enum DeveloperIDProvisioningProfileError: Error, Equatable {
    case invalidPropertyList
    case missingValue(String)
    case unsupportedPlatform
    case notDeveloperIDDistribution
    case expired
    case bundleIdentifierMismatch
    case appIDPrefixMismatch
    case teamIdentifierMismatch
    case keychainAccessGroupNotAuthorized
    case signingCertificateNotAuthorized
    case missingDEREncodedProfile
    case managedEntitlementAlreadyPresent(String)
}

public struct DeveloperIDSigningMetadata: Equatable, Sendable {
    public let profileUUID: String
    public let appIDPrefix: String
    public let teamIdentifier: String
    public let applicationIdentifier: String
    public let keychainAccessGroup: String

    public func effectiveEntitlements(
        basePropertyListData: Data
    ) throws -> Data {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: basePropertyListData,
                options: [],
                format: nil
            )
        } catch {
            throw DeveloperIDProvisioningProfileError.invalidPropertyList
        }
        guard var entitlements = propertyList as? [String: Any] else {
            throw DeveloperIDProvisioningProfileError.invalidPropertyList
        }
        let managedKeys = [
            "com.apple.application-identifier",
            "com.apple.developer.team-identifier",
            "keychain-access-groups",
        ]
        for key in managedKeys where entitlements[key] != nil {
            throw DeveloperIDProvisioningProfileError
                .managedEntitlementAlreadyPresent(key)
        }
        entitlements["com.apple.application-identifier"] = applicationIdentifier
        entitlements["com.apple.developer.team-identifier"] = teamIdentifier
        entitlements["keychain-access-groups"] = [keychainAccessGroup]
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: entitlements,
                format: .xml,
                options: 0
            )
        } catch {
            throw DeveloperIDProvisioningProfileError.invalidPropertyList
        }
    }
}

public struct DeveloperIDProvisioningProfile: Sendable {
    private let profileUUID: String
    private let expirationDate: Date
    private let platforms: [String]
    private let provisionsAllDevices: Bool
    private let applicationIdentifierPrefixes: [String]
    private let teamIdentifiers: [String]
    private let developerCertificates: [Data]
    private let derEncodedProfile: Data
    private let applicationIdentifier: String
    private let entitlementTeamIdentifier: String
    private let keychainAccessGroups: [String]

    public init(decodedPropertyListData: Data) throws {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: decodedPropertyListData,
                options: [],
                format: nil
            )
        } catch {
            throw DeveloperIDProvisioningProfileError.invalidPropertyList
        }
        guard let root = propertyList as? [String: Any] else {
            throw DeveloperIDProvisioningProfileError.invalidPropertyList
        }
        profileUUID = try Self.required(String.self, key: "UUID", in: root)
        expirationDate = try Self.required(
            Date.self,
            key: "ExpirationDate",
            in: root
        )
        platforms = try Self.required([String].self, key: "Platform", in: root)
        provisionsAllDevices = try Self.required(
            Bool.self,
            key: "ProvisionsAllDevices",
            in: root
        )
        applicationIdentifierPrefixes = try Self.required(
            [String].self,
            key: "ApplicationIdentifierPrefix",
            in: root
        )
        teamIdentifiers = try Self.required(
            [String].self,
            key: "TeamIdentifier",
            in: root
        )
        developerCertificates = try Self.required(
            [Data].self,
            key: "DeveloperCertificates",
            in: root
        )
        derEncodedProfile = try Self.required(
            Data.self,
            key: "DER-Encoded-Profile",
            in: root
        )
        guard let entitlements = root["Entitlements"] as? [String: Any] else {
            throw DeveloperIDProvisioningProfileError.missingValue("Entitlements")
        }
        applicationIdentifier = try Self.required(
            String.self,
            key: "com.apple.application-identifier",
            in: entitlements
        )
        entitlementTeamIdentifier = try Self.required(
            String.self,
            key: "com.apple.developer.team-identifier",
            in: entitlements
        )
        keychainAccessGroups = try Self.required(
            [String].self,
            key: "keychain-access-groups",
            in: entitlements
        )
    }

    public func validatedSigningMetadata(
        bundleIdentifier: String,
        signingCertificateDER: Data,
        now: Date = Date()
    ) throws -> DeveloperIDSigningMetadata {
        guard platforms.contains("OSX") else {
            throw DeveloperIDProvisioningProfileError.unsupportedPlatform
        }
        guard provisionsAllDevices else {
            throw DeveloperIDProvisioningProfileError.notDeveloperIDDistribution
        }
        guard expirationDate > now else {
            throw DeveloperIDProvisioningProfileError.expired
        }
        guard !profileUUID.isEmpty else {
            throw DeveloperIDProvisioningProfileError.missingValue("UUID")
        }
        guard !derEncodedProfile.isEmpty else {
            throw DeveloperIDProvisioningProfileError.missingDEREncodedProfile
        }
        guard applicationIdentifier.hasSuffix(".\(bundleIdentifier)") else {
            throw DeveloperIDProvisioningProfileError.bundleIdentifierMismatch
        }
        let prefixLength = applicationIdentifier.count - bundleIdentifier.count - 1
        let appIDPrefix = String(applicationIdentifier.prefix(prefixLength))
        guard !appIDPrefix.isEmpty,
              applicationIdentifierPrefixes.contains(appIDPrefix)
        else {
            throw DeveloperIDProvisioningProfileError.appIDPrefixMismatch
        }
        guard entitlementTeamIdentifier == appIDPrefix,
              teamIdentifiers.contains(entitlementTeamIdentifier)
        else {
            throw DeveloperIDProvisioningProfileError.teamIdentifierMismatch
        }
        let exactKeychainAccessGroup = "\(appIDPrefix).\(bundleIdentifier)"
        guard keychainAccessGroups.contains(where: {
            Self.authorizes($0, exactValue: exactKeychainAccessGroup)
        }) else {
            throw DeveloperIDProvisioningProfileError
                .keychainAccessGroupNotAuthorized
        }
        guard developerCertificates.contains(signingCertificateDER) else {
            throw DeveloperIDProvisioningProfileError
                .signingCertificateNotAuthorized
        }
        return DeveloperIDSigningMetadata(
            profileUUID: profileUUID,
            appIDPrefix: appIDPrefix,
            teamIdentifier: entitlementTeamIdentifier,
            applicationIdentifier: applicationIdentifier,
            keychainAccessGroup: exactKeychainAccessGroup
        )
    }

    private static func required<Value>(
        _ type: Value.Type,
        key: String,
        in dictionary: [String: Any]
    ) throws -> Value {
        guard let value = dictionary[key] as? Value else {
            throw DeveloperIDProvisioningProfileError.missingValue(key)
        }
        return value
    }

    private static func authorizes(
        _ allowedValue: String,
        exactValue: String
    ) -> Bool {
        if allowedValue == exactValue {
            return true
        }
        guard allowedValue.last == "*" else {
            return false
        }
        return exactValue.hasPrefix(allowedValue.dropLast())
    }
}
