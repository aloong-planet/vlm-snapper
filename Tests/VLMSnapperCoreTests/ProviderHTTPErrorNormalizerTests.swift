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

    /// Only an error about the model's input clears the selected model (v1-core failure mode 10).
    /// The messages are the Providers' published text; the JSON around them follows each Provider's error format.
    /// Sources: github.com/Zoo-Code-Org/Zoo-Code/issues/1106, community.openai.com/t/884599,
    /// community.openai.com/t/580195, community.make.com/t/105612, and a Google Cloud forum thread on
    /// gemini-1.0-pro-vision, whose second sentence is a summary.
    @Test("only an error about the model's image input counts as unsupported", arguments: [
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: #"{"error":{"message":"Failed to deserialize the JSON body into the target type: messages[154]: unknown variant `image_url`, expected `text` at line 1 column 666600","type":"invalid_request_error"}}"#,
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"Invalid content type. image_url is only supported by certain models.","type":"invalid_request_error","param":"messages.[0].content.[1].type","code":null}}"#,
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"You uploaded an unsupported image. Please make sure your image is below 20 MB in size and is of one the following formats: ['png', 'jpeg', 'gif', 'webp'].","type":"invalid_request_error","param":null,"code":"invalid_image_format"}}"#,
            expected: .invalidRequest
        ),
        ErrorCase(
            provider: .gemini,
            statusCode: 400,
            body: #"{"error":{"code":400,"message":"Unable to submit request because it contains input data that's not supported. This model supports text, text and up to 16 images, or text and 1 video.","status":"INVALID_ARGUMENT"}}"#,
            expected: .invalidRequest
        ),
        ErrorCase(
            provider: .gemini,
            statusCode: 400,
            body: #"{"error":{"code":400,"message":"Unable to process input image","status":"INVALID_ARGUMENT"}}"#,
            expected: .invalidRequest
        ),
    ])
    func classifiesOnlyModelInputAsUnsupported(testCase: ErrorCase) {
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
