import AppKit
import Foundation
import SwiftUI
import VLMSnapperCore
import VLMSnapperSparkle
import VLMSnapperUI

@MainActor
final class VLMSnapperApplicationModel: ObservableObject {
    @Published var apiKey = ""
    @Published var pendingModelID: String?
    @Published var selectedOperation: WorkspaceOperationKind = .extract
    @Published var selectedTargetLanguageCode = "zh-Hans"

    private(set) var permission: ScreenCapturePermissionReadiness = .notRequested
    private(set) var providerReadiness: ProviderReadiness = .missing
    private(set) var providerConfigurations: [ProviderID: ProviderConfiguration] = [:]
    private(set) var providerSnapshot = ProviderSetupSnapshot(
        selectedProvider: .deepSeek,
        availableModelIDs: [],
        selectedModelID: nil,
        phase: .awaitingValidation,
        failure: nil
    )
    private(set) var updateState: UpdateLifecycleState = .idle
    private(set) var historyRecords: [HistoryRecord] = []
    private(set) var selectedHistoryRecordID: UUID?
    private(set) var selectedHistoryImage: NSImage?
    private(set) var cleanupFailureCount = 0
    private(set) var retention: HistoryRetentionPeriod = .thirtyDays
    private(set) var settings = GeneralSettingsSnapshot()
    private(set) var captureShortcut = GlobalShortcut.defaultCapture
    private(set) var shortcutFailure: ShortcutSettingsFailure?

    var onSnapshotChange: (@MainActor () -> Void)?
    var onNavigate: (@MainActor (ManagementCenterDestination) -> Void)?
    var onShowOnboarding: (@MainActor () -> Void)?

    private let defaults: UserDefaults
    private let shortcutStore: UserDefaultsGlobalShortcutStore
    private let languageStore: UserDefaultsApplicationLanguageStore
    private let providerCoordinator: ProviderConfigurationCoordinator
    private let providerSession: ProviderSetupSession
    private let permissionCoordinator: ScreenCapturePermissionCoordinator
    private let loginCoordinator: LoginItemCoordinator
    private let historyStore: SQLiteHistoryStore
    private let diagnosticStore: DiagnosticLogStore
    private let screenshotStore: FileSystemScreenshotStore
    private let providerStreamer: ProviderPreparedOperationStreamer
    private let historyDeletionCoordinator: HistoryDeletionCoordinator
    private let historyCleanupCoordinator: HistoryCleanupCoordinator
    private let retentionSettingsSession: RetentionSettingsSession
    private let cleanupScheduler: AutomaticHistoryCleanupScheduler
    private let operationGate = ActiveOperationGate()
    private let captureCoordinator: CaptureFreezeCoordinator
    private let captureOverlayController = FrozenCaptureOverlayController()
    private let captureToolbarController = CaptureToolbarPanelController()
    private var captureSelectionSession: CaptureSelectionSession?
    private var captureGeneration: UUID?
    private var workspaceSession: OperationWorkspaceSession?
    private var workspaceSnapshot = OperationWorkspaceSnapshot(
        selectedOperation: .extract,
        extract: WorkspaceOperationSlot(),
        translate: WorkspaceOperationSlot()
    )
    private var originalImage: NSImage?
    private var shortcutCoordinator: GlobalShortcutCoordinator?
    private var cleanupTask: Task<Void, Never>?
    private lazy var resultController = ResultWorkspaceWindowController(
        onClose: { [weak self] in
            await self?.closeWorkspace() ?? .discard
        },
        onDiscardUnsaved: { [weak self] in
            await self?.discardUnsavedWorkspace()
        }
    )
    private lazy var updateDriver = SparkleUpdateDriver { [weak self] event in
        await self?.receiveUpdateEvent(event)
    }
    private lazy var updateCoordinator = UpdateLifecycleCoordinator(driver: updateDriver)

    init(
        applicationSupportRoot: URL,
        languageStore: UserDefaultsApplicationLanguageStore,
        defaults: UserDefaults = .standard
    ) throws {
        self.defaults = defaults
        shortcutStore = UserDefaultsGlobalShortcutStore(defaults: defaults)
        self.languageStore = languageStore
        let credentialStore = AppleKeychainProviderCredentialStore()
        let metadataStore = FileProviderMetadataStore(
            fileURL: applicationSupportRoot.appendingPathComponent("providers.json")
        )
        providerCoordinator = ProviderConfigurationCoordinator(
            modelLister: OfficialProviderModelLister(),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )
        providerSession = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: providerCoordinator
        )
        permissionCoordinator = ScreenCapturePermissionCoordinator(
            authorizer: CoreGraphicsScreenCapturePermissionChecker(),
            requestHistory: UserDefaultsPermissionRequestHistoryStore()
        )
        loginCoordinator = LoginItemCoordinator(
            service: SMAppServiceLoginItemAdapter(),
            preference: UserDefaultsLoginItemPreferenceStore(defaults: defaults)
        )
        historyStore = try SQLiteHistoryStore(
            databaseURL: applicationSupportRoot.appendingPathComponent("history.sqlite")
        )
        diagnosticStore = DiagnosticLogStore(
            directory: applicationSupportRoot.appendingPathComponent(
                "Diagnostics",
                isDirectory: true
            )
        )
        screenshotStore = FileSystemScreenshotStore(
            rootDirectory: try ApplicationDirectories.screenshotRoot()
        )
        providerStreamer = ProviderPreparedOperationStreamer(
            credentialStore: credentialStore
        )
        let deletionCoordinator = HistoryDeletionCoordinator(
            historyStore: historyStore,
            screenshotStore: screenshotStore
        )
        historyDeletionCoordinator = deletionCoordinator
        let cleanupCoordinator = HistoryCleanupCoordinator(
            historyStore: historyStore,
            deletionCoordinator: deletionCoordinator
        )
        historyCleanupCoordinator = cleanupCoordinator
        retentionSettingsSession = RetentionSettingsSession(
            preferences: UserDefaultsRetentionPreferenceStore(),
            cleanup: cleanupCoordinator
        )
        cleanupScheduler = AutomaticHistoryCleanupScheduler(cleanup: cleanupCoordinator)
        captureCoordinator = CaptureFreezeCoordinator(
            permissionChecker: CoreGraphicsScreenCapturePermissionChecker(),
            capturer: ScreenCaptureKitFrozenDisplayCapturer(),
            cropper: SRGBPNGCropper()
        )
        retention = HistoryRetentionPeriod(
            rawValue: defaults.integer(forKey: "historyRetentionDays")
        ) ?? .thirtyDays
        if let savedLanguage = defaults.string(forKey: "targetLanguageCode"),
           TargetLanguageCatalog.standard.contains(savedLanguage) {
            selectedTargetLanguageCode = savedLanguage
        }
    }

    var hasFinishedOnboarding: Bool {
        defaults.bool(forKey: "hasFinishedOnboarding")
    }

    func start() async throws {
        _ = try? await diagnosticStore.removeExpiredLogs()
        try? await diagnosticStore.record(
            DiagnosticEvent(timestamp: Date(), stage: .startup)
        )
        _ = try await historyStore.recoverUnfinishedOperations()
        await cleanupScheduler.runAtStartup(retention: retention, now: Date())
        historyRecords = try await historyStore.history(matching: HistoryQuery())
        permission = try await permissionCoordinator.refreshStatus()
        await providerSession.load()
        providerSnapshot = await providerSession.snapshot()
        try await refreshProviderReadiness()
        let loginState = try await loginCoordinator.configureAtPrimaryLaunch()
        let language = await languageStore.load()
        if defaults.string(forKey: "targetLanguageCode") == nil {
            selectedTargetLanguageCode = defaultTargetLanguage(for: language)
            defaults.set(selectedTargetLanguageCode, forKey: "targetLanguageCode")
        }
        settings = GeneralSettingsSnapshot(
            language: language,
            loginItemEnabled: loginState != .disabled,
            loginItemState: loginState,
            automaticallyChecksForUpdates: defaults.object(
                forKey: "automaticallyChecksForUpdates"
            ) as? Bool ?? true,
            updateState: updateState,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
        try await updateCoordinator.start(
            automaticallyChecks: settings.automaticallyChecksForUpdates
        )
        let shortcut = GlobalShortcutCoordinator(
            backend: try CarbonGlobalShortcutBackend()
        ) { [weak self] in
            self?.capture()
        }
        let preferredShortcut = shortcutStore.load()
        do {
            try shortcut.replaceShortcut(with: preferredShortcut)
            captureShortcut = preferredShortcut
        } catch {
            shortcutFailure = shortcutSettingsFailure(for: error)
            if preferredShortcut != .defaultCapture {
                do {
                    try shortcut.replaceShortcut(with: .defaultCapture)
                    captureShortcut = .defaultCapture
                } catch {}
            }
        }
        shortcutCoordinator = shortcut
        refreshShortcutSettings()
        startAutomaticCleanupLoop()
        publish()
    }

    func menuView() -> MenuBarContainerView {
        MenuBarContainerView(
            recentItems: historyRecords.prefix(3).map {
                MenuRecentItem(record: $0)
            },
            permission: permission,
            provider: providerReadiness,
            updateState: updateState,
            captureShortcut: GlobalShortcutDisplayFormatter.string(
                for: captureShortcut
            ),
            callbacks: menuCallbacks()
        )
    }

    func onboardingView() -> OnboardingContainerView {
        OnboardingContainerView(
            snapshot: OnboardingSession(
                permission: permission,
                provider: providerReadiness
            ).snapshot,
            providerSnapshot: providerSnapshot,
            providerConfigurations: providerConfigurations,
            apiKey: binding(\.apiKey),
            pendingModelID: binding(\.pendingModelID),
            callbacks: onboardingCallbacks()
        )
    }

    func managementCallbacks() -> ManagementCenterCallbacks {
        ManagementCenterCallbacks(
            onSelectRecord: { [weak self] id in
                Task { await self?.selectHistoryRecord(id) }
            },
            onSetPinned: { [weak self] id, pinned in
                Task { await self?.setHistoryPinned(id: id, pinned: pinned) }
            },
            onDelete: { [weak self] id in
                Task { await self?.deleteHistory(ids: [id], includePinned: true) }
            },
            onClearHistory: { [weak self] includePinned in
                Task { await self?.clearHistory(includePinned: includePinned) }
            },
            onRetryCleanup: { [weak self] in
                Task { await self?.runHistoryCleanup() }
            },
            onRetentionChange: { [weak self] value in
                Task { await self?.requestRetentionChange(value) }
            },
            onConfirmRetentionShortening: { [weak self] in
                Task { await self?.confirmRetentionShortening() }
            },
            onCancelRetentionShortening: { [weak self] in
                Task { await self?.cancelRetentionShortening() }
            },
            onLanguageChange: { [weak self] preference in
                Task { await self?.changeLanguage(preference) }
            },
            onRestartForLanguageChange: { [weak self] in
                Task { await self?.restartApplication() }
            },
            onLoginItemChange: { [weak self] enabled in
                Task { await self?.changeLoginItem(enabled) }
            },
            onShortcutChange: { [weak self] shortcut in
                self?.changeShortcut(shortcut)
            },
            onOpenLoginItemSettings: { [weak self] in
                Task { await self?.loginCoordinator.openSystemSettings() }
            },
            onAutomaticUpdateChecksChange: { [weak self] enabled in
                Task { await self?.changeAutomaticUpdateChecks(enabled) }
            },
            onCheckUpdates: { [weak self] in Task { await self?.checkUpdates() } },
            onDownloadUpdate: { [weak self] in Task { await self?.downloadUpdate() } },
            onOpenUpdateInformation: { NSWorkspace.shared.open($0) },
            onInstallUpdate: { [weak self] in Task { await self?.installUpdate() } },
            onExportDiagnostics: { [weak self] in
                Task { await self?.exportDiagnostics() }
            }
        )
    }

    func providerSettingsConfiguration() -> ProviderSettingsConfiguration {
        ProviderSettingsConfiguration(
            snapshot: providerSnapshot,
            configurations: providerConfigurations,
            apiKey: binding(\.apiKey),
            pendingModelID: binding(\.pendingModelID),
            onSelectProvider: { [weak self] provider in
                Task { await self?.selectProvider(provider) }
            },
            onValidate: { [weak self] in
                Task { await self?.validateProvider() }
            },
            onRefresh: { [weak self] in
                Task { await self?.refreshModels() }
            },
            onSelectModel: { [weak self] modelID in
                Task { await self?.selectModel(modelID) }
            },
            onDone: { [weak self] in self?.apiKey = "" }
        )
    }

    private func menuCallbacks() -> MenuBarCallbacks {
        MenuBarCallbacks(
            onCapture: { [weak self] in self?.capture() },
            onOpenRecent: { [weak self] id in
                Task { await self?.openRecentHistoryItem(id) }
            },
            onNavigate: { [weak self] destination in self?.onNavigate?(destination) },
            onCheckUpdates: { [weak self] in Task { await self?.checkUpdates() } },
            onDownloadUpdate: { [weak self] in Task { await self?.downloadUpdate() } },
            onOpenUpdateInformation: { NSWorkspace.shared.open($0) }
        )
    }

    private func onboardingCallbacks() -> OnboardingCallbacks {
        OnboardingCallbacks(
            onPermissionPrimaryAction: { [weak self] in
                Task { await self?.performPermissionAction() }
            },
            onSelectProvider: { [weak self] provider in
                Task { await self?.selectProvider(provider) }
            },
            onValidateProvider: { [weak self] in Task { await self?.validateProvider() } },
            onRefreshModels: { [weak self] in Task { await self?.refreshModels() } },
            onSelectModel: { [weak self] modelID in Task { await self?.selectModel(modelID) } },
            onProviderDone: {},
            onStart: { [weak self] in self?.finishOnboarding() },
            onFinishLater: { [weak self] in self?.finishOnboarding() }
        )
    }

    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<VLMSnapperApplicationModel, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }

    private func selectProvider(_ provider: ProviderID) async {
        await providerSession.selectProvider(provider)
        await refreshProviderPresentation()
    }

    private func validateProvider() async {
        await providerSession.validate(apiKey: apiKey)
        apiKey = ""
        await refreshProviderPresentation()
    }

    private func refreshModels() async {
        await providerSession.refreshModels()
        await refreshProviderPresentation()
    }

    private func selectModel(_ modelID: String) async {
        await providerSession.selectModel(modelID)
        pendingModelID = modelID
        await refreshProviderPresentation()
    }

    private func refreshProviderPresentation() async {
        providerSnapshot = await providerSession.snapshot()
        try? await refreshProviderReadiness()
        publish()
    }

    private func refreshProviderReadiness() async throws {
        let state = try await providerCoordinator.configurationState()
        providerConfigurations = state.configurations
        if let provider = state.currentProvider,
           let configuration = state.configurations[provider],
           let modelID = configuration.selectedModelID,
           configuration.isUsable {
            providerReadiness = .ready(provider: provider, modelID: modelID)
        } else if let pending = state.configurations.first(where: { $0.value.selectedModelID == nil }) {
            providerReadiness = .pendingModel(pending.key)
        } else {
            providerReadiness = .missing
        }
    }

    private func performPermissionAction() async {
        do {
            switch try await permissionCoordinator.performPrimaryAction() {
            case let .state(state): permission = state
            case .openSystemSettings:
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                ) {
                    NSWorkspace.shared.open(url)
                }
            case .restartApplication: await restartApplication()
            case .noAction: break
            }
        } catch {}
        publish()
    }

    private func changeLanguage(_ preference: ApplicationLanguagePreference) async {
        await languageStore.save(preference)
        settings = GeneralSettingsSnapshot(
            language: preference,
            languageRestartRequired: true,
            loginItemEnabled: settings.loginItemEnabled,
            loginItemState: settings.loginItemState,
            automaticallyChecksForUpdates: settings.automaticallyChecksForUpdates,
            updateState: updateState,
            retentionShorteningRecordCount: settings.retentionShorteningRecordCount,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
        publish()
    }

    private func changeLoginItem(_ enabled: Bool) async {
        guard let state = try? await loginCoordinator.setEnabled(enabled) else { return }
        settings = GeneralSettingsSnapshot(
            language: settings.language,
            languageRestartRequired: settings.languageRestartRequired,
            loginItemEnabled: enabled,
            loginItemState: state,
            automaticallyChecksForUpdates: settings.automaticallyChecksForUpdates,
            updateState: updateState,
            retentionShorteningRecordCount: settings.retentionShorteningRecordCount,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
        publish()
    }

    private func changeAutomaticUpdateChecks(_ enabled: Bool) async {
        defaults.set(enabled, forKey: "automaticallyChecksForUpdates")
        try? await updateCoordinator.setAutomaticallyChecks(enabled)
        settings = GeneralSettingsSnapshot(
            language: settings.language,
            languageRestartRequired: settings.languageRestartRequired,
            loginItemEnabled: settings.loginItemEnabled,
            loginItemState: settings.loginItemState,
            automaticallyChecksForUpdates: enabled,
            updateState: updateState,
            retentionShorteningRecordCount: settings.retentionShorteningRecordCount,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
        publish()
    }

    private func checkUpdates() async {
        try? await updateCoordinator.checkForUpdates()
        await refreshUpdatePresentation()
    }

    private func downloadUpdate() async {
        _ = try? await updateCoordinator.requestDownload()
        await refreshUpdatePresentation()
    }

    private func installUpdate() async {
        guard await prepareForTermination() else { return }
        _ = try? await updateCoordinator.requestImmediateInstall()
    }

    func prepareForTermination() async -> Bool {
        if captureSelectionSession != nil {
            await cancelCapture()
        }
        guard workspaceSession != nil else { return true }
        let disposition = await closeWorkspace()
        guard disposition == .confirmDiscardUnsavedResult else { return true }
        guard UnsavedResultConfirmation.confirm() else { return false }
        await discardUnsavedWorkspace()
        return true
    }

    private func exportDiagnostics() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VLMSnapper-diagnostics.jsonl.gz"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try await diagnosticStore.export(to: url)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = VLMSnapperLocalization.localizedString(
                forKey: "diagnostics.exportFailed.title"
            )
            alert.informativeText = VLMSnapperLocalization.localizedString(
                forKey: "diagnostics.exportFailed.body"
            )
            alert.runModal()
        }
    }

    private func receiveUpdateEvent(_ event: UpdateLifecycleEvent) async {
        await updateCoordinator.handle(event)
        await refreshUpdatePresentation()
    }

    private func refreshUpdatePresentation() async {
        updateState = await updateCoordinator.snapshot()
        settings = GeneralSettingsSnapshot(
            language: settings.language,
            languageRestartRequired: settings.languageRestartRequired,
            loginItemEnabled: settings.loginItemEnabled,
            loginItemState: settings.loginItemState,
            automaticallyChecksForUpdates: settings.automaticallyChecksForUpdates,
            updateState: updateState,
            retentionShorteningRecordCount: settings.retentionShorteningRecordCount,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
        publish()
    }

    private func selectHistoryRecord(_ id: UUID) async {
        selectedHistoryRecordID = id
        guard let record = try? await historyStore.historyRecord(id: id),
              let data = try? await screenshotStore.loadIfOwned(record.operation.screenshot)
        else {
            selectedHistoryImage = nil
            publish()
            return
        }
        selectedHistoryImage = NSImage(data: data)
        publish()
    }

    private func setHistoryPinned(id: UUID, pinned: Bool) async {
        try? await historyStore.setPinned(pinned, operationID: id)
        await refreshHistory()
    }

    private func deleteHistory(ids: [UUID], includePinned: Bool) async {
        let summary = await historyDeletionCoordinator.delete(
            recordIDs: ids,
            includePinned: includePinned
        )
        cleanupFailureCount = summary.failed
        if let selectedID = selectedHistoryRecordID, ids.contains(selectedID) {
            self.selectedHistoryRecordID = nil
            selectedHistoryImage = nil
        }
        await refreshHistory()
    }

    private func clearHistory(includePinned: Bool) async {
        await deleteHistory(
            ids: historyRecords.map(\.id),
            includePinned: includePinned
        )
    }

    private func runHistoryCleanup() async {
        let summary = await historyCleanupCoordinator.clean(retention: retention)
        cleanupFailureCount = summary.failed
        await refreshHistory()
    }

    private func startAutomaticCleanupLoop() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    return
                }
                guard let self else { return }
                await self.cleanupScheduler.runIfDue(
                    retention: self.retention,
                    now: Date()
                )
                await self.refreshHistory()
            }
        }
    }

    private func openRecentHistoryItem(_ identifier: String) async {
        guard let id = UUID(uuidString: identifier) else { return }
        await selectHistoryRecord(id)
        onNavigate?(.history)
    }

    private func requestRetentionChange(_ value: HistoryRetentionPeriod) async {
        guard let disposition = try? await retentionSettingsSession.requestChange(
            to: value
        ) else { return }
        switch disposition {
        case .saved:
            retention = value
            updateRetentionConfirmation(count: nil)
        case let .confirmationRequired(expiredRecordCount):
            updateRetentionConfirmation(count: expiredRecordCount)
        }
        publish()
    }

    private func confirmRetentionShortening() async {
        guard let summary = try? await retentionSettingsSession.confirmShortening()
        else { return }
        retention = HistoryRetentionPeriod(
            rawValue: defaults.integer(forKey: "historyRetentionDays")
        ) ?? retention
        cleanupFailureCount = summary.failed
        updateRetentionConfirmation(count: nil)
        await refreshHistory()
    }

    private func cancelRetentionShortening() async {
        await retentionSettingsSession.cancelShortening()
        updateRetentionConfirmation(count: nil)
        publish()
    }

    private func updateRetentionConfirmation(count: Int?) {
        settings = GeneralSettingsSnapshot(
            language: settings.language,
            languageRestartRequired: settings.languageRestartRequired,
            loginItemEnabled: settings.loginItemEnabled,
            loginItemState: settings.loginItemState,
            automaticallyChecksForUpdates: settings.automaticallyChecksForUpdates,
            updateState: updateState,
            retentionShorteningRecordCount: count,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
    }

    private func changeShortcut(_ shortcut: GlobalShortcut) {
        guard let shortcutCoordinator else { return }
        do {
            try shortcutCoordinator.replaceShortcut(with: shortcut)
            shortcutStore.save(shortcut)
            captureShortcut = shortcut
            shortcutFailure = nil
        } catch {
            shortcutFailure = shortcutSettingsFailure(for: error)
        }
        refreshShortcutSettings()
        publish()
    }

    private func refreshShortcutSettings() {
        settings = GeneralSettingsSnapshot(
            language: settings.language,
            languageRestartRequired: settings.languageRestartRequired,
            loginItemEnabled: settings.loginItemEnabled,
            loginItemState: settings.loginItemState,
            automaticallyChecksForUpdates: settings.automaticallyChecksForUpdates,
            updateState: updateState,
            retentionShorteningRecordCount: settings.retentionShorteningRecordCount,
            captureShortcut: captureShortcut,
            shortcutFailure: shortcutFailure
        )
    }

    private func shortcutSettingsFailure(for error: Error) -> ShortcutSettingsFailure {
        if error is GlobalShortcutError {
            return .invalid
        }
        if case GlobalShortcutRegistrationError.conflict = error {
            return .conflict
        }
        return .registrationFailed
    }

    private func finishOnboarding() {
        defaults.set(true, forKey: "hasFinishedOnboarding")
        NSApp.keyWindow?.orderOut(nil)
    }

    private func restartApplication() async {
        guard await prepareForTermination() else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$2\"",
            "vlmsnapper-restart",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {}
    }

    private func capture() {
        if workspaceSession != nil {
            resultController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if captureSelectionSession != nil || captureGeneration != nil {
            requestCapture(replacingCurrent: true)
            return
        }
        guard permission == .ready else {
            onShowOnboarding?()
            return
        }
        guard case .ready = providerReadiness else {
            onShowOnboarding?()
            return
        }
        requestCapture(replacingCurrent: false)
    }

    private func requestCapture(replacingCurrent: Bool) {
        let generation = UUID()
        captureGeneration = generation
        Task {
            if replacingCurrent {
                await captureSelectionSession?.cancel()
                guard captureGeneration == generation else { return }
                cancelCaptureSurfaces()
            }
            await beginCapture(generation: generation)
        }
    }

    private func beginCapture(generation: UUID) async {
        let result = await captureCoordinator.startCapture()
        guard captureGeneration == generation else {
            if case let .ready(session, _, _) = result {
                await session.cancel()
            }
            return
        }
        captureGeneration = nil
        switch result {
        case let .ready(session, frozenDisplays, _):
            captureSelectionSession = session
            captureOverlayController.show(
                displays: frozenDisplays,
                onSelection: { [weak self] selection in
                    Task { await self?.finishSelection(selection) }
                },
                onCancel: { [weak self] in
                    Task { await self?.cancelCapture() }
                }
            )
        case .permissionRequired:
            permission = .unavailable
            publish()
            onShowOnboarding?()
        case .allDisplaysFailed:
            cancelCaptureSurfaces()
            showCaptureFailure()
        }
    }

    private func showCaptureFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = VLMSnapperLocalization.localizedString(
            forKey: "capture.failed.title"
        )
        alert.informativeText = VLMSnapperLocalization.localizedString(
            forKey: "capture.failed.body"
        )
        alert.addButton(
            withTitle: VLMSnapperLocalization.localizedString(
                forKey: "action.retry"
            )
        )
        alert.addButton(
            withTitle: VLMSnapperLocalization.localizedString(
                forKey: "action.cancel"
            )
        )
        if alert.runModal() == .alertFirstButtonReturn {
            requestCapture(replacingCurrent: false)
        }
    }

    private func finishSelection(
        _ selection: FrozenCaptureOverlayController.Selection
    ) async {
        guard let captureSelectionSession,
              let currentGeometry = currentCaptureDisplayGeometry(
                  for: selection.displayID
              )
        else {
            await cancelCapture()
            return
        }
        do {
            try await captureSelectionSession.beginSelection(
                on: selection.displayID,
                at: selection.start
            )
            try await captureSelectionSession.updateSelection(to: selection.end)
            let selected = try await captureSelectionSession.finishSelection(
                currentGeometry: currentGeometry
            )
            originalImage = NSImage(data: selected.originalPNG)
            showCaptureToolbar(
                originalPNG: selected.originalPNG,
                selectionFrame: selection.screenFrame,
                screen: selection.screen
            )
        } catch CaptureSelectionError.selectionTooSmall {
            return
        } catch {
            await cancelCapture()
        }
    }

    private func showCaptureToolbar(
        originalPNG: Data,
        selectionFrame: CGRect,
        screen: NSScreen
    ) {
        captureToolbarController.show(
            content: CaptureOperationToolbar(
                operation: binding(\.selectedOperation),
                targetLanguageCode: targetLanguageBinding,
                targetLanguages: targetLanguageOptions,
                providerSummary: providerSummary,
                onStart: { [weak self] operation in
                    self?.openWorkspace(originalPNG: originalPNG, operation: operation)
                },
                onCancel: { [weak self] in
                    Task { await self?.cancelCapture() }
                }
            ),
            below: selectionFrame,
            on: screen
        )
    }

    private func openWorkspace(
        originalPNG: Data,
        operation: WorkspaceOperationKind
    ) {
        guard let providerSelection else { return }
        cancelCaptureSurfaces()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: historyStore,
            provider: providerStreamer
        )
        let session = OperationWorkspaceSession(
            originalPNG: originalPNG,
            runner: runner,
            activeGate: operationGate
        )
        workspaceSession = session
        selectedOperation = operation
        Task {
            await session.select(operation)
            workspaceSnapshot = await session.snapshot()
            showResultWorkspace()
            let previousAttempt = selectedAttempt
            let run = Task {
                try await session.startSelectedOperation(
                    selection: providerSelection,
                    targetLanguage: selectedTargetLanguageCode
                )
            }
            var observedTransition = false
            let transitionDeadline = Date().addingTimeInterval(1)
            while !run.isCancelled {
                guard workspaceSession === session else {
                    run.cancel()
                    return
                }
                workspaceSnapshot = await session.snapshot()
                showResultWorkspace()
                if selectedAttempt != previousAttempt {
                    observedTransition = true
                }
                if selectedSlotIsTerminal,
                   observedTransition || Date() >= transitionDeadline {
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            _ = try? await run.value
            guard workspaceSession === session else { return }
            workspaceSnapshot = await session.snapshot()
            showResultWorkspace()
            await recordSelectedOperationDiagnostic()
            await refreshHistory()
        }
    }

    private func showResultWorkspace() {
        resultController.show(
            content: ResultWorkspaceView(
                operation: binding(\.selectedOperation),
                snapshot: workspaceSnapshot,
                originalImage: originalImage,
                providerSummary: providerSummary,
                targetLanguage: targetLanguageName,
                onStart: { [weak self] operation in
                    Task { await self?.rerunWorkspace(operation) }
                },
                onCopy: { value in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                },
                onRetrySave: { [weak self] in
                    Task { await self?.retrySavingWorkspace() }
                }
            )
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func rerunWorkspace(_ operation: WorkspaceOperationKind) async {
        guard let workspaceSession, let providerSelection else { return }
        await workspaceSession.select(operation)
        selectedOperation = operation
        workspaceSnapshot = await workspaceSession.snapshot()
        let previousAttempt = selectedAttempt
        let run = Task {
            try await workspaceSession.startSelectedOperation(
                selection: providerSelection,
                targetLanguage: selectedTargetLanguageCode
            )
        }
        var observedTransition = false
        let transitionDeadline = Date().addingTimeInterval(1)
        while !run.isCancelled {
            guard self.workspaceSession === workspaceSession else {
                run.cancel()
                return
            }
            workspaceSnapshot = await workspaceSession.snapshot()
            showResultWorkspace()
            if selectedAttempt != previousAttempt {
                observedTransition = true
            }
            if selectedSlotIsTerminal,
               observedTransition || Date() >= transitionDeadline {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        _ = try? await run.value
        guard self.workspaceSession === workspaceSession else { return }
        workspaceSnapshot = await workspaceSession.snapshot()
        showResultWorkspace()
        await recordSelectedOperationDiagnostic()
        await refreshHistory()
    }

    private func retrySavingWorkspace() async {
        try? await workspaceSession?.retrySavingSelectedResult()
        if let workspaceSession {
            workspaceSnapshot = await workspaceSession.snapshot()
            showResultWorkspace()
            await refreshHistory()
        }
    }

    private func closeWorkspace() async -> WorkspaceCloseDisposition {
        guard let workspaceSession else { return .discard }
        let disposition = await workspaceSession.close()
        if disposition != .confirmDiscardUnsavedResult {
            self.workspaceSession = nil
            originalImage = nil
        }
        return disposition
    }

    private func discardUnsavedWorkspace() async {
        await workspaceSession?.discardUnsavedResults()
        workspaceSession = nil
        originalImage = nil
    }

    private func cancelCapture() async {
        captureGeneration = nil
        await captureSelectionSession?.cancel()
        cancelCaptureSurfaces()
    }

    private func cancelCaptureSurfaces() {
        captureOverlayController.close()
        captureToolbarController.hide()
        captureSelectionSession = nil
    }

    private func refreshHistory() async {
        historyRecords = (try? await historyStore.history(matching: HistoryQuery())) ?? []
        publish()
    }

    private var providerSelection: ProviderSelection? {
        guard case let .ready(provider, modelID) = providerReadiness else {
            return nil
        }
        return ProviderSelection(providerID: provider.rawValue, modelID: modelID)
    }

    private var providerSummary: String {
        guard case let .ready(provider, modelID) = providerReadiness else {
            return ""
        }
        let providerName = switch provider {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
        return "\(providerName) · \(modelID)"
    }

    private var targetLanguageBinding: Binding<String> {
        Binding(
            get: { self.selectedTargetLanguageCode },
            set: { value in
                guard TargetLanguageCatalog.standard.contains(value) else { return }
                self.selectedTargetLanguageCode = value
                self.defaults.set(value, forKey: "targetLanguageCode")
            }
        )
    }

    private var targetLanguageOptions: [TargetLanguageOption] {
        TargetLanguageCatalog.standard.codes.map {
            TargetLanguageOption(
                code: $0,
                name: VLMSnapperLocalization.localizedLanguageName(for: $0)
            )
        }
    }

    private var targetLanguageName: String {
        VLMSnapperLocalization.localizedLanguageName(
            for: selectedTargetLanguageCode
        )
    }

    private func defaultTargetLanguage(
        for preference: ApplicationLanguagePreference
    ) -> String {
        switch preference {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true
                ? "zh-Hans"
                : "en"
        }
    }

    private var selectedSlotIsTerminal: Bool {
        switch selectedAttempt {
        case .succeeded, .failed, .canceled, .resultPersistenceFailed:
            return true
        case .neverStarted, .preparing, .streaming:
            return false
        }
    }

    private var selectedAttempt: WorkspaceAttemptState {
        let slot = selectedOperation == .extract
            ? workspaceSnapshot.extract
            : workspaceSnapshot.translate
        return slot.attempt
    }

    private func recordSelectedOperationDiagnostic() async {
        guard case let .ready(provider, modelID) = providerReadiness else { return }
        let stage: DiagnosticRequestStage
        let errorCode: String?
        switch selectedAttempt {
        case let .failed(code):
            stage = .response
            errorCode = code
        case .resultPersistenceFailed:
            stage = .persistence
            errorCode = "result_persistence_failed"
        case .succeeded, .canceled:
            stage = .response
            errorCode = nil
        case .neverStarted, .preparing, .streaming:
            return
        }
        try? await diagnosticStore.record(
            DiagnosticEvent(
                timestamp: Date(),
                providerID: provider,
                modelID: modelID,
                stage: stage,
                normalizedErrorCode: errorCode
            )
        )
    }

    private func publish() {
        onSnapshotChange?()
    }
}
