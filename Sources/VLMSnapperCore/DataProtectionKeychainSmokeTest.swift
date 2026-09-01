import Foundation

public enum DataProtectionKeychainSmokeTestError: Error, Equatable {
    case lifecycleMismatch(String)
}

public struct DataProtectionKeychainSmokeTest {
    public init() {}

    public func run(
        store: any ProviderCredentialStoring,
        provider: ProviderID = .openAI,
        firstCredential: ProviderCredential = ProviderCredential(
            generation: UUID(),
            apiKey: UUID().uuidString
        ),
        replacementCredential: ProviderCredential = ProviderCredential(
            generation: UUID(),
            apiKey: UUID().uuidString
        )
    ) async throws {
        do {
            try await store.replaceCredential(firstCredential, for: provider)
            guard try await store.credential(for: provider) == firstCredential else {
                throw DataProtectionKeychainSmokeTestError
                    .lifecycleMismatch("read after add")
            }
            try await store.replaceCredential(replacementCredential, for: provider)
            guard try await store.credential(for: provider) == replacementCredential else {
                throw DataProtectionKeychainSmokeTestError
                    .lifecycleMismatch("read after update")
            }
            try await store.deleteCredential(for: provider)
            guard try await store.credential(for: provider) == nil else {
                throw DataProtectionKeychainSmokeTestError
                    .lifecycleMismatch("read after delete")
            }
        } catch {
            try? await store.deleteCredential(for: provider)
            throw error
        }
    }
}
