import Foundation

/// Incremental JSON grammar for one segments envelope. Complete segments are
/// retained; only the active string is decoded again at chunk boundaries.
/// Keys can arrive in any order; no range is published before its identity and
/// block metadata are complete. Text is data, never Markdown/HTML to execute.
struct AlignedTranslationParser: Sendable {
    private enum State: Equatable {
        case start, rootKey, rootColon, arrayStart
        case segmentStart(allowEnd: Bool), fieldKey, fieldColon, fieldValue, fieldEnd
        case segmentEnd, rootEnd, done
    }
    private var state: State = .start
    private var token = ""
    private var escaped = false
    private var key = ""
    private var fields: [String: String] = [:]
    private var segments: [TranslationSegment] = []
    private var ids = Set<String>()
    private var blocks: [String: TranslationSegment.Kind] = [:]
    private var emitted: [TranslationSegment]?
    private let keys: Set<String> = ["id", "block", "kind", "source", "translation"]

    mutating func consume(_ delta: String) throws -> [ProviderStreamEvent] {
        for scalar in delta.unicodeScalars {
            let character = String(scalar)
            if !token.isEmpty {
                token += character
                if character == "\"", !escaped {
                    let value = try decode(token)
                    token = ""
                    try acceptString(value)
                } else if character == "\\", !escaped {
                    escaped = true
                } else {
                    escaped = false
                }
                continue
            }
            if [" ", "\t", "\r", "\n"].contains(character) { continue }
            if character == "\"", state == .rootKey || state == .fieldKey || state == .fieldValue {
                token = "\""
                escaped = false
                continue
            }
            switch (state, character) {
            case (.start, "{"): state = .rootKey
            case (.rootColon, ":"): state = .arrayStart
            case (.arrayStart, "["): state = .segmentStart(allowEnd: true)
            case (.segmentStart, "{"):
                fields = [:]
                state = .fieldKey
            case (.segmentStart(allowEnd: true), "]"): state = .rootEnd
            case (.fieldColon, ":"): state = .fieldValue
            case (.fieldEnd, ","): state = .fieldKey
            case (.fieldEnd, "}"):
                guard Set(fields.keys) == keys, let segment = makeSegment(fields),
                      !segment.source.isEmpty, !segment.translation.isEmpty,
                      ids.insert(segment.id).inserted else { throw malformed }
                if let kind = blocks[segment.block] {
                    guard kind == segment.kind, segments.last?.block == segment.block else { throw malformed }
                }
                blocks[segment.block] = segment.kind
                segments.append(segment)
                fields = [:]
                state = .segmentEnd
            case (.segmentEnd, ","): state = .segmentStart(allowEnd: false)
            case (.segmentEnd, "]"): state = .rootEnd
            case (.rootEnd, "}"): state = .done
            default: throw malformed
            }
        }
        var snapshot = segments
        var partial = fields
        // Only content strings may stream. An unfinished id/block/kind is not
        // an identity and must never enter a published correspondence snapshot.
        if state == .fieldValue, !token.isEmpty, key == "source" || key == "translation" {
            partial[key] = try decodePrefix(token)
        }
        if let segment = makeSegment(partial), !segment.source.isEmpty || !segment.translation.isEmpty {
            guard !ids.contains(segment.id) else { throw malformed }
            snapshot.append(segment)
        }
        guard snapshot != emitted else { return [] }
        // Empty metadata is not a text event. An empty completed document is.
        guard !snapshot.isEmpty || state == .done else { return [] }
        emitted = snapshot
        return [.translationSegments(snapshot)]
    }

    func finish() throws {
        guard state == .done, token.isEmpty else {
            throw OrderedStructuredOutputParserError.incompleteOutput
        }
    }

    private mutating func acceptString(_ value: String) throws {
        switch state {
        case .rootKey:
            guard value == "segments" else { throw malformed }
            state = .rootColon
        case .fieldKey:
            guard keys.contains(value), fields[value] == nil else { throw malformed }
            key = value
            state = .fieldColon
        case .fieldValue:
            fields[key] = value
            state = .fieldEnd
        default: throw malformed
        }
    }

    private func makeSegment(_ values: [String: String]) -> TranslationSegment? {
        guard let id = values["id"], !id.isEmpty,
              let block = values["block"], !block.isEmpty,
              let kindValue = values["kind"], let kind = TranslationSegment.Kind(rawValue: kindValue) else { return nil }
        return TranslationSegment(id: id, block: block, kind: kind,
                                  source: values["source"] ?? "", translation: values["translation"] ?? "")
    }

    private func decode(_ value: String) throws -> String {
        guard let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) else { throw malformed }
        return decoded
    }

    private func decodePrefix(_ value: String) throws -> String {
        var candidate = value
        // A split JSON escape or surrogate pair is at most 12 ASCII scalars.
        for _ in 0...12 {
            if let result = try? decode(candidate + "\"") { return result }
            guard candidate.unicodeScalars.count > 1 else { break }
            candidate.unicodeScalars.removeLast()
        }
        throw malformed
    }

    private var malformed: OrderedStructuredOutputParserError { .malformedOutput }
}
