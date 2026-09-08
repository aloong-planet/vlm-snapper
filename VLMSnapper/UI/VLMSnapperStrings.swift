import Foundation
import VLMSnapperCore

enum VLMSnapperStrings {
    static var extract: String { localized("operation.extract") }
    static var translate: String { localized("operation.translate") }
    static var operationSelector: String { localized("operation.selector") }
    static var targetLanguageSearch: String { localized("operation.targetLanguageSearch") }
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
    static var discardUnsavedTitle: String { localized("result.discardUnsaved.title") }
    static var discardUnsavedBody: String { localized("result.discardUnsaved.body") }
    static var discardUnsavedAction: String { localized("result.discardUnsaved.action") }
    static var captureFailedTitle: String { localized("capture.failed.title") }
    static var captureFailedBody: String { localized("capture.failed.body") }
    static var retry: String { localized("action.retry") }
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
    static var refreshingModels: String { localized("providerSetup.refreshingModels") }
    static var retryModelRefresh: String { localized("providerSetup.retryModelRefresh") }
    static var modelRefreshFailureHint: String { localized("providerSetup.modelRefreshFailureHint") }
    static var close: String { localized("action.close") }
    static var openSettings: String { localized("action.openSettings") }
    static var restart: String { localized("action.restart") }
    static var providerSetupSubtitle: String { localized("providerSetup.subtitle") }
    static var apiKey: String { localized("providerSetup.apiKey") }
    static var currentModel: String { localized("providerSetup.currentModel") }
    static var chooseModel: String { localized("providerSetup.chooseModel") }
    static var visionValidationHint: String { localized("providerSetup.visionValidationHint") }
    static var modelPending: String { localized("providerSetup.pendingModel") }
    static var notConfigured: String { localized("providerSetup.notConfigured") }
    static var validating: String { localized("providerSetup.validating") }
    static var recovering: String { localized("providerSetup.recovering") }
    static var providerStorageFailure: String { localized("providerSetup.storageFailure") }
    static var providerStorageReadFailure: String { localized("providerSetup.storageReadFailure") }
    static var configured: String { localized("providerSetup.configured") }
    static var providerAvailable: String { localized("providerSetup.available") }
    static var providerSetupRequired: String { localized("providerSetup.setupRequired") }
    static var providerReadOnly: String { localized("providerSetup.readOnly") }
    static var apiKeyPlaceholder: String { localized("providerSetup.apiKeyPlaceholder") }
    static var clearAPIKey: String { localized("providerSetup.clearAPIKey") }
    static var showAPIKey: String { localized("providerSetup.showAPIKey") }
    static var hideAPIKey: String { localized("providerSetup.hideAPIKey") }
    static var providerPendingValidation: String { localized("providerSetup.pendingValidation") }
    static var providerNewKeyPending: String { localized("providerSetup.newKeyPending") }
    static var providerRetryValidation: String { localized("providerSetup.retryValidation") }
    static var providerEnterKey: String { localized("providerSetup.enterKey") }
    static var providerKeyContainsNewline: String { localized("providerSetup.keyContainsNewline") }
    static var providerKeyTooLong: String { localized("providerSetup.keyTooLong") }
    static var providerReplacementHint: String { localized("providerSetup.replacementHint") }
    static var providerCurrent: String { localized("providerSetup.current") }
    static var providerSetCurrent: String { localized("providerSetup.setCurrent") }
    static var providerRemove: String { localized("providerSetup.remove") }
    static var providerRemoveConfirmation: String { localized("providerSetup.removeConfirmation") }
    static var providerCurrentDetailFormat: String { localized("providerSetup.currentDetailFormat") }
    static var permissionRecoveryTitle: String { localized("permissionRecovery.title") }
    static var permissionRecoveryDenied: String { localized("permissionRecovery.unavailable") }
    static var permissionRecoveryInitial: String { localized("permissionRecovery.initial") }
    static var permissionRecoveryRestart: String { localized("permissionRecovery.restart") }
    static var permissionReady: String { localized("permissionRecovery.ready") }
    static var permissionRecoverySubtitle: String { localized("permissionRecovery.subtitle") }
    static var permissionRecoveryBlockedTitle: String { localized("permissionRecovery.blockedTitle") }
    static var permissionRecoveryRestartTitle: String { localized("permissionRecovery.restartTitle") }
    static var permissionRecoveryRestartSubtitle: String { localized("permissionRecovery.restartSubtitle") }
    static var permissionRecoveryNotGrantedTitle: String { localized("permissionRecovery.notGrantedTitle") }
    static var permissionRecoveryRevokedTitle: String { localized("permissionRecovery.revokedTitle") }
    static var permissionRecoveryEnabledTitle: String { localized("permissionRecovery.enabledTitle") }
    static var permissionRecoveryStepOne: String { localized("permissionRecovery.stepOne") }
    static var permissionRecoveryStepTwo: String { localized("permissionRecovery.stepTwo") }
    static var permissionRecoveryLaterNote: String { localized("permissionRecovery.laterNote") }
    static var permissionRecoveryRestartNote: String { localized("permissionRecovery.restartNote") }
    static var permissionBlocker: String { localized("onboarding.blocker.permission") }
    static var providerBlocker: String { localized("onboarding.blocker.provider") }
    static var menuCapture: String { localized("menu.capture") }
    static var menuRecent: String { localized("menu.recent") }
    static var menuHistory: String { localized("menu.history") }
    static var menuSettings: String { localized("menu.settings") }
    static var menuCheckUpdates: String { localized("menu.checkUpdates") }
    static var menuQuit: String { localized("menu.quit") }
    static var menuFile: String { localized("applicationMenu.file") }
    static var menuEdit: String { localized("applicationMenu.edit") }
    static var menuWindow: String { localized("applicationMenu.window") }
    static var menuHelp: String { localized("applicationMenu.help") }
    static var menuAboutFormat: String { localized("applicationMenu.aboutFormat") }
    static var menuHideFormat: String { localized("applicationMenu.hideFormat") }
    static var menuHideOthers: String { localized("applicationMenu.hideOthers") }
    static var menuShowAll: String { localized("applicationMenu.showAll") }
    static var menuCloseWindow: String { localized("applicationMenu.closeWindow") }
    static var menuMinimize: String { localized("applicationMenu.minimize") }
    static var menuZoom: String { localized("applicationMenu.zoom") }
    static var menuBringAllToFront: String { localized("applicationMenu.bringAllToFront") }
    static var editUndo: String { localized("edit.undo") }
    static var editRedo: String { localized("edit.redo") }
    static var editCut: String { localized("edit.cut") }
    static var editCopy: String { localized("edit.copy") }
    static var editPaste: String { localized("edit.paste") }
    static var editPasteAndMatchStyle: String { localized("edit.pasteAndMatchStyle") }
    static var editDelete: String { localized("edit.delete") }
    static var editSelectAll: String { localized("edit.selectAll") }
    static var editFind: String { localized("edit.find") }
    static var editFindPanel: String { localized("edit.findPanel") }
    static var editFindNext: String { localized("edit.findNext") }
    static var editFindPrevious: String { localized("edit.findPrevious") }
    static var editUseSelectionForFind: String { localized("edit.useSelectionForFind") }
    static var editJumpToSelection: String { localized("edit.jumpToSelection") }
    static var editSpellingAndGrammar: String { localized("edit.spellingAndGrammar") }
    static var editShowSpellingAndGrammar: String { localized("edit.showSpellingAndGrammar") }
    static var editCheckDocumentNow: String { localized("edit.checkDocumentNow") }
    static var editCheckSpellingWhileTyping: String { localized("edit.checkSpellingWhileTyping") }
    static var editCheckGrammarWithSpelling: String { localized("edit.checkGrammarWithSpelling") }
    static var editCorrectSpellingAutomatically: String { localized("edit.correctSpellingAutomatically") }
    static var editSubstitutions: String { localized("edit.substitutions") }
    static var editShowSubstitutions: String { localized("edit.showSubstitutions") }
    static var editSmartCopyPaste: String { localized("edit.smartCopyPaste") }
    static var editSmartQuotes: String { localized("edit.smartQuotes") }
    static var editSmartDashes: String { localized("edit.smartDashes") }
    static var editSmartLinks: String { localized("edit.smartLinks") }
    static var editDataDetectors: String { localized("edit.dataDetectors") }
    static var editTextReplacement: String { localized("edit.textReplacement") }
    static var editTransformations: String { localized("edit.transformations") }
    static var editMakeUpperCase: String { localized("edit.makeUpperCase") }
    static var editMakeLowerCase: String { localized("edit.makeLowerCase") }
    static var editCapitalize: String { localized("edit.capitalize") }
    static var editSpeech: String { localized("edit.speech") }
    static var editStartSpeaking: String { localized("edit.startSpeaking") }
    static var editStopSpeaking: String { localized("edit.stopSpeaking") }
    static var editStartDictation: String { localized("edit.startDictation") }
    static var editEmojiAndSymbols: String { localized("edit.emojiAndSymbols") }
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
    static var menuProviderRequestFailed: String { localized("menu.providerRequestFailed") }
    static var menuSetupRequired: String { localized("menu.setupRequired") }
    static var menuProviderAvailableFormat: String { localized("menu.providerAvailableFormat") }
    static var menuProviderNeedsModelFormat: String { localized("menu.providerNeedsModelFormat") }
    static var menuStatusActive: String { localized("menu.status.active") }
    static var menuStatusSucceeded: String { localized("menu.status.succeeded") }
    static var menuStatusFailed: String { localized("menu.status.failed") }
    static var menuStatusCanceled: String { localized("menu.status.canceled") }
    static var menuTimeNow: String { localized("menu.time.now") }
    static var menuTimeMinutesFormat: String { localized("menu.time.minutesFormat") }
    static var menuTimeHoursFormat: String { localized("menu.time.hoursFormat") }
    static var menuTimeDaysFormat: String { localized("menu.time.daysFormat") }
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
    static var historyRetentionShorteningConfirm: String {
        localized("history.retentionShorteningConfirm")
    }
    static var historyRetentionShorteningAction: String {
        localized("history.retentionShorteningAction")
    }
    static var generalSettingsSubtitle: String { localized("settings.general.subtitle") }
    static var languageTitle: String { localized("settings.language.title") }
    static var languageHint: String { localized("settings.language.hint") }
    static var languageRestartRequired: String { localized("settings.language.restartRequired") }
    static var languageRestartHint: String { localized("settings.language.restartHint") }
    static var languageSystem: String { localized("settings.language.system") }
    static var languageSimplifiedChinese: String { localized("settings.language.zhHans") }
    static var languageEnglish: String { localized("settings.language.en") }
    static var shortcutTitle: String { localized("settings.shortcut.title") }
    static var shortcutHint: String { localized("settings.shortcut.hint") }
    static var shortcutRecording: String { localized("settings.shortcut.recording") }
    static var shortcutConflict: String { localized("settings.shortcut.conflict") }
    static var shortcutInvalid: String { localized("settings.shortcut.invalid") }
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
        case "local_storage": "failure.localStorage"
        case "malformed_output", "incomplete_response": "failure.incomplete"
        default: "failure.unknown"
        }
        return localized(key)
    }

    static func localized(_ key: String) -> String {
        LocalizationBundleStore.shared.localized(key)
    }
}
