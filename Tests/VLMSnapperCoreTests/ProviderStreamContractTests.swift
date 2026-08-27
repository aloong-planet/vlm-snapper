import Testing
@testable import VLMSnapperCore

@Suite("Provider stream contract")
struct ProviderStreamContractTests {
    @Test("translation completes after ordered source, translation, and metadata events")
    func orderedTranslationStreamCompletes() throws {
        var accumulator = ProviderStreamAccumulator(
            operation: .translate(targetLanguage: "es")
        )

        let firstSource = try accumulator.consume(.sourceDelta("Hello "))
        let secondSource = try accumulator.consume(.sourceDelta("world"))
        let translation = try accumulator.consume(.translationDelta("Hola mundo"))
        let metadata = try accumulator.consume(
            .metadata(
                ProviderResponseMetadata(
                    requestID: "req_123",
                    usage: ProviderTokenUsage(inputTokens: 12, outputTokens: 8, totalTokens: 20)
                )
            )
        )
        #expect(firstSource == nil)
        #expect(secondSource == nil)
        #expect(translation == nil)
        #expect(metadata == nil)

        let result = try accumulator.consume(.completed)

        #expect(
            result == ProviderCompletedOutput(
                source: "Hello world",
                translation: "Hola mundo",
                metadata: ProviderResponseMetadata(
                    requestID: "req_123",
                    usage: ProviderTokenUsage(inputTokens: 12, outputTokens: 8, totalTokens: 20)
                )
            )
        )
    }

    @Test("extraction completes without a translation event")
    func extractionCompletesWithoutTranslation() throws {
        var accumulator = ProviderStreamAccumulator(operation: .extractText)
        _ = try accumulator.consume(.sourceDelta("Extracted text"))
        _ = try accumulator.consume(
            .metadata(ProviderResponseMetadata(requestID: nil, usage: nil))
        )

        let result = try accumulator.consume(.completed)

        #expect(result?.source == "Extracted text")
        #expect(result?.translation == nil)
    }

    @Test("source events cannot resume after translation starts")
    func sourceCannotResumeAfterTranslation() throws {
        var accumulator = ProviderStreamAccumulator(
            operation: .translate(targetLanguage: "es")
        )
        _ = try accumulator.consume(.sourceDelta("Hello"))
        _ = try accumulator.consume(.translationDelta("Hola"))

        #expect(throws: ProviderStreamContractError.invalidEventOrder) {
            _ = try accumulator.consume(.sourceDelta(" again"))
        }
    }

    @Test("completion rejects a stream without terminal metadata")
    func completionRequiresMetadata() throws {
        var accumulator = ProviderStreamAccumulator(operation: .extractText)
        _ = try accumulator.consume(.sourceDelta("Extracted text"))

        #expect(throws: ProviderStreamContractError.incompleteOutput) {
            _ = try accumulator.consume(.completed)
        }
    }
}
