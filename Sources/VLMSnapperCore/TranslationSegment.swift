import Foundation

public struct TranslationSegment: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case paragraph, heading, listItem
    }

    public let id: String
    public let block: String
    public let kind: Kind
    public let source: String
    public let translation: String

    public init(id: String, block: String, kind: Kind, source: String, translation: String) {
        self.id = id
        self.block = block
        self.kind = kind
        self.source = source
        self.translation = translation
    }

    /// Separators belong to blocks, never to sentence boundaries. Providers
    /// retain the whitespace needed between adjacent sentences in their text.
    public static func text(_ segments: [Self], translated: Bool) -> String {
        var result = ""
        var previousBlock: String?
        for segment in segments {
            let text = translated ? segment.translation : segment.source
            guard !text.isEmpty else { continue }
            if previousBlock != segment.block {
                if previousBlock != nil { result += "\n\n" }
                if segment.kind == .listItem { result += "- " }
            }
            result += text
            previousBlock = segment.block
        }
        return result
    }
}
