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
