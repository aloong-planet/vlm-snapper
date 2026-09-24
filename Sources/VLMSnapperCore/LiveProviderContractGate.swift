import CryptoKit
import Dispatch
import Foundation

public protocol LiveProviderContractStreaming: Sendable {
    func stream(
        provider: ProviderID,
        modelID: String,
        apiKey: String,
        originalPNG: Data,
        operation: ProviderOperation
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}

extension ProviderAdapterExecutor: LiveProviderContractStreaming {}

public struct LiveProviderContractConfiguration: Equatable, Sendable {
    public let modelID: String
    public let apiKey: String

    public init(modelID: String, apiKey: String) {
        self.modelID = modelID
        self.apiKey = apiKey
    }
}

public enum LiveProviderContractEnvironment {
    public static func configurations(
        from environment: [String: String]
    ) -> [ProviderID: LiveProviderContractConfiguration] {
        var configurations: [ProviderID: LiveProviderContractConfiguration] = [:]
        for provider in ProviderID.allCases {
            let names = environmentNames(for: provider)
            guard let apiKey = environment[names.apiKey],
                  let modelID = environment[names.model],
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            configurations[provider] = LiveProviderContractConfiguration(
                modelID: modelID,
                apiKey: apiKey
            )
        }
        return configurations
    }

    private static func environmentNames(
        for provider: ProviderID
    ) -> (apiKey: String, model: String) {
        switch provider {
        case .openAI:
            return ("OPENAI_API_KEY", "VLMSNAPPER_OPENAI_MODEL")
        case .gemini:
            return ("GEMINI_API_KEY", "VLMSNAPPER_GEMINI_MODEL")
        case .deepSeek:
            return ("DEEPSEEK_API_KEY", "VLMSNAPPER_DEEPSEEK_MODEL")
        }
    }
}

public enum LiveProviderContractStage: String, Codable, Equatable, Sendable {
    case configuration
    case request
    case validation
}

public enum LiveProviderContractOutcome: String, Codable, Equatable, Sendable {
    case passed
    case blocked
    case failed
}

public enum LiveProviderContractOperation: String, CaseIterable, Codable, Equatable, Sendable {
    case extract
    case translate
}

public struct LiveProviderContractUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, outputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

public struct LiveProviderContractReport: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let operation: LiveProviderContractOperation
    public let modelID: String?
    public let stage: LiveProviderContractStage
    public let outcome: LiveProviderContractOutcome
    public let durationMilliseconds: Int64
    public let status: String
    public let requestID: String?
    public let usage: LiveProviderContractUsage?

    public init(
        provider: ProviderID,
        operation: LiveProviderContractOperation,
        modelID: String?,
        stage: LiveProviderContractStage,
        outcome: LiveProviderContractOutcome,
        durationMilliseconds: Int64,
        status: String,
        requestID: String?,
        usage: LiveProviderContractUsage?
    ) {
        self.provider = provider
        self.operation = operation
        self.modelID = modelID
        self.stage = stage
        self.outcome = outcome
        self.durationMilliseconds = durationMilliseconds
        self.status = status
        self.requestID = requestID
        self.usage = usage
    }
}

public struct LiveProviderContractGate: Sendable {
    private let streamer: any LiveProviderContractStreaming
    private let nowMilliseconds: @Sendable () -> Int64

    public init(
        streamer: any LiveProviderContractStreaming = ProviderAdapterExecutor(),
        nowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        }
    ) {
        self.streamer = streamer
        self.nowMilliseconds = nowMilliseconds
    }

    public func run(
        configurations: [ProviderID: LiveProviderContractConfiguration],
        originalPNG: Data,
        expectedSource: String? = nil,
        providers: [ProviderID] = ProviderID.allCases
    ) async -> [LiveProviderContractReport] {
        var reports: [LiveProviderContractReport] = []
        for provider in ProviderID.allCases where providers.contains(provider) {
            for operation in LiveProviderContractOperation.allCases {
                guard let configuration = configurations[provider],
                      configuration.hasRequiredValues else {
                    reports.append(
                        LiveProviderContractReport(
                            provider: provider,
                            operation: operation,
                            modelID: configurations[provider]?.modelID,
                            stage: .configuration,
                            outcome: .blocked,
                            durationMilliseconds: 0,
                            status: "missing_configuration",
                            requestID: nil,
                            usage: nil
                        )
                    )
                    continue
                }
                reports.append(await run(
                    provider: provider,
                    operation: operation,
                    configuration: configuration,
                    originalPNG: originalPNG,
                    expectedSource: expectedSource
                ))
            }
        }
        return reports
    }

    private func run(
        provider: ProviderID,
        operation: LiveProviderContractOperation,
        configuration: LiveProviderContractConfiguration,
        originalPNG: Data,
        expectedSource: String?
    ) async -> LiveProviderContractReport {
        let startedAt = nowMilliseconds()
        do {
            let providerOperation = operation.providerOperation
            var accumulator = ProviderStreamAccumulator(operation: providerOperation)
            var completedOutput: ProviderCompletedOutput?
            for try await event in streamer.stream(
                provider: provider,
                modelID: configuration.modelID,
                apiKey: configuration.apiKey,
                originalPNG: originalPNG,
                operation: providerOperation
            ) {
                do {
                    if let output = try accumulator.consume(event) {
                        completedOutput = output
                    }
                } catch {
                    return failureReport(
                        provider: provider,
                        operation: operation,
                        modelID: configuration.modelID,
                        stage: .validation,
                        startedAt: startedAt,
                        status: (error as? ProviderStreamContractError) == .incompleteOutput
                            ? "incomplete_response" : "malformed_output"
                    )
                }
            }
            guard let completedOutput else {
                return failureReport(
                    provider: provider,
                    operation: operation,
                    modelID: configuration.modelID,
                    stage: .validation,
                    startedAt: startedAt,
                    status: "incomplete_response"
                )
            }
            if let expectedSource,
               expectedSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || normalizedSource(completedOutput.source, operation: operation) != normalizedText(expectedSource) {
                return failureReport(
                    provider: provider, operation: operation, modelID: configuration.modelID,
                    stage: .validation, startedAt: startedAt, status: "source_mismatch"
                )
            }
            if operation == .translate,
               completedOutput.translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return failureReport(
                    provider: provider, operation: operation, modelID: configuration.modelID,
                    stage: .validation, startedAt: startedAt, status: "empty_translation"
                )
            }
            return LiveProviderContractReport(
                provider: provider,
                operation: operation,
                modelID: configuration.modelID,
                stage: .validation,
                outcome: .passed,
                durationMilliseconds: elapsed(since: startedAt),
                status: "passed",
                requestID: completedOutput.metadata.requestID.map(redactRequestID),
                usage: completedOutput.metadata.usage.map {
                    LiveProviderContractUsage(
                        inputTokens: $0.inputTokens,
                        outputTokens: $0.outputTokens,
                        totalTokens: $0.totalTokens
                    )
                }
            )
        } catch let error as ProviderAdapterError {
            return failureReport(
                provider: provider,
                operation: operation,
                modelID: configuration.modelID,
                stage: .request,
                startedAt: startedAt,
                status: error.normalizedCode
            )
        } catch {
            return failureReport(
                provider: provider,
                operation: operation,
                modelID: configuration.modelID,
                stage: .request,
                startedAt: startedAt,
                status: "unknown"
            )
        }
    }

    private func failureReport(
        provider: ProviderID,
        operation: LiveProviderContractOperation,
        modelID: String,
        stage: LiveProviderContractStage,
        startedAt: Int64,
        status: String
    ) -> LiveProviderContractReport {
        LiveProviderContractReport(
            provider: provider,
            operation: operation,
            modelID: modelID,
            stage: stage,
            outcome: .failed,
            durationMilliseconds: elapsed(since: startedAt),
            status: status,
            requestID: nil,
            usage: nil
        )
    }

    private func elapsed(since startedAt: Int64) -> Int64 {
        max(0, nowMilliseconds() - startedAt)
    }

    private func redactRequestID(_ requestID: String) -> String {
        let digest = SHA256.hash(data: Data(requestID.utf8))
        return "sha256:" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func normalizedSource(_ source: String, operation: LiveProviderContractOperation) -> String {
        // Extraction permits Markdown styling; translation segments carry plain text.
        guard operation == .extract,
              let text = try? AttributedString(markdown: source, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
              )) else {
            return normalizedText(source)
        }
        return normalizedText(String(text.characters))
    }
}

private extension LiveProviderContractOperation {
    var providerOperation: ProviderOperation {
        switch self {
        case .extract:
            return .extractText
        case .translate:
            return .translate(targetLanguage: "Simplified Chinese")
        }
    }
}

private extension LiveProviderContractConfiguration {
    var hasRequiredValues: Bool {
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
