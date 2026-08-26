import Foundation

enum VLMSnapperStrings {
    static var extract: String { localized("operation.extract") }
    static var translate: String { localized("operation.translate") }
    static var operationSelector: String { localized("operation.selector") }
    static var cancel: String { localized("action.cancel") }
    static var start: String { localized("action.start") }
    static var rerun: String { localized("action.rerun") }
    static var retrySave: String { localized("action.retrySave") }
    static var copy: String { localized("action.copy") }
    static var originalScreenshot: String { localized("result.originalScreenshot") }
    static var result: String { localized("result.title") }
    static var neverStarted: String { localized("result.neverStarted") }
    static var preparing: String { localized("result.preparing") }
    static var streaming: String { localized("result.streaming") }
    static var failed: String { localized("result.failed") }
    static var canceled: String { localized("result.canceled") }
    static var persistenceFailed: String { localized("result.persistenceFailed") }

    static func failureMessage(code: String) -> String {
        let key = switch code {
        case "invalid_credential": "failure.invalidCredential"
        case "model_unavailable": "failure.modelUnavailable"
        case "rate_limited": "failure.rateLimited"
        case "insufficient_balance": "failure.insufficientBalance"
        case "provider_unavailable": "failure.providerUnavailable"
        case "content_blocked": "failure.contentBlocked"
        case "image_input_unsupported": "failure.imageUnsupported"
        case "image_too_large": "failure.imageTooLarge"
        case "first_text_timeout", "stream_stalled", "total_timeout":
            "failure.timeout"
        case "transport": "failure.transport"
        case "malformed_output", "incomplete_response": "failure.incomplete"
        default: "failure.unknown"
        }
        return localized(key)
    }

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }
}
