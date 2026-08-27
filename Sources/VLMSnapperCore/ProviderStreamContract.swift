import Foundation

public enum ProviderOperation: Equatable, Sendable {
    case extractText
    case translate(targetLanguage: String)
}

public struct ProviderTokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct ProviderResponseMetadata: Equatable, Sendable {
    public let requestID: String?
    public let usage: ProviderTokenUsage?

    public init(requestID: String?, usage: ProviderTokenUsage?) {
        self.requestID = requestID
        self.usage = usage
    }
}

public enum ProviderStreamEvent: Equatable, Sendable {
    case sourceDelta(String)
    case translationDelta(String)
    case metadata(ProviderResponseMetadata)
    case completed
}

public struct ProviderCompletedOutput: Equatable, Sendable {
    public let source: String
    public let translation: String?
    public let metadata: ProviderResponseMetadata

    public init(
        source: String,
        translation: String?,
        metadata: ProviderResponseMetadata
    ) {
        self.source = source
        self.translation = translation
        self.metadata = metadata
    }
}

public enum ProviderStreamContractError: Error, Equatable {
    case invalidEventOrder
    case translationNotAllowed
    case incompleteOutput
}

public struct ProviderStreamAccumulator: Sendable {
    private enum Phase: Equatable, Sendable {
        case source
        case translation
        case metadata
        case completed
    }

    private let operation: ProviderOperation
    private var phase: Phase = .source
    private var source = ""
    private var translation = ""
    private var metadata: ProviderResponseMetadata?

    public init(operation: ProviderOperation) {
        self.operation = operation
    }

    public mutating func consume(
        _ event: ProviderStreamEvent
    ) throws -> ProviderCompletedOutput? {
        switch event {
        case let .sourceDelta(delta):
            guard phase == .source else {
                throw ProviderStreamContractError.invalidEventOrder
            }
            source.append(delta)
            return nil
        case let .translationDelta(delta):
            guard case .translate = operation else {
                throw ProviderStreamContractError.translationNotAllowed
            }
            guard phase == .source || phase == .translation else {
                throw ProviderStreamContractError.invalidEventOrder
            }
            phase = .translation
            translation.append(delta)
            return nil
        case let .metadata(responseMetadata):
            switch operation {
            case .extractText:
                guard phase == .source else {
                    throw ProviderStreamContractError.invalidEventOrder
                }
            case .translate:
                guard phase == .translation else {
                    throw ProviderStreamContractError.invalidEventOrder
                }
            }
            phase = .metadata
            metadata = responseMetadata
            return nil
        case .completed:
            guard phase == .metadata, let metadata, !source.isEmpty else {
                throw ProviderStreamContractError.incompleteOutput
            }
            if case .translate = operation, translation.isEmpty {
                throw ProviderStreamContractError.incompleteOutput
            }
            phase = .completed
            return ProviderCompletedOutput(
                source: source,
                translation: operation.translationValue(translation),
                metadata: metadata
            )
        }
    }
}

private extension ProviderOperation {
    func translationValue(_ value: String) -> String? {
        switch self {
        case .extractText:
            return nil
        case .translate:
            return value
        }
    }
}
