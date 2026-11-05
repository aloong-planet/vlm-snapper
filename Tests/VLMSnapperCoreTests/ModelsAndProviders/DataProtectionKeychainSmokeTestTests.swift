import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Data Protection Keychain smoke test")
struct DataProtectionKeychainSmokeTestTests {
    @Test("the smoke test verifies a complete credential lifecycle")
    func verifiesCompleteCredentialLifecycle() async throws {
        let store = SmokeCredentialStore()
        let first = ProviderCredential(
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            apiKey: "first-fake-secret"
        )
        let replacement = ProviderCredential(
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            apiKey: "replacement-fake-secret"
        )

        try await DataProtectionKeychainSmokeTest().run(
            store: store,
            provider: .deepSeek,
            firstCredential: first,
            replacementCredential: replacement
        )

        #expect(await store.operations == [
            "replace:first-fake-secret",
            "read",
            "replace:replacement-fake-secret",
            "read",
            "delete",
            "read",
        ])
    }

    @Test("a failed smoke test still attempts to delete its credential")
    func failureStillAttemptsCleanup() async {
        let store = FailingSmokeCredentialStore()

        await #expect(throws: SmokeBoundaryError.readFailed) {
            try await DataProtectionKeychainSmokeTest().run(store: store)
        }

        #expect(await store.operations == ["replace", "read", "delete"])
    }
}

private actor SmokeCredentialStore: ProviderCredentialStoring {
    private var credentialValue: ProviderCredential?
    private(set) var operations: [String] = []

    func credential(for provider: ProviderID) -> ProviderCredential? {
        operations.append("read")
        return credentialValue
    }

    func replaceCredential(
        _ credential: ProviderCredential,
        for provider: ProviderID
    ) {
        operations.append("replace:\(credential.apiKey)")
        credentialValue = credential
    }

    func deleteCredential(for provider: ProviderID) {
        operations.append("delete")
        credentialValue = nil
    }
}

private enum SmokeBoundaryError: Error {
    case readFailed
}

private actor FailingSmokeCredentialStore: ProviderCredentialStoring {
    private(set) var operations: [String] = []

    func credential(for provider: ProviderID) throws -> ProviderCredential? {
        operations.append("read")
        throw SmokeBoundaryError.readFailed
    }

    func replaceCredential(
        _ credential: ProviderCredential,
        for provider: ProviderID
    ) {
        operations.append("replace")
    }

    func deleteCredential(for provider: ProviderID) {
        operations.append("delete")
    }
}
