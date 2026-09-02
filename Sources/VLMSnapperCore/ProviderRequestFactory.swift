import Foundation

public struct ProviderRequestFactory: Sendable {
    private let geminiMaximumBodyBytes: Int

    public init(geminiMaximumBodyBytes: Int = 20_000_000) {
        self.geminiMaximumBodyBytes = geminiMaximumBodyBytes
    }

    public func makeRequest(
        provider: ProviderID,
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) throws -> URLRequest {
        switch provider {
        case .openAI:
            return try makeOpenAIRequest(
                modelID: modelID,
                apiKey: apiKey,
                originalPNG: originalPNG,
                operation: operation
            )
        case .gemini:
            return try makeGeminiRequest(
                modelID: modelID,
                apiKey: apiKey,
                originalPNG: originalPNG,
                operation: operation
            )
        case .deepSeek:
            return try makeDeepSeekRequest(
                modelID: modelID,
                apiKey: apiKey,
                originalPNG: originalPNG,
                operation: operation
            )
        }
    }

    private func makeOpenAIRequest(
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) throws -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelID,
            "stream": true,
            "temperature": 0,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt(for: operation)],
                    [
                        "type": "input_image",
                        "image_url": pngDataURL(originalPNG),
                    ],
                ],
            ]],
            "text": [
                "format": structuredFormat(for: operation),
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func makeGeminiRequest(
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) throws -> URLRequest {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        guard let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: pathAllowed),
              let url = URL(
                  string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelID):streamGenerateContent?alt=sse"
              ) else {
            throw ProviderRequestFactoryError.invalidModelID
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt(for: operation)],
                    [
                        "inlineData": [
                            "mimeType": "image/png",
                            "data": originalPNG.base64EncodedString(),
                        ],
                    ],
                ],
            ]],
            "generationConfig": [
                "temperature": 0,
                "responseMimeType": "application/json",
                "responseJsonSchema": structuredSchema(for: operation),
            ],
        ]
        let serializedBody = try JSONSerialization.data(withJSONObject: body)
        guard serializedBody.count < geminiMaximumBodyBytes else {
            throw ProviderRequestFactoryError.requestBodyTooLarge(
                actualBytes: serializedBody.count,
                limitBytes: geminiMaximumBodyBytes
            )
        }
        request.httpBody = serializedBody
        return request
    }

    private func makeDeepSeekRequest(
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) throws -> URLRequest {
        let url = URL(string: "https://api.deepseek.com/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": modelID,
            "stream": true,
            "stream_options": ["include_usage": true],
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt(for: operation)],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": pngDataURL(originalPNG),
                            "detail": "original",
                        ],
                    ],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func prompt(for operation: ProviderOperation) -> String {
        switch operation {
        case .extractText:
            return "VLMSnapper extraction prompt v1. Transcribe all visible text from the image. Preserve reading order and useful Markdown structure. Return exactly one JSON object with this shape: {\"source\":\"<transcribed Markdown>\"}. Do not use other field names or include text outside the JSON object."
        case let .translate(targetLanguage):
            return "VLMSnapper translation prompt v1. First transcribe all visible text from the image into source. Then translate it into \(targetLanguage) in translation. Preserve meaning and useful Markdown structure. Return only the required JSON object, with source before translation."
        }
    }

    private func structuredFormat(for operation: ProviderOperation) -> [String: Any] {
        let name: String
        switch operation {
        case .extractText:
            name = "vlmsnapper_extraction_v1"
        case .translate:
            name = "vlmsnapper_translation_v1"
        }
        return [
            "type": "json_schema",
            "name": name,
            "strict": true,
            "schema": structuredSchema(for: operation),
        ]
    }

    private func structuredSchema(for operation: ProviderOperation) -> [String: Any] {
        let properties: [String: Any]
        let required: [String]
        switch operation {
        case .extractText:
            properties = ["source": ["type": "string"]]
            required = ["source"]
        case .translate:
            properties = [
                "source": ["type": "string"],
                "translation": ["type": "string"],
            ]
            required = ["source", "translation"]
        }
        return [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false,
        ]
    }

    private func pngDataURL(_ data: Data) -> String {
        "data:image/png;base64,\(data.base64EncodedString())"
    }
}

public enum ProviderRequestFactoryError: Error, Equatable {
    case invalidModelID
    case requestBodyTooLarge(actualBytes: Int, limitBytes: Int)
}
