import Testing
@testable import VLMSnapperCore

@Suite("Provider API Key safety boundary")
struct ProviderAPIKeyInputTests {
    @Test("only empty newline or more than 4096 UTF-8 bytes are rejected")
    func validationUsesTheDocumentedSafetyBoundary() {
        #expect(ProviderAPIKeyInput.issue(in: "") == .empty)
        #expect(ProviderAPIKeyInput.issue(in: " x\ty ") == nil)
        #expect(ProviderAPIKeyInput.issue(in: "   ") == nil)
        #expect(ProviderAPIKeyInput.issue(in: "e\u{301}\u{200B}") == nil)
        #expect(ProviderAPIKeyInput.issue(in: "x\nY") == .containsNewline)
        #expect(ProviderAPIKeyInput.issue(in: "x\rY") == .containsNewline)
        #expect(ProviderAPIKeyInput.issue(in: "x\u{2028}Y") == .containsNewline)
        #expect(ProviderAPIKeyInput.issue(in: String(repeating: "🔑", count: 1024)) == nil)
        #expect(ProviderAPIKeyInput.issue(in: String(repeating: "🔑", count: 1024) + "x") == .tooLong)
    }
}
