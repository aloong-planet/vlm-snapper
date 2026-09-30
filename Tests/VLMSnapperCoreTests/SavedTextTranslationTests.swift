import Foundation
import Testing
@testable import VLMSnapperCore

struct SavedTextTranslationTests {
    @Test func sourceIsPartitionedWithoutChangingItsBytes() throws {
        let plan = try SavedTextTranslation(source: "Need help? Contact us.")
        #expect(plan.segments.map(\.id) == ["saved-1", "saved-2"])
        #expect(plan.segments.map(\.source) == ["Need help? ", "Contact us."])
        #expect(TranslationSegment.text(plan.segments, translated: false) == "Need help? Contact us.")
    }

    @Test func leadingWhitespaceDoesNotBecomeAnUntranslatableSegment() throws {
        let plan = try SavedTextTranslation(source: "\n\nNeed help? Contact us.\n")
        #expect(plan.segments.map(\.source) == ["\n\nNeed help? ", "Contact us.\n"])
    }

    @Test func partialTranslationKeepsTheFullSourceAndFinalValidationRejectsMissingPairs() throws {
        let plan = try SavedTextTranslation(source: "Need help? Contact us.")
        let partial = [TranslationSegment(id: "saved-1", block: "saved", kind: .paragraph,
            source: "Need help? ", translation: "需要")]
        let merged = try plan.merging(partial, complete: false)
        #expect(merged.map(\.source) == ["Need help? ", "Contact us."])
        #expect(merged.map(\.translation) == ["需要", ""])
        #expect(throws: ProviderStreamContractError.self) { try plan.merging(partial, complete: true) }
    }

    @Test(arguments: ["id", "block", "kind", "source", "sourcePrefix", "translation"])
    func finalMappingRejectsChangedIdentitySourceOrEmptyTranslation(field: String) throws {
        let plan = try SavedTextTranslation(source: "Hello.")
        let segment = TranslationSegment(id: field == "id" ? "other" : "saved-1",
            block: field == "block" ? "other" : "saved", kind: field == "kind" ? .heading : .paragraph,
            source: field == "source" ? "Goodbye." : field == "sourcePrefix" ? "Hel" : "Hello.",
            translation: field == "translation" ? " " : "你好。")
        #expect(throws: ProviderStreamContractError.self) { try plan.merging([segment], complete: true) }
    }

    // Shape follows the user's archived multi-paragraph Markdown/URL screenshots.
    @Test func markdownUnicodeAndRepeatedSentencesRetainExactSourceBytes() throws {
        let text = "# Help\n\nNeed help? Need help?\n\n- Cafe\u{301} 👩🏽‍💻: https://example.com/a?b=c\n- مرحبا.\n"
        let plan = try SavedTextTranslation(source: text)
        #expect(Array(TranslationSegment.text(plan.segments, translated: false).utf8) == Array(text.utf8))
        #expect(Set(plan.segments.map(\.id)).count == plan.segments.count)
        #expect(throws: OperationWorkspaceRunFailure.self) { try SavedTextTranslation(source: " \n\t") }
    }
}
