import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Provider HTTP error normalizer")
struct ProviderHTTPErrorNormalizerTests {
    @Test("Provider-specific error bodies retain actionable categories", arguments: [
        ErrorCase(
            provider: .openAI,
            statusCode: 429,
            body: "{\"error\":{\"code\":\"insufficient_quota\"}}",
            expected: .insufficientBalance
        ),
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: "{\"error\":{\"message\":\"This model does not support image input\"}}",
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .gemini,
            statusCode: 400,
            body: "{\"error\":{\"message\":\"Image payload is too large\"}}",
            expected: .imageTooLarge
        ),
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: "{\"error\":{\"message\":\"Image exceeds the maximum supported size\"}}",
            expected: .imageTooLarge
        ),
    ])
    func retainsActionableCategory(testCase: ErrorCase) {
        let error = ProviderHTTPErrorNormalizer().normalize(
            provider: testCase.provider,
            statusCode: testCase.statusCode,
            headers: [:],
            body: Data(testCase.body.utf8)
        )

        #expect(error == testCase.expected)
    }
}

struct ErrorCase: Sendable, CustomTestStringConvertible {
    let provider: ProviderID
    let statusCode: Int
    let body: String
    let expected: ProviderAdapterError

    var testDescription: String {
        "\(provider.rawValue)-\(statusCode)-\(expected)"
    }
}
