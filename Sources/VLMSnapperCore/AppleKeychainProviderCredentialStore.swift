import Foundation
import Security

public enum AppleKeychainError: Error, Equatable {
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

public struct AppleKeychainProviderCredentialStore: ProviderCredentialStoring {
    public static let defaultService = "com.loong.vlmsnapper.provider-api-key"

    private let service: String
    private let usesDataProtectionKeychain: Bool

    public init(
        service: String = Self.defaultService,
        usesDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    public func credential(for provider: ProviderID) async throws -> ProviderCredential? {
        var query = baseQuery(for: provider)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppleKeychainError.unexpectedStatus(status)
        }
        do {
            return try JSONDecoder().decode(ProviderCredential.self, from: data)
        } catch {
            throw AppleKeychainError.decodingFailed
        }
    }

    public func replaceCredential(
        _ credential: ProviderCredential,
        for provider: ProviderID
    ) async throws {
        let data: Data
        do {
            data = try JSONEncoder().encode(credential)
        } catch {
            throw AppleKeychainError.encodingFailed
        }
        let query = baseQuery(for: provider)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AppleKeychainError.unexpectedStatus(updateStatus)
        }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel] = "VLMSnapper \(provider.rawValue) API Key"
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppleKeychainError.unexpectedStatus(addStatus)
        }
    }

    public func deleteCredential(for provider: ProviderID) async throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppleKeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for provider: ProviderID) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: provider.rawValue,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        if usesDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain] = kCFBooleanTrue
        }
        return query
    }
}
