import Foundation

/// Immutable input for the explicit conversion action, never for image retry.
public struct SavedTextTranslation: Equatable, Sendable {
    public let segments: [TranslationSegment]

    public init(source: String) throws {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
        }
        var starts: [String.Index] = [source.startIndex]
        var foundSentence = false
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex,
                                   options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            guard !source[range].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if foundSentence { starts.append(range.lowerBound) }
            foundSentence = true
        }
        starts.append(source.endIndex)
        // Retain every original separator and Markdown character. One logical
        // block avoids adding separators while the text view honors newlines.
        segments = zip(starts, starts.dropFirst()).enumerated().map { index, range in
            TranslationSegment(id: "saved-\(index + 1)", block: "saved", kind: .paragraph,
                source: String(source[range.0..<range.1]), translation: "")
        }
    }

    public func merging(_ received: [TranslationSegment], complete: Bool) throws -> [TranslationSegment] {
        guard received.count <= segments.count, !complete || received.count == segments.count else {
            throw ProviderStreamContractError.incompleteOutput
        }
        var result = segments
        for (index, value) in received.enumerated() {
            let expected = segments[index]
            guard value.id == expected.id, value.block == expected.block, value.kind == expected.kind,
                  expected.source.utf8.starts(with: value.source.utf8),
                  !complete || (expected.source.utf8.elementsEqual(value.source.utf8)
                    && !value.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
                throw ProviderStreamContractError.incompleteOutput
            }
            result[index] = TranslationSegment(id: expected.id, block: expected.block, kind: expected.kind,
                source: expected.source, translation: value.translation)
        }
        return result
    }
}
