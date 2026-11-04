import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Server-sent event decoder")
struct ServerSentEventDecoderTests {
    @Test("SSE data survives arbitrary byte boundaries and ignores comments")
    func dataSurvivesByteBoundaries() throws {
        let bytes = Data(
            ": keep-alive\r\ndata: {\"delta\":\"café\"}\r\n\r\ndata: [DONE]\n\n".utf8
        )
        let accentLead = try #require(bytes.firstIndex(of: 0xC3))
        let boundaries = Array(Set([1, 7, 19, accentLead + 1, bytes.count])).sorted()
        var start = 0
        var decoder = ServerSentEventDecoder()
        var payloads: [String] = []

        for end in boundaries {
            payloads.append(contentsOf: try decoder.consume(bytes[start..<end]))
            start = end
        }
        try decoder.finish()

        #expect(payloads == [#"{"delta":"café"}"#, "[DONE]"])
    }
}
