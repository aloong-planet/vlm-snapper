import Testing
@testable import VLMSnapperCore

@Suite("Provider adapter error")
struct ProviderAdapterErrorTests {
    @Test("every adapter failure has a stable normalized history code")
    func normalizedCodesAreStable() {
        let cases: [(ProviderAdapterError, String)] = [
            (.invalidCredential, "invalid_credential"),
            (.permissionDenied, "permission_denied"),
            (.invalidRequest, "invalid_request"),
            (.modelUnavailable, "model_unavailable"),
            (.rateLimited(retryAfterSeconds: 60), "rate_limited"),
            (.insufficientBalance, "insufficient_balance"),
            (.providerUnavailable, "provider_unavailable"),
            (.contentBlocked, "content_blocked"),
            (.outputTruncated, "output_truncated"),
            (.imageInputUnsupported, "image_input_unsupported"),
            (.imageTooLarge, "image_too_large"),
            (.malformedOutput, "malformed_output"),
            (.incompleteResponse, "incomplete_response"),
            (.firstTextTimeout, "first_text_timeout"),
            (.streamStalled, "stream_stalled"),
            (.totalTimeout, "total_timeout"),
            (.transport, "transport"),
            (.cancelled, "canceled"),
            (.unknown, "unknown"),
        ]

        for (error, expectedCode) in cases {
            #expect(error.normalizedCode == expectedCode)
        }
    }
}
