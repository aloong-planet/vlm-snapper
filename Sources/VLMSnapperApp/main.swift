import AppKit
import VLMSnapperCore

if Array(CommandLine.arguments.dropFirst()) == ["--verify-data-protection-keychain"] {
    let service = AppleKeychainProviderCredentialStore.defaultService
        + ".release-smoke."
        + UUID().uuidString
    do {
        try await DataProtectionKeychainSmokeTest().run(
            store: AppleKeychainProviderCredentialStore(service: service)
        )
        print("Data Protection Keychain CRUD verification passed.")
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(
            Data("Data Protection Keychain CRUD verification failed: \(error)\n".utf8)
        )
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = VLMSnapperApplicationDelegate()
application.delegate = delegate
application.run()
