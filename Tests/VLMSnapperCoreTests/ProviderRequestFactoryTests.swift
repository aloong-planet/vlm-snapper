import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Provider request factory")
struct ProviderRequestFactoryTests {
    @Test("OpenAI request sends the original PNG in one structured streaming request")
    func openAIRequestUsesOriginalPNGAndStructuredStream() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let factory = ProviderRequestFactory()

        let request = try factory.makeRequest(
            provider: .openAI,
            modelID: "gpt-4.1",
            apiKey: "openai-secret",
            originalPNG: png,
            operation: .translate(targetLanguage: "es")
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer openai-secret")
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["model"] as? String == "gpt-4.1")
        #expect(json["stream"] as? Bool == true)
        let input = try #require(json["input"] as? [[String: Any]])
        let content = try #require(input.first?["content"] as? [[String: Any]])
        let image = try #require(content.first { $0["type"] as? String == "input_image" })
        #expect(
            image["image_url"] as? String
                == "data:image/png;base64,\(png.base64EncodedString())"
        )
        let text = try #require(json["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
    }

    @Test("Gemini request uses inline PNG data and JSON schema streaming")
    func geminiRequestUsesInlinePNGAndJSONSchemaStreaming() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let factory = ProviderRequestFactory()

        let request = try factory.makeRequest(
            provider: .gemini,
            modelID: "gemini-2.5-flash",
            apiKey: "gemini-secret",
            originalPNG: png,
            operation: .extractText
        )

        #expect(
            request.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-secret")
        #expect(request.url?.query?.contains("key=") == false)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let contents = try #require(json["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        let inlineData = try #require(
            parts.compactMap { $0["inlineData"] as? [String: Any] }.first
        )
        #expect(inlineData["mimeType"] as? String == "image/png")
        #expect(inlineData["data"] as? String == png.base64EncodedString())
        let generationConfig = try #require(json["generationConfig"] as? [String: Any])
        #expect(generationConfig["responseMimeType"] as? String == "application/json")
        #expect(generationConfig["responseJsonSchema"] != nil)
    }

    @Test("Gemini rejects a serialized request body at the configured byte limit")
    func geminiRejectsOversizedSerializedBody() throws {
        let factory = ProviderRequestFactory(geminiMaximumBodyBytes: 100)

        do {
            _ = try factory.makeRequest(
                provider: .gemini,
                modelID: "gemini-2.5-flash",
                apiKey: "gemini-secret",
                originalPNG: Data(repeating: 0x01, count: 64),
                operation: .extractText
            )
            Issue.record("Expected the serialized Gemini body to be rejected")
        } catch let ProviderRequestFactoryError.requestBodyTooLarge(actualBytes, limitBytes) {
            #expect(actualBytes >= limitBytes)
            #expect(limitBytes == 100)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("DeepSeek request uses the vision Chat Completions contract")
    func deepSeekRequestUsesVisionChatCompletions() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let factory = ProviderRequestFactory()

        let request = try factory.makeRequest(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            apiKey: "deepseek-secret",
            originalPNG: png,
            operation: .translate(targetLanguage: "fr")
        )

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-secret")
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["model"] as? String == "deepseek-v4-flash-vision-exp")
        #expect(json["stream"] as? Bool == true)
        let streamOptions = try #require(json["stream_options"] as? [String: Any])
        #expect(streamOptions["include_usage"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let imagePart = try #require(
            content.first { $0["type"] as? String == "image_url" }
        )
        let imageURL = try #require(imagePart["image_url"] as? [String: Any])
        #expect(
            imageURL["url"] as? String
                == "data:image/png;base64,\(png.base64EncodedString())"
        )
        #expect(imageURL["detail"] as? String == "original")
        let responseFormat = try #require(json["response_format"] as? [String: Any])
        #expect(responseFormat["type"] as? String == "json_object")
    }

    @Test("DeepSeek extraction prompt requires the canonical source field")
    func deepSeekExtractionPromptRequiresCanonicalSourceField() throws {
        let request = try ProviderRequestFactory().makeRequest(
            provider: .deepSeek,
            modelID: "deepseek-v4-flash-vision-exp",
            apiKey: "deepseek-secret",
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            operation: .extractText
        )
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? [[String: Any]])
        let textPart = try #require(content.first { $0["type"] as? String == "text" })

        #expect(
            textPart["text"] as? String
                == "VLMSnapper extraction prompt v1. Transcribe all visible text from the image. Preserve reading order and useful Markdown structure. Return exactly one JSON object with this shape: {\"source\":\"<transcribed Markdown>\"}. Do not use other field names or include text outside the JSON object."
        )
    }
}
