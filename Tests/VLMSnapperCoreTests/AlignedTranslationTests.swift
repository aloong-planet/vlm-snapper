import Testing
@testable import VLMSnapperCore

@Suite("Aligned translation")
struct AlignedTranslationTests {
    @Test("escaped Unicode survives every scalar chunk boundary with any field order")
    func unicodeAndKeyOrder() throws {
        let json = #"{"segments":[{"translation":"\u4f60\u597d","source":"\ud83d\udc69\u200d\ud83d\udcbb Cafe\u0301. ","kind":"heading","block":"title","id":"a"},{"id":"b","block":"p","kind":"paragraph","source":"שלום","translation":"和平"}]}"#
        var parser = OrderedStructuredOutputParser(operation: .translate(targetLanguage: "zh-Hans"))
        var accumulator = ProviderStreamAccumulator(operation: .translate(targetLanguage: "zh-Hans"))
        for scalar in json.unicodeScalars {
            for event in try parser.consume(String(scalar)) { _ = try accumulator.consume(event) }
        }
        try parser.finish()
        _ = try accumulator.consume(.metadata(ProviderResponseMetadata(requestID: nil, usage: nil)))
        let result = try #require(try accumulator.consume(.completed))
        #expect(result.source == "👩‍💻 Cafe\u{301}. \n\nשלום")
        #expect(result.translation == "你好\n\n和平")
        #expect(result.segments?.map(\.id) == ["a", "b"])
    }

    @Test("empty images complete without inventing text")
    func emptyImage() throws {
        var parser = OrderedStructuredOutputParser(operation: .translate(targetLanguage: "en"))
        var accumulator = ProviderStreamAccumulator(operation: .translate(targetLanguage: "en"))
        for event in try parser.consume(#"{"segments":[]}"#) { _ = try accumulator.consume(event) }
        try parser.finish()
        _ = try accumulator.consume(.metadata(ProviderResponseMetadata(requestID: nil, usage: nil)))
        let result = try #require(try accumulator.consume(.completed))
        #expect(result.source == "")
        #expect(result.translation == "")
        #expect(result.segments == [])
    }

    @Test("invalid structures cannot complete", arguments: [
        #"{"segments":[{"id":"a","block":"p","kind":"paragraph","source":"A","translation":"甲"},{"id":"a","block":"p","kind":"paragraph","source":"B","translation":"乙"}]}"#,
        #"{"segments":[{"id":"a","block":"p","kind":"paragraph","source":"A"}]}"#,
        #"{"segments":[{"id":"a","block":"p","kind":"paragraph","source":"A","translation":""}]}"#,
        #"{"segments":[{"id":"a","block":"p","kind":"unknown","source":"A","translation":"甲"}]}"#,
        #"{"segments":[{"id":"a","id":"b","block":"p","kind":"paragraph","source":"A","translation":"甲"}]}"#,
        #"{"segments":[],}"#,
        #"{"segments":[]} extra"#,
        #"{"segments":[{"id":"a","block":"p","kind":"paragraph","source":"A","translation":"甲"},]}"#,
        #"{"segments":[{"id":"a","block":"p","kind":"paragraph","source":"A","translation":"甲"}"#,
    ])
    func invalidStructures(_ json: String) {
        #expect(throws: OrderedStructuredOutputParserError.self) {
            var parser = OrderedStructuredOutputParser(operation: .translate(targetLanguage: "zh-Hans"))
            _ = try parser.consume(json)
            try parser.finish()
        }
    }

    @Test("a first translation is available before the next source sentence")
    func streamsPairsInsideParagraphs() throws {
        var parser = OrderedStructuredOutputParser(operation: .translate(targetLanguage: "zh-Hans"))
        let first = try parser.consume(#"{"segments":[{"id":"s1","block":"p1","kind":"paragraph","source":"Need help? ","translation":"需要帮助？"}"#)
        #expect(first == [.translationSegments([TranslationSegment(id: "s1", block: "p1", kind: .paragraph,
            source: "Need help? ", translation: "需要帮助？")])])
        _ = try parser.consume(#",{"id":"s2","block":"p1","kind":"paragraph","source":"Contact us.","translation":"联系我们。"}]}"#)
        try parser.finish()
    }
}
