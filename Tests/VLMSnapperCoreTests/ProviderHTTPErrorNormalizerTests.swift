import Foundation
import Testing
@testable import VLMSnapperCore

// Gap: these bodies come from public reports, not live requests. OpenAI's reply on /v1/responses, the endpoint the
// app uses, for a model that takes no images has not been seen. A reply without these phrases counts as an invalid
// request, and the model stays selected. A live contract run would show only the code it gets, not its text.
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
        #expect(normalized(testCase) == testCase.expected)
    }

    /// Only an error about the model's input clears the selected model (v1-core failure mode 10).
    /// The messages are the Providers' published text; the JSON around them follows each Provider's error format.
    /// Sources: github.com/Zoo-Code-Org/Zoo-Code/issues/1106, developers.google.cn/learn/pathways/quizzes/
    /// solution-ai-gemini-images, community.openai.com/t/982848, community.openai.com/t/580195,
    /// community.openai.com/t/1110985, community.make.com/t/105612, and a Google Cloud forum thread on
    /// gemini-1.0-pro-vision, whose second sentence is a summary. The `video_url` body is built from DeepSeek's.
    @Test("only an error about the model's image input counts as unsupported", arguments: [
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: #"{"error":{"message":"Failed to deserialize the JSON body into the target type: messages[154]: unknown variant `image_url`, expected `text` at line 1 column 666600","type":"invalid_request_error"}}"#,
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .gemini,
            statusCode: 400,
            body: #"{"error":{"code":400,"message":"Image input modality is not enabled for models/gemini-pro","status":"INVALID_ARGUMENT"}}"#,
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"Invalid model: ft:gpt-4o-2024-08-06:personal::AJMD5QXL does not support image message content types.","type":"invalid_request_error","param":"model","code":"invalid_type"}}"#,
            expected: .imageInputUnsupported
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"You uploaded an unsupported image. Please make sure your image is below 20 MB in size and is of one the following formats: ['png', 'jpeg', 'gif', 'webp'].","type":"invalid_request_error","param":null,"code":"invalid_image_format"}}"#,
            expected: .invalidRequest
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"Invalid image URL: 'messages[1].content[1].image_url.url'. Expected a base64-encoded data URL with an image MIME type (e.g. 'data:image/png;base64,aW1nIGJ5dGVzIGhlcmU='), but got a value without the 'data:' prefix.","type":"invalid_request_error","param":"messages[1].content[1].image_url.url","code":"invalid_value"}}"#,
            expected: .invalidRequest
        ),
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: #"{"error":{"message":"Failed to deserialize the JSON body into the target type: messages[1]: unknown variant `video_url`, expected `text` at line 1 column 120","type":"invalid_request_error"}}"#,
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
        #expect(normalized(testCase) == testCase.expected)
    }

    /// A model gone or out of reach refreshes the list (v1-core failure mode 11), and the status code does not say so
    /// by itself. The messages are the Providers' published text; the JSON around them follows each Provider's format.
    /// Sources: github.com/RooCodeInc/Roo-Code/issues/439 and 2468, community.openai.com/t/679777, t/704402, t/1371814,
    /// and discuss.ai.google.dev/t/107266.
    @Test("a Provider's reply about a missing model counts as model unavailable", arguments: [
        ErrorCase(
            provider: .deepSeek,
            statusCode: 400,
            body: #"{"error":{"message":"Model Not Exist","type":"invalid_request_error","param":null,"code":"invalid_request_error"}}"#,
            expected: .modelUnavailable
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 404,
            body: #"{"error":{"message":"The model `gpt-4-turbo-preview` does not exist or you do not have access to it.","type":"invalid_request_error","param":null,"code":"model_not_found"}}"#,
            expected: .modelUnavailable
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"The requested model 'gpt-4-0125-preview' does not exist.","type":"invalid_request_error","param":"model","code":"model_not_found"}}"#,
            expected: .modelUnavailable
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 403,
            body: #"{"error":{"message":"Project `proj_x` does not have access to model `gpt-5.2`","type":"invalid_request_error","param":null,"code":"model_not_found"}}"#,
            expected: .modelUnavailable
        ),
        ErrorCase(
            provider: .gemini,
            statusCode: 404,
            body: #"{"error":{"code":404,"message":"models/gemini-pro is not found for API version v1beta, or is not supported for generateContent. Call ListModels to see the list of available models and their supported methods.","status":"NOT_FOUND"}}"#,
            expected: .modelUnavailable
        ),
        ErrorCase(
            provider: .openAI,
            statusCode: 400,
            body: #"{"error":{"message":"This model's maximum context length is 8192 tokens.","type":"invalid_request_error","param":"messages","code":"context_length_exceeded"}}"#,
            expected: .invalidRequest
        ),
    ])
    func classifiesAMissingModel(testCase: ErrorCase) {
        #expect(normalized(testCase) == testCase.expected)
    }
}

private func normalized(_ testCase: ErrorCase) -> ProviderAdapterError {
    ProviderHTTPErrorNormalizer().normalize(
        provider: testCase.provider,
        statusCode: testCase.statusCode,
        headers: [:],
        body: Data(testCase.body.utf8)
    )
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
