import Foundation

public enum OrderedStructuredOutputParserError: Error, Equatable {
    case malformedOutput
    case incompleteOutput
}

public struct OrderedStructuredOutputParser: Sendable {
    private let operation: ProviderOperation
    private var buffer = ""
    private var emittedSource = ""
    private var emittedTranslation = ""

    public init(operation: ProviderOperation) {
        self.operation = operation
    }

    public mutating func consume(_ delta: String) throws -> [ProviderStreamEvent] {
        buffer.append(delta)
        let snapshot = try parseSnapshot()
        var events: [ProviderStreamEvent] = []
        let sourceDelta = try incrementalDelta(
            current: snapshot.source,
            emitted: emittedSource
        )
        if !sourceDelta.isEmpty {
            emittedSource = snapshot.source
            events.append(.sourceDelta(sourceDelta))
        }
        let translationDelta = try incrementalDelta(
            current: snapshot.translation,
            emitted: emittedTranslation
        )
        if !translationDelta.isEmpty {
            emittedTranslation = snapshot.translation
            events.append(.translationDelta(translationDelta))
        }
        return events
    }

    private func incrementalDelta(current: String, emitted: String) throws -> String {
        let currentBytes = current.utf8
        let emittedBytes = emitted.utf8
        guard currentBytes.starts(with: emittedBytes) else {
            throw OrderedStructuredOutputParserError.malformedOutput
        }
        return String(
            decoding: currentBytes.dropFirst(emittedBytes.count),
            as: UTF8.self
        )
    }

    public func finish() throws {
        guard try parseSnapshot().objectComplete else {
            throw OrderedStructuredOutputParserError.incompleteOutput
        }
    }

    private func parseSnapshot() throws -> Snapshot {
        var cursor = buffer.startIndex
        skipWhitespace(at: &cursor)
        guard consumeCharacter("{", at: &cursor) else {
            return try incompleteOrMalformed(at: cursor)
        }
        skipWhitespace(at: &cursor)
        let sourceKey = try parseString(at: &cursor)
        guard sourceKey.complete else {
            return Snapshot()
        }
        guard sourceKey.value == "source" else {
            throw OrderedStructuredOutputParserError.malformedOutput
        }
        skipWhitespace(at: &cursor)
        guard consumeCharacter(":", at: &cursor) else {
            return try incompleteOrMalformed(at: cursor)
        }
        skipWhitespace(at: &cursor)
        let source = try parseString(at: &cursor)
        guard source.complete else {
            return Snapshot(source: source.value)
        }
        skipWhitespace(at: &cursor)

        switch operation {
        case .extractText:
            guard consumeCharacter("}", at: &cursor) else {
                return try incompleteOrMalformed(
                    at: cursor,
                    snapshot: Snapshot(source: source.value)
                )
            }
            try requireOnlyTrailingWhitespace(at: cursor)
            return Snapshot(source: source.value, objectComplete: true)
        case .translate:
            guard consumeCharacter(",", at: &cursor) else {
                return try incompleteOrMalformed(
                    at: cursor,
                    snapshot: Snapshot(source: source.value)
                )
            }
            skipWhitespace(at: &cursor)
            let translationKey = try parseString(at: &cursor)
            guard translationKey.complete else {
                return Snapshot(source: source.value)
            }
            guard translationKey.value == "translation" else {
                throw OrderedStructuredOutputParserError.malformedOutput
            }
            skipWhitespace(at: &cursor)
            guard consumeCharacter(":", at: &cursor) else {
                return try incompleteOrMalformed(
                    at: cursor,
                    snapshot: Snapshot(source: source.value)
                )
            }
            skipWhitespace(at: &cursor)
            let translation = try parseString(at: &cursor)
            guard translation.complete else {
                return Snapshot(
                    source: source.value,
                    translation: translation.value
                )
            }
            skipWhitespace(at: &cursor)
            guard consumeCharacter("}", at: &cursor) else {
                return try incompleteOrMalformed(
                    at: cursor,
                    snapshot: Snapshot(
                        source: source.value,
                        translation: translation.value
                    )
                )
            }
            try requireOnlyTrailingWhitespace(at: cursor)
            return Snapshot(
                source: source.value,
                translation: translation.value,
                objectComplete: true
            )
        }
    }

    private func parseString(at cursor: inout String.Index) throws -> ParsedString {
        guard consumeCharacter("\"", at: &cursor) else {
            if cursor == buffer.endIndex {
                return ParsedString()
            }
            throw OrderedStructuredOutputParserError.malformedOutput
        }
        let tokenStart = buffer.index(before: cursor)
        var scan = cursor
        var escaped = false
        while scan < buffer.endIndex {
            let character = buffer[scan]
            if character == "\"" && !escaped {
                let tokenEnd = buffer.index(after: scan)
                let token = String(buffer[tokenStart..<tokenEnd])
                cursor = tokenEnd
                return ParsedString(value: try decodeStringToken(token), complete: true)
            }
            if character == "\\" && !escaped {
                escaped = true
            } else {
                escaped = false
            }
            scan = buffer.index(after: scan)
        }
        let rawContent = String(buffer[cursor...])
        return ParsedString(value: try decodeSafePrefix(rawContent))
    }

    private func decodeSafePrefix(_ rawContent: String) throws -> String {
        var candidate = rawContent
        for _ in 0...12 {
            if let decoded = try? decodeStringToken("\"\(candidate)\"") {
                return decoded
            }
            guard !candidate.isEmpty else {
                break
            }
            candidate.removeLast()
        }
        throw OrderedStructuredOutputParserError.malformedOutput
    }

    private func decodeStringToken(_ token: String) throws -> String {
        do {
            return try JSONDecoder().decode(String.self, from: Data(token.utf8))
        } catch {
            throw OrderedStructuredOutputParserError.malformedOutput
        }
    }

    private func requireOnlyTrailingWhitespace(at start: String.Index) throws {
        var cursor = start
        skipWhitespace(at: &cursor)
        guard cursor == buffer.endIndex else {
            throw OrderedStructuredOutputParserError.malformedOutput
        }
    }

    private func incompleteOrMalformed(
        at cursor: String.Index,
        snapshot: Snapshot = Snapshot()
    ) throws -> Snapshot {
        guard cursor == buffer.endIndex else {
            throw OrderedStructuredOutputParserError.malformedOutput
        }
        return snapshot
    }

    private func consumeCharacter(
        _ expected: Character,
        at cursor: inout String.Index
    ) -> Bool {
        guard cursor < buffer.endIndex, buffer[cursor] == expected else {
            return false
        }
        cursor = buffer.index(after: cursor)
        return true
    }

    private func skipWhitespace(at cursor: inout String.Index) {
        while cursor < buffer.endIndex, buffer[cursor].isWhitespace {
            cursor = buffer.index(after: cursor)
        }
    }
}

private struct ParsedString {
    let value: String
    let complete: Bool

    init(value: String = "", complete: Bool = false) {
        self.value = value
        self.complete = complete
    }
}

private struct Snapshot {
    let source: String
    let translation: String
    let objectComplete: Bool

    init(
        source: String = "",
        translation: String = "",
        objectComplete: Bool = false
    ) {
        self.source = source
        self.translation = translation
        self.objectComplete = objectComplete
    }
}
