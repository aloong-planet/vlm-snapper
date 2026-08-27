import Foundation

public struct ProviderHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol ProviderHTTPDataLoading: Sendable {
    func data(for request: URLRequest) async throws -> ProviderHTTPResponse
}

public struct URLSessionProviderHTTPDataLoader: ProviderHTTPDataLoading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> ProviderHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderModelListError.invalidResponse
        }
        return ProviderHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

public enum ProviderModelListError: Error, Equatable {
    case authenticationRejected
    case requestRejected(statusCode: Int)
    case invalidResponse
    case paginationCycle
}

public struct OfficialProviderModelLister: ProviderModelListing {
    private let httpLoader: any ProviderHTTPDataLoading

    public init(httpLoader: any ProviderHTTPDataLoading = URLSessionProviderHTTPDataLoader()) {
        self.httpLoader = httpLoader
    }

    public func listModels(provider: ProviderID, apiKey: String) async throws -> [String] {
        if provider != .gemini {
            return try await listOpenAICompatibleModels(provider: provider, apiKey: apiKey)
        }
        var models: [String] = []
        var pageToken: String?
        var followedTokens = Set<String>()
        repeat {
            if let pageToken, !followedTokens.insert(pageToken).inserted {
                throw ProviderModelListError.paginationCycle
            }
            var components = URLComponents(
                string: "https://generativelanguage.googleapis.com/v1beta/models"
            )
            var queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else {
                throw ProviderModelListError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let response = try await httpLoader.data(for: request)
            try Self.validateStatus(response.statusCode)
            let page: GeminiModelPage
            do {
                page = try JSONDecoder().decode(GeminiModelPage.self, from: response.data)
            } catch {
                throw ProviderModelListError.invalidResponse
            }
            let normalizedNames = page.models.map { model in
                model.name.hasPrefix("models/")
                    ? String(model.name.dropFirst("models/".count))
                    : model.name
            }
            guard normalizedNames.allSatisfy({ !$0.isEmpty }) else {
                throw ProviderModelListError.invalidResponse
            }
            models.append(contentsOf: normalizedNames)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return models
    }

    private func listOpenAICompatibleModels(
        provider: ProviderID,
        apiKey: String
    ) async throws -> [String] {
        let urlString: String
        switch provider {
        case .openAI:
            urlString = "https://api.openai.com/v1/models"
        case .deepSeek:
            urlString = "https://api.deepseek.com/models"
        case .gemini:
            throw ProviderModelListError.invalidResponse
        }
        guard let url = URL(string: urlString) else {
            throw ProviderModelListError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let response = try await httpLoader.data(for: request)
        try Self.validateStatus(response.statusCode)
        let page: OpenAICompatibleModelPage
        do {
            page = try JSONDecoder().decode(OpenAICompatibleModelPage.self, from: response.data)
        } catch {
            throw ProviderModelListError.invalidResponse
        }
        let modelIDs = page.data.map(\.id)
        guard modelIDs.allSatisfy({ !$0.isEmpty }) else {
            throw ProviderModelListError.invalidResponse
        }
        return modelIDs
    }

    private static func validateStatus(_ statusCode: Int) throws {
        if statusCode == 401 || statusCode == 403 {
            throw ProviderModelListError.authenticationRejected
        }
        guard (200..<300).contains(statusCode) else {
            throw ProviderModelListError.requestRejected(statusCode: statusCode)
        }
    }
}

private struct GeminiModelPage: Decodable {
    let models: [GeminiModel]
    let nextPageToken: String?
}

private struct GeminiModel: Decodable {
    let name: String
}

private struct OpenAICompatibleModelPage: Decodable {
    let data: [OpenAICompatibleModel]
}

private struct OpenAICompatibleModel: Decodable {
    let id: String
}
