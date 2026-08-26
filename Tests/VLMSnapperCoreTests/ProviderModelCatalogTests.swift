import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Official provider model catalog")
struct ProviderModelCatalogTests {
    @Test("Gemini follows every page token and returns one complete model list")
    func geminiFollowsEveryPageToken() async throws {
        let firstURL = try #require(
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        )
        let secondURL = try #require(
            URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&pageToken=next%20page"
            )
        )
        let loader = RoutedHTTPLoader(
            routes: [
                firstURL: ProviderHTTPResponse(
                    data: Data(
                        #"{"models":[{"name":"models/gemini-2.5-pro"}],"nextPageToken":"next page"}"#.utf8
                    ),
                    statusCode: 200
                ),
                secondURL: ProviderHTTPResponse(
                    data: Data(
                        #"{"models":[{"name":"models/gemini-2.5-flash"}]}"#.utf8
                    ),
                    statusCode: 200
                ),
            ]
        )
        let lister = OfficialProviderModelLister(httpLoader: loader)

        let models = try await lister.listModels(provider: .gemini, apiKey: "gemini-secret")

        #expect(models == ["gemini-2.5-pro", "gemini-2.5-flash"])
        let requests = await loader.requests
        #expect(requests.map(\.url) == [firstURL, secondURL])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-goog-api-key") == "gemini-secret" })
        #expect(requests.allSatisfy { $0.url?.absoluteString.contains("gemini-secret") == false })
    }

    @Test(
        "OpenAI-compatible model lists use one official Bearer request",
        arguments: [
            (
                ProviderID.openAI,
                "https://api.openai.com/v1/models",
                "openai-secret",
                #"{"object":"list","data":[{"id":"gpt-4o","object":"model","created":1715367049,"owned_by":"system"},{"id":"text-embedding-3-small","object":"model","created":1705948997,"owned_by":"system"}]}"#,
                ["gpt-4o", "text-embedding-3-small"]
            ),
            (
                ProviderID.deepSeek,
                "https://api.deepseek.com/models",
                "deepseek-secret",
                #"{"object":"list","data":[{"id":"deepseek-chat","object":"model","owned_by":"deepseek"},{"id":"deepseek-v4-flash-vision-exp","object":"model","owned_by":"deepseek"}]}"#,
                ["deepseek-chat", "deepseek-v4-flash-vision-exp"]
            ),
        ]
    )
    func openAICompatibleListsUseOneOfficialBearerRequest(
        provider: ProviderID,
        urlString: String,
        apiKey: String,
        responseJSON: String,
        expectedModels: [String]
    ) async throws {
        let url = try #require(URL(string: urlString))
        let loader = RoutedHTTPLoader(
            routes: [
                url: ProviderHTTPResponse(data: Data(responseJSON.utf8), statusCode: 200),
            ]
        )
        let lister = OfficialProviderModelLister(httpLoader: loader)

        let models = try await lister.listModels(provider: provider, apiKey: apiKey)

        #expect(models == expectedModels)
        let requests = await loader.requests
        #expect(requests.map(\.url) == [url])
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(apiKey)")
    }

    @Test("Gemini rejects a later-page failure instead of returning a partial list")
    func geminiLaterPageFailureRejectsPartialList() async throws {
        let firstURL = try #require(
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        )
        let secondURL = try #require(
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&pageToken=next")
        )
        let loader = RoutedHTTPLoader(
            routes: [
                firstURL: ProviderHTTPResponse(
                    data: Data(
                        #"{"models":[{"name":"models/gemini-2.5-pro"}],"nextPageToken":"next"}"#.utf8
                    ),
                    statusCode: 200
                ),
                secondURL: ProviderHTTPResponse(data: Data(), statusCode: 503),
            ]
        )
        let lister = OfficialProviderModelLister(httpLoader: loader)

        do {
            _ = try await lister.listModels(provider: .gemini, apiKey: "gemini-secret")
            Issue.record("Expected the incomplete pagination request to fail")
        } catch {
            #expect(error as? ProviderModelListError == .requestRejected(statusCode: 503))
        }
        #expect(await loader.requests.map(\.url) == [firstURL, secondURL])
    }

    @Test("authentication rejection is normalized for provider setup")
    func authenticationRejectionIsNormalized() async throws {
        let url = try #require(URL(string: "https://api.openai.com/v1/models"))
        let loader = RoutedHTTPLoader(
            routes: [url: ProviderHTTPResponse(data: Data(), statusCode: 401)]
        )
        let lister = OfficialProviderModelLister(httpLoader: loader)

        do {
            _ = try await lister.listModels(provider: .openAI, apiKey: "invalid-secret")
            Issue.record("Expected authentication rejection")
        } catch {
            #expect(error as? ProviderModelListError == .authenticationRejected)
        }
    }

    @Test("Gemini repeated page tokens are rejected")
    func geminiRepeatedPageTokenIsRejected() async throws {
        let firstURL = try #require(
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        )
        let repeatedURL = try #require(
            URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&pageToken=repeat")
        )
        let loader = RoutedHTTPLoader(
            routes: [
                firstURL: ProviderHTTPResponse(
                    data: Data(#"{"models":[],"nextPageToken":"repeat"}"#.utf8),
                    statusCode: 200
                ),
                repeatedURL: ProviderHTTPResponse(
                    data: Data(#"{"models":[],"nextPageToken":"repeat"}"#.utf8),
                    statusCode: 200
                ),
            ]
        )
        let lister = OfficialProviderModelLister(httpLoader: loader)

        do {
            _ = try await lister.listModels(provider: .gemini, apiKey: "gemini-secret")
            Issue.record("Expected repeated pagination token rejection")
        } catch {
            #expect(error as? ProviderModelListError == .paginationCycle)
        }
        #expect(await loader.requests.count == 2)
    }
}

private actor RoutedHTTPLoader: ProviderHTTPDataLoading {
    private let routes: [URL: ProviderHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(routes: [URL: ProviderHTTPResponse]) {
        self.routes = routes
    }

    func data(for request: URLRequest) async throws -> ProviderHTTPResponse {
        requests.append(request)
        guard let url = request.url, let response = routes[url] else {
            throw ProviderModelListError.invalidResponse
        }
        return response
    }
}
