import Foundation

public struct ProviderHTTPErrorNormalizer: Sendable {
    public init() {}

    public func normalize(
        provider: ProviderID,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) -> ProviderAdapterError {
        let evidence = bodyEvidence(body)
        if containsAny(evidence, ["insufficient_quota", "insufficient balance", "balance not enough"]) {
            return .insufficientBalance
        }
        if containsAll(evidence, ["image", "large"]) ||
            containsAll(evidence, ["image", "maximum", "size"]) ||
            containsAny(evidence, ["image_too_large", "payload too large"]) {
            return .imageTooLarge
        }
        if containsAll(evidence, ["image", "support"]) ||
            containsAny(evidence, ["image_input_unsupported", "unsupported image input"]) {
            return .imageInputUnsupported
        }
        if containsAny(evidence, ["content_filter", "safety", "blocked"]), statusCode < 500 {
            return .contentBlocked
        }
        if containsAll(evidence, ["model", "not found"]) {
            return .modelUnavailable
        }

        switch statusCode {
        case 400, 422:
            return .invalidRequest
        case 401:
            return .invalidCredential
        case 402:
            return .insufficientBalance
        case 403:
            return .permissionDenied
        case 404:
            return .modelUnavailable
        case 413:
            return .imageTooLarge
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfterSeconds(headers))
        case 500..<600:
            return .providerUnavailable
        default:
            return .unknown
        }
    }

    private func retryAfterSeconds(_ headers: [String: String]) -> Int? {
        let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
        return value.flatMap(Int.init).map { min(max($0, 60), 300) }
    }

    private func bodyEvidence(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            return String(data: body, encoding: .utf8)?.lowercased() ?? ""
        }
        var strings: [String] = []
        collectStrings(from: object, into: &strings)
        return strings.joined(separator: " ").lowercased()
    }

    private func collectStrings(from value: Any, into strings: inout [String]) {
        switch value {
        case let string as String:
            strings.append(string)
        case let dictionary as [String: Any]:
            for (key, nestedValue) in dictionary {
                strings.append(key)
                collectStrings(from: nestedValue, into: &strings)
            }
        case let array as [Any]:
            for nestedValue in array {
                collectStrings(from: nestedValue, into: &strings)
            }
        default:
            break
        }
    }

    private func containsAny(_ evidence: String, _ terms: [String]) -> Bool {
        terms.contains { evidence.contains($0) }
    }

    private func containsAll(_ evidence: String, _ terms: [String]) -> Bool {
        terms.allSatisfy { evidence.contains($0) }
    }
}
