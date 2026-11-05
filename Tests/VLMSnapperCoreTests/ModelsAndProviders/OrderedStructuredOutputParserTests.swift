import Testing
@testable import VLMSnapperCore

@Suite("Ordered structured output parser")
struct OrderedStructuredOutputParserTests {
    @Test("translation JSON streams sentence pairs across arbitrary chunks")
    func translationStreamsInOrderAcrossChunks() throws {
        var parser = OrderedStructuredOutputParser(
            operation: .translate(targetLanguage: "es")
        )
        let chunks = [
            #"{"segments":[{"id":"s1","block":"p1","kind":"paragraph","sou"#,
            #"rce":"Hello\nwo"#,
            #"rld","translation":"Hola "#,
            #"mundo"}]}"#,
        ]
        var events: [ProviderStreamEvent] = []

        for chunk in chunks {
            events.append(contentsOf: try parser.consume(chunk))
        }
        try parser.finish()

        guard case let .translationSegments(segments) = try #require(events.last) else {
            Issue.record("Expected a paired translation"); return
        }
        #expect(segments.first?.source == "Hello\nworld")
        #expect(segments.first?.translation == "Hola mundo")
    }

    @Test("Unicode escape and surrogate boundaries do not emit malformed text")
    func unicodeEscapeBoundariesAreSafe() throws {
        var parser = OrderedStructuredOutputParser(operation: .extractText)
        var events: [ProviderStreamEvent] = []
        for chunk in [#"{"source":"A\uD83"#, #"D\uDE"#, #"00B"}"#] {
            events.append(contentsOf: try parser.consume(chunk))
        }
        try parser.finish()

        #expect(events == [.sourceDelta("A"), .sourceDelta("😀B")])
    }

    @Test("translation rejects the obsolete unpaired envelope")
    func translationRejectsReorderedKeys() {
        var parser = OrderedStructuredOutputParser(
            operation: .translate(targetLanguage: "es")
        )

        #expect(throws: OrderedStructuredOutputParserError.malformedOutput) {
            _ = try parser.consume(#"{"translation":"Hola","source":"Hello"}"#)
        }
    }

    @Test("finish rejects incomplete JSON")
    func finishRejectsIncompleteJSON() throws {
        var parser = OrderedStructuredOutputParser(operation: .extractText)
        _ = try parser.consume(#"{"source":"Hello""#)

        #expect(throws: OrderedStructuredOutputParserError.incompleteOutput) {
            try parser.finish()
        }
    }

    @Test("a combining mark arriving later extends the streamed source")
    func combiningMarkAcrossChunks() throws {
        var parser = OrderedStructuredOutputParser(operation: .extractText)
        var events = try parser.consume(#"{"source":"e"#)
        events.append(contentsOf: try parser.consume("\u{0301}\"}"))
        try parser.finish()

        #expect(events == [.sourceDelta("e"), .sourceDelta("\u{0301}")])
    }
}
