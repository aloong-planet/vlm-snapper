import Foundation

public enum ServerSentEventDecoderError: Error, Equatable {
    case invalidUTF8
    case incompleteFrame
}

public struct ServerSentEventDecoder: Sendable {
    private var buffer = Data()
    private var dataLines: [String] = []

    public init() {}

    public mutating func consume<Bytes: DataProtocol>(
        _ bytes: Bytes
    ) throws -> [String] {
        buffer.append(contentsOf: bytes)
        var payloads: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var lineData = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if lineData.last == 0x0D {
                lineData.removeLast()
            }
            guard let line = String(data: lineData, encoding: .utf8) else {
                throw ServerSentEventDecoderError.invalidUTF8
            }
            if line.isEmpty {
                if !dataLines.isEmpty {
                    payloads.append(dataLines.joined(separator: "\n"))
                    dataLines.removeAll(keepingCapacity: true)
                }
                continue
            }
            guard !line.hasPrefix(":") else {
                continue
            }
            let field: Substring
            let value: Substring
            if let colon = line.firstIndex(of: ":") {
                field = line[..<colon]
                var valueStart = line.index(after: colon)
                if valueStart < line.endIndex, line[valueStart] == " " {
                    valueStart = line.index(after: valueStart)
                }
                value = line[valueStart...]
            } else {
                field = Substring(line)
                value = ""
            }
            if field == "data" {
                dataLines.append(String(value))
            }
        }
        return payloads
    }

    public func finish() throws {
        guard buffer.isEmpty, dataLines.isEmpty else {
            throw ServerSentEventDecoderError.incompleteFrame
        }
    }
}
