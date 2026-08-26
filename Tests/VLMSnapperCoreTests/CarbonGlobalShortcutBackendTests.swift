import Testing
@testable import VLMSnapperCore

@Suite("Carbon global shortcut backend")
@MainActor
struct CarbonGlobalShortcutBackendTests {
    @Test("the native registrar installs and releases in a test host")
    func nativeRegistrarLifecycle() throws {
        weak var releasedBackend: CarbonGlobalShortcutBackend?

        do {
            let backend = try CarbonGlobalShortcutBackend()
            releasedBackend = backend
            #expect(releasedBackend != nil)
        }

        #expect(releasedBackend == nil)
    }
}
