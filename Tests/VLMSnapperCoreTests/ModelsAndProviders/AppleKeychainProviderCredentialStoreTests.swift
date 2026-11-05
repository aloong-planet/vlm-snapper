import Foundation
import Testing
@testable import VLMSnapperCore

// SwiftPM's unsigned test host cannot access the Data Protection Keychain.
// The production default remains enabled and requires signed-app verification in Ticket 10.
@Suite("Apple Keychain provider credential store", .serialized)
struct AppleKeychainProviderCredentialStoreTests {
    @Test("a provider credential can be added, replaced, read, and deleted")
    func credentialLifecycle() async throws {
        let service = "com.loong.vlmsnapper.tests.\(UUID().uuidString)"
        let store = AppleKeychainProviderCredentialStore(
            service: service,
            usesDataProtectionKeychain: false
        )
        try? await store.deleteCredential(for: .openAI)
        do {
            let first = ProviderCredential(
                generation: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                apiKey: "first-test-secret"
            )
            try await store.replaceCredential(first, for: .openAI)
            #expect(try await store.credential(for: .openAI) == first)

            let replacement = ProviderCredential(
                generation: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                apiKey: "replacement-test-secret"
            )
            try await store.replaceCredential(replacement, for: .openAI)
            #expect(try await store.credential(for: .openAI) == replacement)

            try await store.deleteCredential(for: .openAI)
            #expect(try await store.credential(for: .openAI) == nil)
        } catch {
            try? await store.deleteCredential(for: .openAI)
            throw error
        }
    }
}
