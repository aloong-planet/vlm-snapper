import Testing
@testable import VLMSnapperCore

@Suite("Ordered structured output parser")
struct OrderedStructuredOutputParserTests {
    @Test("translation JSON streams source before translation across arbitrary chunks")
    func translationStreamsInOrderAcrossChunks() throws {
        var parser = OrderedStructuredOutputParser(
            operation: .translate(targetLanguage: "es")
        )
        let chunks = [
            #"{"sou"#,
            #"rce":"Hello\nwo"#,
            #"rld","translation":"Hola "#,
            #"mundo"}"#,
        ]
        var events: [ProviderStreamEvent] = []

        for chunk in chunks {
            events.append(contentsOf: try parser.consume(chunk))
        }
        try parser.finish()

        let source = events.compactMap { event -> String? in
            guard case let .sourceDelta(delta) = event else { return nil }
            return delta
        }.joined()
        let translation = events.compactMap { event -> String? in
            guard case let .translationDelta(delta) = event else { return nil }
            return delta
        }.joined()
        #expect(source == "Hello\nworld")
        #expect(translation == "Hola mundo")
        let firstTranslationIndex = try #require(
            events.firstIndex { event in
                if case .translationDelta = event { return true }
                return false
            }
        )
        #expect(
            events[..<firstTranslationIndex].allSatisfy { event in
                if case .sourceDelta = event { return true }
                return false
            }
        )
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

    @Test("translation rejects reordered keys")
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
