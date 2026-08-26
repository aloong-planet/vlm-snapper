import Foundation

public enum ProviderAdapterError: Error, Equatable, Sendable {
    case invalidCredential
    case permissionDenied
    case invalidRequest
    case modelUnavailable
    case rateLimited(retryAfterSeconds: Int?)
    case insufficientBalance
    case providerUnavailable
    case contentBlocked
    case outputTruncated
    case imageInputUnsupported
    case imageTooLarge
    case malformedOutput
    case incompleteResponse
    case firstTextTimeout
    case streamStalled
    case totalTimeout
    case transport
    case cancelled
    case unknown
}

public extension ProviderAdapterError {
    var normalizedCode: String {
        switch self {
        case .invalidCredential: "invalid_credential"
        case .permissionDenied: "permission_denied"
        case .invalidRequest: "invalid_request"
        case .modelUnavailable: "model_unavailable"
        case .rateLimited: "rate_limited"
        case .insufficientBalance: "insufficient_balance"
        case .providerUnavailable: "provider_unavailable"
        case .contentBlocked: "content_blocked"
        case .outputTruncated: "output_truncated"
        case .imageInputUnsupported: "image_input_unsupported"
        case .imageTooLarge: "image_too_large"
        case .malformedOutput: "malformed_output"
        case .incompleteResponse: "incomplete_response"
        case .firstTextTimeout: "first_text_timeout"
        case .streamStalled: "stream_stalled"
        case .totalTimeout: "total_timeout"
        case .transport: "transport"
        case .cancelled: "canceled"
        case .unknown: "unknown"
        }
    }
}
