import Foundation
import VLMSnapperCore

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
    static var onboardingTitle: String { localized("onboarding.title") }
    static var onboardingSubtitle: String { localized("onboarding.subtitle") }
    static var permissionTitle: String { localized("onboarding.permission.title") }
    static var providerTitle: String { localized("onboarding.provider.title") }
    static var privacyTitle: String { localized("onboarding.privacy.title") }
    static var privacySummary: String { localized("onboarding.privacy.summary") }
    static var configure: String { localized("action.configure") }
    static var modify: String { localized("action.modify") }
    static var continueSetup: String { localized("action.continueSetup") }
    static var finishLater: String { localized("action.finishLater") }
    static var startUsing: String { localized("action.startUsing") }
    static var viewDetails: String { localized("action.viewDetails") }
    static var done: String { localized("action.done") }
    static var validate: String { localized("action.validate") }
    static var refresh: String { localized("action.refresh") }
    static var close: String { localized("action.close") }
    static var openSettings: String { localized("action.openSettings") }
    static var restart: String { localized("action.restart") }
    static var providerSetupTitle: String { localized("providerSetup.title") }
    static var providerSetupSubtitle: String { localized("providerSetup.subtitle") }
    static var apiKey: String { localized("providerSetup.apiKey") }
    static var currentModel: String { localized("providerSetup.currentModel") }
    static var chooseModel: String { localized("providerSetup.chooseModel") }
    static var modelListHint: String { localized("providerSetup.modelListHint") }
    static var visionValidationHint: String { localized("providerSetup.visionValidationHint") }
    static var modelPending: String { localized("providerSetup.pendingModel") }
    static var providerSection: String { localized("providerSetup.providerSection") }
    static var officialEndpoint: String { localized("providerSetup.officialEndpoint") }
    static var notConfigured: String { localized("providerSetup.notConfigured") }
    static var validating: String { localized("providerSetup.validating") }
    static var configured: String { localized("providerSetup.configured") }
    static var providerReadOnly: String { localized("providerSetup.readOnly") }
    static var permissionRecoveryTitle: String { localized("permissionRecovery.title") }
    static var permissionRecoveryDenied: String { localized("permissionRecovery.unavailable") }
    static var permissionRecoveryInitial: String { localized("permissionRecovery.initial") }
    static var permissionRecoveryRestart: String { localized("permissionRecovery.restart") }
    static var permissionReady: String { localized("permissionRecovery.ready") }
    static var permissionBlocker: String { localized("onboarding.blocker.permission") }
    static var providerBlocker: String { localized("onboarding.blocker.provider") }
    static var menuCapture: String { localized("menu.capture") }
    static var menuRecent: String { localized("menu.recent") }
    static var menuHistory: String { localized("menu.history") }
    static var menuSettings: String { localized("menu.settings") }
    static var menuCheckUpdates: String { localized("menu.checkUpdates") }
    static var menuQuit: String { localized("menu.quit") }
    static var privacyDetailsTitle: String { localized("privacy.title") }
    static var privacyUploadTitle: String { localized("privacy.upload.title") }
    static var privacyUploadBody: String { localized("privacy.upload.body") }
    static var privacyStorageTitle: String { localized("privacy.storage.title") }
    static var privacyStorageBody: String { localized("privacy.storage.body") }
    static var privacyRetentionTitle: String { localized("privacy.retention.title") }
    static var privacyRetentionBody: String { localized("privacy.retention.body") }
    static var privacyBackupTitle: String { localized("privacy.backup.title") }
    static var privacyBackupBody: String { localized("privacy.backup.body") }
    static var noRecentItems: String { localized("menu.noRecentItems") }
    static var historyAll: String { localized("history.filter.all") }
    static var historySearch: String { localized("history.search") }
    static var historyEmptyTitle: String { localized("history.empty.title") }
    static var historyEmptyBody: String { localized("history.empty.body") }
    static var historyPinned: String { localized("history.pinned") }
    static var historyProviderSettings: String { localized("history.providerSettings") }
    static var historyGeneralSettings: String { localized("history.generalSettings") }
    static var historyOriginal: String { localized("history.original") }
    static var historyTranslation: String { localized("history.translation") }
    static var historyScreenshotUnavailable: String { localized("history.screenshotUnavailable") }
    static var historyFirstTextLatency: String { localized("history.firstTextLatency") }
    static var historyTotalLatency: String { localized("history.totalLatency") }
    static var historyTokenUsage: String { localized("history.tokenUsage") }
    static var historyUnavailable: String { localized("history.unavailable") }
    static var historyDelete: String { localized("history.delete") }
    static var historyClear: String { localized("history.clear") }
    static var historyRetryCleanup: String { localized("history.retryCleanup") }
    static var historyCleanupFailures: String { localized("history.cleanupFailures") }
    static var historyRetention: String { localized("history.retention") }
    static var historyRetentionHint: String { localized("history.retentionHint") }
    static var historyDeleteConfirm: String { localized("history.deleteConfirm") }
    static var historyClearConfirm: String { localized("history.clearConfirm") }
    static var historyClearUnpinned: String { localized("history.clearUnpinned") }
    static var historyClearIncludingPinned: String { localized("history.clearIncludingPinned") }
    static var historyTokenUsageFormat: String { localized("history.tokenUsageFormat") }
    static var historyRetentionDaysFormat: String { localized("history.retentionDaysFormat") }
    static var generalSettingsSubtitle: String { localized("settings.general.subtitle") }
    static var languageTitle: String { localized("settings.language.title") }
    static var languageHint: String { localized("settings.language.hint") }
    static var languageRestartRequired: String { localized("settings.language.restartRequired") }
    static var languageRestartHint: String { localized("settings.language.restartHint") }
    static var languageSystem: String { localized("settings.language.system") }
    static var languageSimplifiedChinese: String { localized("settings.language.zhHans") }
    static var languageEnglish: String { localized("settings.language.en") }
    static var loginItemTitle: String { localized("settings.loginItem.title") }
    static var loginItemHint: String { localized("settings.loginItem.hint") }
    static var loginItemApproval: String { localized("settings.loginItem.approval") }
    static var updateSection: String { localized("update.section") }
    static var updateAutomaticChecks: String { localized("update.automaticChecks") }
    static var updateAutomaticChecksHint: String { localized("update.automaticChecksHint") }
    static var updateCurrent: String { localized("update.current") }
    static var updateChecking: String { localized("update.checking") }
    static var updateCheck: String { localized("update.check") }
    static var updateRetry: String { localized("update.retry") }
    static var updateDownload: String { localized("update.download") }
    static var updateView: String { localized("update.view") }
    static var updateInstallNow: String { localized("update.installNow") }
    static var updateAvailableTitleFormat: String { localized("update.availableTitleFormat") }
    static var updateDownloadingTitleFormat: String { localized("update.downloadingTitleFormat") }
    static var updateReadyTitleFormat: String { localized("update.readyTitleFormat") }
    static var updateAvailableMenuDetail: String { localized("update.availableMenuDetail") }
    static var updateDownloadingMenuDetail: String { localized("update.downloadingMenuDetail") }
    static var updateReadyMenuDetail: String { localized("update.readyMenuDetail") }
    static var updateAvailableDetail: String { localized("update.availableDetail") }
    static var updateDownloadingDetail: String { localized("update.downloadingDetail") }
    static var updateReadyDetail: String { localized("update.readyDetail") }
    static var updateFailedTitle: String { localized("update.failedTitle") }
    static var updateFailedDetail: String { localized("update.failedDetail") }
    static var diagnosticsSection: String { localized("diagnostics.section") }
    static var diagnosticsTitle: String { localized("diagnostics.title") }
    static var diagnosticsHint: String { localized("diagnostics.hint") }
    static var diagnosticsExport: String { localized("diagnostics.export") }

    static func providerName(_ provider: ProviderID) -> String {
        switch provider {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }

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

    static func localized(_ key: String) -> String {
        LocalizationBundleStore.shared.localized(key)
    }
}
