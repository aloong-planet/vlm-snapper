import AppKit
import Foundation
import SwiftUI
import VLMSnapperCore
import VLMSnapperSparkle
import VLMSnapperUI

@MainActor
final class VLMSnapperApplicationModel: ObservableObject {
    private struct CaptureRequest {
        let generation: UUID
        let lease: UUID
        let workspaceToRetire: OperationWorkspaceSession?
    }

    let credentialEditor = ProviderCredentialEditor()
    private var credentialTasks: [UUID: Task<Void, Never>] = [:]
    private var providerObservationTask: Task<Void, Never>?
    private var activityObservationTask: Task<Void, Never>?
    private var providerFocusRequest: ProviderSettingsFocusRequest?
    @Published var pendingModelID: String?
    @Published var selectedTargetLanguageCode = "zh-Hans"

    private(set) var permission: ScreenCapturePermissionReadiness = .notRequested
    private(set) var providerReadiness: ProviderReadiness = .missing
    private(set) var providerConfigurations: [ProviderID: ProviderConfiguration] = [:]
    private(set) var currentProvider: ProviderID?
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
    private(set) var selectedHistoryImageLoadFailed = false
    private var historyImageLoadGeneration: UUID?
    let historyRetry = HistoryRetryPresentation()
    private var historyRetrySession: OperationWorkspaceSession?
    private var historyRetryTask: Task<Void, Never>?
    private(set) var cleanupFailureCount = 0
    private(set) var retention: HistoryRetentionPeriod = .thirtyDays
    private(set) var settings = GeneralSettingsSnapshot()
    private(set) var captureShortcut = GlobalShortcut.defaultCapture
    private(set) var shortcutFailure: ShortcutSettingsFailure?

    var onSnapshotChange: (@MainActor () -> Void)?
    var onNavigate: (@MainActor (ManagementCenterDestination) -> Void)?
    var onShowOnboarding: (@MainActor () -> Void)?
    var onOpenProviderSettingsFromOnboarding: (@MainActor () -> Void)?
    var onProviderConfigurationCompleted: (@MainActor () -> Void)?
    var onRetireCaptureSources: (@MainActor () -> Void)?

    private let defaults: UserDefaults
    private let dependencies: ApplicationModelDependencies
    private let shortcutStore: UserDefaultsGlobalShortcutStore
    private let languageStore: UserDefaultsApplicationLanguageStore
    private let providerCoordinator: ProviderConfigurationCoordinator
    private lazy var workflow = ApplicationWorkflow(coordinator: providerCoordinator)
    private let providerSession: ProviderSetupSession
    private let permissionCoordinator: ScreenCapturePermissionCoordinator
    private let loginCoordinator: LoginItemCoordinator
    private let historyStore: SQLiteHistoryStore
    private let diagnosticStore: DiagnosticLogStore
    private let screenshotStore: FileSystemScreenshotStore
    private let historyImageLoader: any ManagedScreenshotLoading
    private let providerStreamer: ProviderPreparedOperationStreamer
    private let historyDeletionCoordinator: HistoryDeletionCoordinator
    private let historyCleanupCoordinator: HistoryCleanupCoordinator
    private let retentionSettingsSession: RetentionSettingsSession
    private let cleanupScheduler: AutomaticHistoryCleanupScheduler
    private let operationGate = ActiveOperationGate()
    private let captureCoordinator: CaptureFreezeCoordinator
    /// The display of the selection the toolbar belongs to; a change to it ends the capture (v1-core::REQ-007/AC-07).
    private var confirmedSelectionDisplayID: UInt32?
    /// The latest crop of the confirmed selection and the crop still running after an adjustment;
    /// toolbar actions wait for that crop so they never use the selection before it was adjusted.
    private var confirmedSelectionPNG: Data?
    private var selectionCropTask: Task<Void, Never>?
    /// Selections are cropped one after another: the session takes no new selection while it crops,
    /// so a release during a crop waits for it, and only the newest selection's crop is kept.
    private var selectionCount = 0
    /// Set while a toolbar action handles a click, so a second click (a double click) is ignored.
    private var captureActionInProgress = false
    private let captureOverlayController = FrozenCaptureOverlayController()
    private let captureToolbarController = CaptureToolbarPanelController()
    private var captureSelectionSession: CaptureSelectionSession?
    private var captureDisplayGeometries: [UInt32: CaptureDisplayGeometry] = [:]
    private var captureRequest: CaptureRequest?
    private var activeCaptureGeneration: UUID?
    private var captureLease: UUID?
    private var workspaceSession: OperationWorkspaceSession?
    private var workspaceSnapshot = OperationWorkspaceSnapshot(
        selectedOperation: .extract,
        extract: WorkspaceOperationSlot(),
        translate: WorkspaceOperationSlot()
    )
    /// The result box of the capture on screen (v1-core::REQ-010, REQ-011, REQ-012).
    private var shownResultOperation: WorkspaceOperationKind?
    private var runningResultOperation: WorkspaceOperationKind?
    var isRunningResultRequest: Bool { runningResultOperation != nil }
    private var resultRunTask: Task<Void, Never>?
    private var hasUnsavedWorkspaceResult = false
    private var isConfirmingResultExit = false
    /// A request that never reached the session, such as with no usable model; shown like its failure.
    private var localResultFailures: [WorkspaceOperationKind: String] = [:]
    private var workspaceProviderSummary: String?
    /// The language of the record in the translation slot; a rerun keeps it.
    private var workspaceTargetLanguageCode: String?
    private var confirmedSelectionFrame: CGRect?
    private var confirmedSelectionScreen: NSScreen?
    private lazy var captureToolbarState = CaptureToolbarState(targetLanguageCode: selectedTargetLanguageCode)
    private var shortcutCoordinator: GlobalShortcutCoordinator?
    private var cleanupTask: Task<Void, Never>?
    private lazy var resultBoxController = CaptureResultBoxPanelController(
        actions: CaptureResultBoxActions(
            onCopy: { [weak self] in self?.dependencies.captureClipboard.write(text: $0) },
            onRetry: { [weak self] in self?.retryShownResult() },
            onRetrySave: { [weak self] in Task { await self?.retrySavingShownResult() } },
            onClose: { [weak self] in self?.closeResultBox() }
        ),
        onEscape: { [weak self] in
            guard let self, let generation = activeCaptureGeneration else { return }
            Task { await self.requestCaptureExit(generation: generation) }
        }
    )
    private lazy var updateDriver = dependencies.makeUpdateDriver { [weak self] event in
        await self?.receiveUpdateEvent(event)
    }
    private lazy var updateCoordinator = UpdateLifecycleCoordinator(driver: updateDriver)

    convenience init(
        applicationSupportRoot: URL,
        languageStore: UserDefaultsApplicationLanguageStore,
        defaults: UserDefaults = .standard
    ) throws {
        try self.init(
            applicationSupportRoot: applicationSupportRoot,
            languageStore: languageStore,
            defaults: defaults,
            dependencies: .live()
        )
    }

    init(
        applicationSupportRoot: URL,
        languageStore: UserDefaultsApplicationLanguageStore,
        defaults: UserDefaults,
        dependencies: ApplicationModelDependencies,
        historyImageLoader: (any ManagedScreenshotLoading)? = nil
    ) throws {
        self.defaults = defaults
        self.dependencies = dependencies
        shortcutStore = UserDefaultsGlobalShortcutStore(defaults: defaults)
        self.languageStore = languageStore
        let credentialStore = dependencies.credentialStore
        let metadataStore = FileProviderMetadataStore(
            fileURL: applicationSupportRoot.appendingPathComponent("providers.json")
        )
        providerCoordinator = ProviderConfigurationCoordinator(
            modelLister: OfficialProviderModelLister(httpLoader: dependencies.modelHTTP),
            credentialStore: credentialStore,
            metadataStore: metadataStore
        )
        providerSession = ProviderSetupSession(
            selectedProvider: .deepSeek,
            boundary: providerCoordinator
        )
        permissionCoordinator = ScreenCapturePermissionCoordinator(
            authorizer: dependencies.permissionAuthorizer,
            requestHistory: dependencies.permissionHistory
        )
        loginCoordinator = LoginItemCoordinator(
            service: dependencies.loginService,
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
            rootDirectory: dependencies.screenshotRoot
        )
        self.historyImageLoader = historyImageLoader ?? screenshotStore
        providerStreamer = ProviderPreparedOperationStreamer(
            credentialStore: credentialStore,
            executor: ProviderAdapterExecutor(transport: dependencies.operationHTTP)
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
            preferences: dependencies.retentionPreferences,
            cleanup: cleanupCoordinator
        )
        cleanupScheduler = AutomaticHistoryCleanupScheduler(cleanup: cleanupCoordinator)
        captureCoordinator = CaptureFreezeCoordinator(
            permissionChecker: dependencies.permissionChecker,
            capturer: dependencies.frozenDisplayCapturer,
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
        let providerChanges = await providerSession.changes()
        providerObservationTask = Task { [weak self] in
            for await _ in providerChanges {
                guard !Task.isCancelled, let self else { return }
                await self.refreshProviderPresentation()
            }
        }
        let activityChanges = await providerCoordinator.activityChanges()
        activityObservationTask = Task { [weak self] in
            for await _ in activityChanges {
                guard !Task.isCancelled, let self else { return }
                await self.refreshProviderPresentation()
            }
        }
        for provider in ProviderID.allCases {
            try Task.checkCancellation()
            do { _ = try await providerCoordinator.reconcileCredentialState(for: provider) }
            catch { /* Opening the affected card exposes the classified storage or recovery failure. */ }
        }
        try Task.checkCancellation()
        await providerSession.load()
        providerSnapshot = await providerSession.snapshot()
        let initialRead = credentialEditor.beginLoading(for: providerSnapshot.selectedProvider)
        await loadCredential(initialRead)
        pendingModelID = providerSnapshot.selectedModelID
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
            backend: try dependencies.makeShortcutBackend()
        ) { [weak self] in
            self?.capture(from: .shortcut)
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
            recentItems: historyRecords.prefix(5).map {
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
            callbacks: onboardingCallbacks()
        )
    }

    func managementCallbacks() -> ManagementCenterCallbacks {
        ManagementCenterCallbacks(
            historyRetry: historyRetry,
            onRetryHistorySave: { [weak self] in self?.retryHistorySave() },
            onSelectRecord: { [weak self] id in
                Task { await self?.selectHistoryRecord(id) }
            },
            onRetryRecord: { [weak self] id in self?.startHistoryRetry(id) },
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
            focusRequest: providerFocusRequest,
            configurations: providerConfigurations,
            currentProvider: currentProvider,
            credentialEditor: credentialEditor,
            pendingModelID: binding(\.pendingModelID),
            onSelectProvider: { [weak self] provider in
                guard let self else { return }
                let request = credentialEditor.beginLoading(for: provider)
                let task = startCredentialTask {
                    await self.credentialEditor.performLoad(request) {
                        await self.selectProvider(request)
                    }
                    // In its own task, as a manual refresh is: a refresh outlives this card's load.
                    Task { [session = self.providerSession] in await session.checkOpenedCardCache() }
                }
                credentialEditor.attachLoadTask(task, for: request)
            },
            onOpenProviderCard: { [providerSession] provider in
                Task { await providerSession.cardOpened(provider) }
            },
            onValidate: { [weak self] submission in
                self?.startCredentialTask { await self?.validateProvider(submission) }
            },
            onRefresh: { [weak self] in
                Task { await self?.refreshModels() }
            },
            onSelectModel: { [weak self] modelID in
                Task { await self?.selectModel(modelID) }
            },
            onSetCurrentProvider: { [weak self] provider in
                Task { await self?.setCurrentProvider(provider) }
            },
            onRemoveProvider: { [weak self] provider in
                Task { await self?.removeProvider(provider) }
            }
        )
    }

    private func menuCallbacks() -> MenuBarCallbacks {
        MenuBarCallbacks(
            onCapture: { [weak self] in self?.capture(from: .menu) },
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
            onOpenProviderSettings: { [weak self] in
                self?.onOpenProviderSettingsFromOnboarding?()
            },
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

    private func selectProvider(_ request: ProviderCredentialLoad) async {
        guard credentialEditor.accepts(request) else { return }
        await providerSession.selectProvider(request.provider) { [weak self] in
            await MainActor.run { self?.credentialEditor.detachLoadTask(for: request) }
        }
        guard credentialEditor.accepts(request), !Task.isCancelled else { return }
        if credentialEditor.isLoading {
            await loadCredential(request)
        }
        await refreshProviderPresentation()
    }

    @discardableResult
    private func startCredentialTask(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await operation()
            self?.credentialTasks[id] = nil
        }
        credentialTasks[id] = task
        return task
    }

    private func loadCredential(_ request: ProviderCredentialLoad) async {
        guard credentialEditor.accepts(request) else { return }
        let snapshot = await providerSession.snapshot()
        guard snapshot.failure != .secureStorage else { return }
        do {
            let value = try await providerCoordinator.apiKey(for: request.provider)
            guard credentialEditor.accepts(request), !Task.isCancelled else { return }
            credentialEditor.completeLoad(request, value: value ?? "")
        } catch {
            guard credentialEditor.accepts(request), !Task.isCancelled else { return }
            await providerSession.credentialReadDidFail(for: request.provider) { [weak self] in
                await MainActor.run { self?.credentialEditor.accepts(request) == true }
            }
        }
    }

    private func validateProvider(_ submission: ProviderCredentialSubmission) async {
        let succeeded = await providerSession.validate(apiKey: submission.value, for: submission.provider)
        credentialEditor.complete(submission, succeeded: succeeded)
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
        if providerSnapshot.phase == .ready,
           providerSnapshot.selectedModelID == modelID {
            onProviderConfigurationCompleted?()
        }
    }

    private func setCurrentProvider(_ provider: ProviderID) async {
        try? await providerCoordinator.setCurrentProvider(provider)
        await refreshProviderPresentation()
    }

    private func removeProvider(_ provider: ProviderID) async {
        do {
            try await providerCoordinator.clearProvider(provider)
        } catch {
            await refreshProviderPresentation()
            return
        }
        await providerSession.clearValidationFailure(for: provider)
        credentialEditor.configurationWasRemoved(for: provider)
        if providerSnapshot.selectedProvider == provider {
            pendingModelID = nil
            await providerSession.load()
        }
        await refreshProviderPresentation()
    }

    private func refreshProviderPresentation() async {
        providerSnapshot = await providerSession.snapshot()
        pendingModelID = providerSnapshot.selectedModelID
        do { try await refreshProviderReadiness() }
        catch {
            providerConfigurations = [:]
            currentProvider = nil
            providerReadiness = .missing
        }
        publish()
    }

    private func refreshProviderReadiness() async throws {
        let state = try await providerCoordinator.configurationState()
        providerConfigurations = state.configurations
        currentProvider = state.currentProvider
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
        if let historyRetrySession {
            let disposition = await historyRetrySession.close()
            if disposition == .confirmDiscardUnsavedResult {
                guard UnsavedResultConfirmation.confirm() else { return false }
                await historyRetrySession.discardUnsavedResults()
            }
        }
        historyRetryTask?.cancel()
        await historyRetryTask?.value
        if let request = captureRequest {
            await abandonPendingCapture(request)
        }
        if let activeCaptureGeneration {
            guard await closeResultSessionForExit() else { return false }
            await cancelCapture(generation: activeCaptureGeneration)
        }
        for task in credentialTasks.values { task.cancel() }
        credentialTasks.removeAll()
        credentialEditor.terminate()
        providerObservationTask?.cancel()
        activityObservationTask?.cancel()
        return true
    }

    /// Final resource release after termination has been committed, not during
    /// preparation (which is also used before an update installation attempt).
    func stop() {
        historyImageLoadGeneration = nil
        dependencies.displayMonitor.stop()
        cleanupTask?.cancel()
        cleanupTask = nil
        shortcutCoordinator?.unregister()
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
        if selectedHistoryRecordID == id, historyImageLoadGeneration != nil { return }
        let generation = UUID()
        historyImageLoadGeneration = generation
        if selectedHistoryRecordID != id { selectedHistoryImage = nil }
        selectedHistoryRecordID = id
        selectedHistoryImageLoadFailed = false
        publish()
        let image: NSImage?
        if let record = try? await historyStore.historyRecord(id: id),
           let data = try? await historyImageLoader.loadIfOwned(record.operation.screenshot) {
            image = NSImage(data: data)
        } else {
            image = nil
        }
        guard selectedHistoryRecordID == id, historyImageLoadGeneration == generation else { return }
        historyImageLoadGeneration = nil
        selectedHistoryImage = image
        selectedHistoryImageLoadFailed = image == nil
        publish()
    }

    private func startHistoryRetry(_ id: UUID) {
        guard !historyRetry.isRunning, historyRetry.slot.unsavedResult == nil else { return }
        historyRetry.isRunning = true
        historyRetry.recordID = id
        historyRetrySession = nil
        historyRetry.providerSummary = ""
        historyRetry.slot = WorkspaceOperationSlot(attempt: .preparing)
        historyRetryTask = Task { [weak self] in
            guard let self else { return }
            defer { historyRetry.isRunning = false; publish() }
            do {
                let admitted = try await workflow.performOperation {
                    guard await workspaceSession?.preventsHistoryDiscard != true else {
                        throw OperationWorkspaceRunFailure(code: "operation_busy")
                    }
                    guard let selection = providerSelection else {
                        throw OperationWorkspaceRunFailure(code: "provider_unavailable")
                    }
                    guard let record = try await historyStore.historyRecord(id: id),
                          !record.operation.status.isActive else {
                        throw OperationWorkspaceRunFailure(code: "history_record_unavailable")
                    }
                    guard let png = try? await screenshotStore.loadIfOwned(record.operation.screenshot),
                          NSImage(data: png) != nil else {
                        throw OperationWorkspaceRunFailure(code: "history_screenshot_unavailable")
                    }
                    try Task.checkCancellation()
                    let runner = PersistedOperationWorkspaceRunner(screenshotStore: screenshotStore,
                        historyStore: historyStore, provider: providerStreamer,
                        visionCompatibility: providerCoordinator, modelListRefresh: providerCoordinator,
                        restoring: record.operation)
                    let session = OperationWorkspaceSession(originalPNG: png, runner: runner,
                        activeGate: operationGate, restoring: record.operation)
                    historyRetrySession = session
                    historyRetry.providerSummary = providerSummary(for: selection)
                    let kind: WorkspaceOperationKind = record.operation.kind == .extract ? .extract : .translate
                    await session.select(kind)
                    let observation = Task { @MainActor in
                        while !Task.isCancelled {
                            let snapshot = await session.snapshot()
                            guard !Task.isCancelled else { return }
                            historyRetry.slot = kind == .extract ? snapshot.extract : snapshot.translate
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                    }
                    defer { observation.cancel() }
                    do {
                        try await session.startSelectedOperation(selection: selection,
                            targetLanguage: record.operation.targetLanguage ?? selectedTargetLanguageCode)
                    } catch {
                        let snapshot = await session.snapshot()
                        historyRetry.slot = kind == .extract ? snapshot.extract : snapshot.translate
                        await refreshHistory()
                        throw error
                    }
                    let snapshot = await session.snapshot()
                    historyRetry.slot = kind == .extract ? snapshot.extract : snapshot.translate
                    await refreshHistory()
                }
                if !admitted { historyRetry.slot = WorkspaceOperationSlot(attempt: .failed(code: "operation_busy")) }
            } catch {
                if historyRetry.slot.attempt == .preparing || historyRetry.slot.attempt == .neverStarted {
                    historyRetry.slot = WorkspaceOperationSlot(attempt: .failed(
                        code: (error as? OperationWorkspaceRunFailure)?.code ?? "operation_failed"))
                }
            }
            await reloadProviderIfRequestChangedModels(historyRetry.slot)
        }
    }

    /// The request may have just cleared the model. This finishes before the request counts as ended, so a press
    /// right after the failure already finds no model (v1-core failure mode 56), and the settings page shows none.
    private func reloadProviderIfRequestChangedModels(_ slot: WorkspaceOperationSlot) async {
        guard slot.attempt == .failed(code: ProviderAdapterError.imageInputUnsupported.normalizedCode)
                || slot.attempt == .failed(code: ProviderAdapterError.modelUnavailable.normalizedCode),
              let currentProvider else { return }
        await providerSession.reloadConfiguration(of: currentProvider)
        await refreshProviderPresentation()
    }

    private func retryHistorySave() {
        guard !historyRetry.isRunning, historyRetry.slot.unsavedResult != nil,
              let session = historyRetrySession else { return }
        historyRetry.isRunning = true
        historyRetryTask = Task { [weak self] in
            guard let self else { return }
            defer { historyRetry.isRunning = false; publish() }
            try? await session.retrySavingSelectedResult()
            let snapshot = await session.snapshot()
            historyRetry.slot = snapshot.selectedOperation == .extract ? snapshot.extract : snapshot.translate
            await refreshHistory()
        }
    }

    private func setHistoryPinned(id: UUID, pinned: Bool) async {
        try? await historyStore.setPinned(pinned, operationID: id)
        await refreshHistory()
    }

    private func deleteHistory(ids: [UUID], includePinned: Bool) async {
        guard !historyRetry.preventsDiscard,
              await workspaceSession?.preventsHistoryDiscard != true else {
            await refreshHistory()
            return
        }
        let summary = await historyDeletionCoordinator.delete(
            recordIDs: ids,
            includePinned: includePinned
        )
        cleanupFailureCount = summary.failed
        if let selectedID = selectedHistoryRecordID, ids.contains(selectedID) {
            self.selectedHistoryRecordID = nil
            selectedHistoryImage = nil
            selectedHistoryImageLoadFailed = false
            historyImageLoadGeneration = nil
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
        guard !historyRetry.preventsDiscard,
              await workspaceSession?.preventsHistoryDiscard != true else { return }
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
                guard !self.historyRetry.preventsDiscard,
                      await self.workspaceSession?.preventsHistoryDiscard != true else { continue }
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
        guard await workspaceSession?.preventsHistoryDiscard != true,
              !historyRetry.preventsDiscard else {
            publish()
            return
        }
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

    private func capture(from source: CaptureEntryPoint = .menu) {
        Task {
            await workflow.capture(
                from: source,
                replacing: captureLease,
                presentProvider: { [weak self] provider in
                    guard let self else { return }
                    self.providerFocusRequest = ProviderSettingsFocusRequest(provider: provider)
                    self.publish()
                    self.onNavigate?(.providerSettings)
                    self.providerSettingsConfiguration().onSelectProvider(provider)
                },
                perform: { [self] lease in
                    guard permission == .ready, case .ready = providerReadiness else {
                        onShowOnboarding?()
                        return false
                    }
                    guard captureRequest == nil else { return false }
                    let previousLease = captureLease
                    captureLease = lease
                    let workspaceToRetire = workspaceSession
                    if let workspaceToRetire {
                        let preparation = await workspaceToRetire.prepareForCapture()
                        guard workspaceSession === workspaceToRetire else {
                            captureLease = previousLease
                            return false
                        }
                        // A running request or an unsaved result keeps its capture on screen
                        // (v1-core::REQ-012/AC-05).
                        guard preparation == .beginCapture else {
                            captureLease = previousLease
                            return false
                        }
                    }
                    let accepted = await requestCapture(workspaceToRetire: workspaceToRetire)
                    if !accepted, captureLease == lease { captureLease = previousLease }
                    return accepted
                }
            )
        }
    }

    private func requestCapture(
        workspaceToRetire: OperationWorkspaceSession?
    ) async -> Bool {
        guard captureRequest == nil, let captureLease else { return false }
        let request = CaptureRequest(
            generation: UUID(),
            lease: captureLease,
            workspaceToRetire: workspaceToRetire
        )
        captureRequest = request
        return await beginCapture(request: request)
    }

    private func beginCapture(request: CaptureRequest) async -> Bool {
        // Cover the displays now; the freeze below excludes VLMSnapper windows.
        if captureOverlayController.presentPending(
            onSelection: { [weak self] selection in
                guard let self else { return }
                let previous = selectionCropTask
                selectionCount += 1
                let number = selectionCount
                selectionCropTask = Task {
                    await previous?.value
                    await self.finishSelection(
                        selection,
                        number: number,
                        generation: request.generation
                    )
                }
            },
            onCancel: { [weak self] in
                Task { await self?.requestCaptureExit(generation: request.generation) }
            },
            onSelectionChanging: { [weak self] frame, screen in
                // The toolbar follows an adjusted selection and hides when a new one starts.
                guard let self, activeCaptureGeneration == request.generation else { return }
                if let frame {
                    captureToolbarController.reposition(below: frame, on: screen)
                } else {
                    captureToolbarController.hide()
                }
            }
        ) {
            captureToolbarController.suspend()
            resultBoxController.suspend()
            attachSnapRegions(for: request)
        }
        let result = await captureCoordinator.startCapture()
        guard captureRequest?.generation == request.generation else {
            // The cancellation that cleared this request withdrew its overlay.
            if case let .ready(session, _, _) = result {
                await session.cancel()
            }
            return false
        }
        switch result {
        case let .ready(session, frozenDisplays, _):
            // Revalidate the frozen frames before showing them.
            let geometries = dependencies.displayMonitor.currentGeometries()
            let invalidated = await session.applyCurrentDisplayGeometries(geometries)
            let validDisplays = frozenDisplays.filter { !invalidated.contains($0.geometry.displayID) }
            guard captureRequestCanCommit(request) else {
                // Whoever cleared this request already withdrew its overlay and
                // restored its workspace; a newer request may own both again.
                let ownsRequest = captureRequest?.generation == request.generation
                if ownsRequest {
                    captureRequest = nil
                    withdrawPendingCapture()
                }
                await session.cancel()
                if ownsRequest {
                    await request.workspaceToRetire?.restoreAfterCaptureFailure()
                }
                return false
            }
            let replacementPresented = captureOverlayController.commit(
                displays: validDisplays
            )
            guard replacementPresented else {
                captureRequest = nil
                withdrawPendingCapture()
                await session.cancel()
                await request.workspaceToRetire?.restoreAfterCaptureFailure()
                await releaseFailedCaptureIfNeeded(request)
                showCaptureFailure()
                return false
            }
            let retiredSelectionSession = captureSelectionSession
            captureSelectionSession = session
            captureDisplayGeometries = Dictionary(uniqueKeysWithValues: validDisplays
                .filter { captureOverlayController.presentedDisplayIDs.contains($0.geometry.displayID) }
                .map { ($0.geometry.displayID, $0.geometry) })
            activeCaptureGeneration = request.generation
            dependencies.displayMonitor.start { [weak self] geometries in
                self?.captureDisplaysChanged(geometries)
            }
            // Registration follows an actor hop. Read again while subscribed,
            // before yielding, so a change in that gap cannot leave a stale overlay.
            captureDisplaysChanged(dependencies.displayMonitor.currentGeometries())
            captureRequest = nil
            captureToolbarController.hide()
            if let workspaceToRetire = request.workspaceToRetire,
               workspaceSession === workspaceToRetire {
                resetResultSurfaces()
            }
            onRetireCaptureSources?()
            await retiredSelectionSession?.cancel()
            return true
        case .permissionRequired:
            captureRequest = nil
            withdrawPendingCapture()
            await request.workspaceToRetire?.restoreAfterCaptureFailure()
            permission = .unavailable
            publish()
            onShowOnboarding?()
        case .allDisplaysFailed:
            captureRequest = nil
            withdrawPendingCapture()
            await request.workspaceToRetire?.restoreAfterCaptureFailure()
            await releaseFailedCaptureIfNeeded(request)
            showCaptureFailure()
        }
        return false
    }

    /// A capture that cannot commit leaves the previous selection exactly as it was.
    private func withdrawPendingCapture() {
        captureOverlayController.rollback()
        resultBoxController.resume()
        captureToolbarController.resume()
    }

    /// `Esc` or termination before frozen frames arrive leaves capture entirely,
    /// including a selection being replaced; a reserved workspace becomes usable again.
    private func abandonPendingCapture(_ request: CaptureRequest) async {
        captureRequest = nil
        if let activeCaptureGeneration {
            await cancelCapture(generation: activeCaptureGeneration)
        } else {
            captureOverlayController.close()
        }
        await request.workspaceToRetire?.restoreAfterCaptureFailure()
    }

    private func releaseFailedCaptureIfNeeded(_ request: CaptureRequest) async {
        // A retry from the failure alert must not inherit a failed new attempt's
        // lease. A replacement failure still belongs to the existing selection.
        guard activeCaptureGeneration == nil, captureLease == request.lease else { return }
        captureLease = nil
        await providerCoordinator.release(request.lease)
    }

    private func captureRequestCanCommit(_ request: CaptureRequest) -> Bool {
        guard captureRequest?.generation == request.generation else { return false }
        guard captureLease == request.lease else { return false }
        if let workspaceToRetire = request.workspaceToRetire {
            return workspaceSession === workspaceToRetire
        }
        return workspaceSession == nil
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
        Task {
            // A retained overlay's toolbar takes no action while the alert is shown over it.
            captureActionInProgress = true
            let response = await captureOverlayController.presentAlert(alert)
            captureActionInProgress = false
            if response == .alertFirstButtonReturn {
                capture()
            }
        }
    }

    /// Reads the window list alongside the freeze and hands it to this request's overlay only
    /// while that overlay is the newest: pending for this request, or committed with no newer
    /// request pending (v1-core::REQ-006).
    private func attachSnapRegions(for request: CaptureRequest) {
        let listing = dependencies.windowListing
        Task { [weak self] in
            let snapshot = await listing.captureWindowSnapshot()
            guard let self else { return }
            let ownsNewestOverlay = self.captureRequest.map { $0.generation == request.generation }
                ?? (self.activeCaptureGeneration == request.generation)
            guard ownsNewestOverlay else { return }
            self.captureOverlayController.attachSnapRegions(snapshot.map {
                CaptureSnapRegionResolver(
                    snapshot: $0,
                    excludedProcessID: ProcessInfo.processInfo.processIdentifier
                )
            })
        }
    }

    private func finishSelection(
        _ selection: FrozenCaptureOverlayController.Selection,
        number: Int,
        generation: UUID
    ) async {
        guard activeCaptureGeneration == generation,
              let captureSelectionSession,
              captureDisplayGeometries[selection.displayID] != nil else { return }
        let geometries = dependencies.displayMonitor.currentGeometries()
        captureDisplaysChanged(geometries)
        guard let currentGeometry = captureDisplayGeometries[selection.displayID] else { return }
        do {
            try await captureSelectionSession.beginSelection(
                on: selection.displayID,
                at: selection.start
            )
            try await captureSelectionSession.updateSelection(to: selection.end)
            let selected = try await captureSelectionSession.finishSelection(
                currentGeometry: currentGeometry
            )
            guard activeCaptureGeneration == generation,
                  self.captureSelectionSession === captureSelectionSession,
                  captureDisplayGeometries[selection.displayID] != nil,
                  selectionCount == number else { return }
            // Displays stay monitored: the selection can still be adjusted until an action starts.
            confirmedSelectionDisplayID = selection.displayID
            confirmedSelectionPNG = selected.originalPNG
            confirmedSelectionFrame = selection.screenFrame
            confirmedSelectionScreen = selection.screen
            showCaptureToolbar(
                selectionFrame: selection.screenFrame,
                screen: selection.screen
            )
        } catch CaptureSelectionError.selectionTooSmall {
            return
        } catch let error as CaptureSelectionError
            where error == .displayUnavailable || error == .displayGeometryChanged || error == .inactiveSession {
            // A display notification or a replacement may have retired this drag.
            // The remaining displays and newer capture belong to their own session.
            return
        } catch {
            await cancelCapture(generation: generation)
        }
    }

    private func captureDisplaysChanged(_ geometries: [CaptureDisplayGeometry]) {
        guard let generation = activeCaptureGeneration,
              let session = captureSelectionSession,
              !captureDisplayGeometries.isEmpty else { return }
        let current = Dictionary(uniqueKeysWithValues: geometries.map { ($0.displayID, $0) })
        let invalidated = captureDisplayGeometries.compactMap { id, frozen in
            current[id] == frozen ? nil : id
        }
        guard !invalidated.isEmpty else { return }
        for id in invalidated { captureDisplayGeometries.removeValue(forKey: id) }
        // Remove stale native hit targets before yielding to the session actor.
        captureOverlayController.invalidateDisplays(invalidated)
        Task { [weak self] in
            _ = await session.applyCurrentDisplayGeometries(geometries)
            guard let self, activeCaptureGeneration == generation,
                  captureSelectionSession === session else { return }
            let confirmedDisplayChanged = confirmedSelectionDisplayID.map(invalidated.contains) ?? false
            if captureDisplayGeometries.isEmpty || confirmedDisplayChanged {
                await endCaptureAfterDisplayLoss(generation: generation)
            }
        }
    }

    private func showCaptureToolbar(
        selectionFrame: CGRect,
        screen: NSScreen
    ) {
        guard let generation = activeCaptureGeneration else { return }
        captureToolbarState.targetLanguageCode = selectedTargetLanguageCode
        captureToolbarController.show(
            content: CaptureOperationToolbar(
                state: captureToolbarState,
                targetLanguages: targetLanguageOptions,
                onStart: { [weak self] operation in
                    self?.runCaptureAction(generation: generation) { png in
                        self?.handleOperationPress(operation, originalPNG: png)
                    }
                },
                onTargetLanguageChange: { [weak self] code in
                    self?.changeTargetLanguage(code)
                },
                onCopy: { [weak self] in
                    self?.runCaptureAction(generation: generation) { png in
                        await self?.copyCapturedImage(png, generation: generation)
                    }
                },
                onSave: { [weak self] in
                    self?.runCaptureAction(generation: generation) { png in
                        await self?.saveCapturedImage(png, generation: generation)
                    }
                },
                onCancel: { [weak self] in
                    Task { await self?.requestCaptureExit(generation: generation) }
                }
            ),
            below: selectionFrame,
            on: screen
        )
    }

    /// Runs a toolbar action with the crop of the selection as it is now, after any adjustment still
    /// being cropped. One action at a time: clicks while one runs are ignored.
    private func runCaptureAction(generation: UUID, _ action: @escaping @MainActor (Data) async -> Void) {
        guard activeCaptureGeneration == generation, !captureActionInProgress else { return }
        captureActionInProgress = true
        Task {
            await selectionCropTask?.value
            if activeCaptureGeneration == generation, let png = confirmedSelectionPNG {
                await action(png)
            }
            captureActionInProgress = false
        }
    }

    /// Copy and Save end the capture like Cancel: no new history, no model request (v1-core::REQ-008, REQ-009).
    private func copyCapturedImage(_ png: Data, generation: UUID) async {
        guard dependencies.captureClipboard.write(png: png) else {
            await presentCaptureActionFailure(
                title: VLMSnapperLocalization.localizedString(forKey: "capture.copyFailed.title"),
                body: VLMSnapperLocalization.localizedString(forKey: "capture.copyFailed.body")
            )
            return
        }
        await requestCaptureExit(generation: generation)
    }

    private func saveCapturedImage(_ png: Data, generation: UUID) async {
        // The save panel is not modal, so the overlay is held still while it is open (v1-core::REQ-009/AC-04).
        captureOverlayController.setSelectionEnabled(false)
        let outcome = await dependencies.captureImageSaver.save(
            png: png,
            suggestedName: CaptureImageFileName.suggested()
        )
        captureOverlayController.setSelectionEnabled(true)
        guard activeCaptureGeneration == generation else { return }
        switch outcome {
        case .saved:
            await requestCaptureExit(generation: generation)
        case .cancelled:
            break
        case .failed:
            await presentCaptureActionFailure(
                title: VLMSnapperLocalization.localizedString(forKey: "capture.saveFailed.title"),
                body: VLMSnapperLocalization.localizedString(forKey: "capture.saveFailed.body")
            )
        }
    }

    private func presentCaptureActionFailure(title: String, body: String) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        _ = await captureOverlayController.presentAlert(alert, onDisplay: confirmedSelectionDisplayID)
    }

    /// A press on Extract or Translate: the first one fixes the selection, then a press either starts a
    /// request or shows the result the operation already has (v1-core::REQ-011).
    private func handleOperationPress(_ operation: WorkspaceOperationKind, originalPNG: Data) {
        guard runningResultOperation == nil else { return }
        if workspaceSession == nil {
            workspaceSession = OperationWorkspaceSession(
                originalPNG: originalPNG,
                runner: PersistedOperationWorkspaceRunner(
                    screenshotStore: screenshotStore,
                    historyStore: historyStore,
                    provider: providerStreamer,
                    visionCompatibility: providerCoordinator,
                    modelListRefresh: providerCoordinator
                ),
                activeGate: operationGate
            )
            captureOverlayController.lockSelection()
        }
        guard wouldStartRequest(operation) else {
            shownResultOperation = operation
            refreshResultSurfaces()
            return
        }
        guard !hasUnsavedWorkspaceResult else { return }
        startResultRequest(operation, targetLanguage: selectedTargetLanguageCode)
    }

    private func resultSlot(_ operation: WorkspaceOperationKind) -> WorkspaceOperationSlot {
        if let code = localResultFailures[operation] {
            return WorkspaceOperationSlot(attempt: .failed(code: code))
        }
        return operation == .extract ? workspaceSnapshot.extract : workspaceSnapshot.translate
    }

    private func wouldStartRequest(_ operation: WorkspaceOperationKind) -> Bool {
        if resultSlot(operation).attempt == .neverStarted { return true }
        return operation == .translate && workspaceTargetLanguageCode != selectedTargetLanguageCode
    }

    private func startResultRequest(_ operation: WorkspaceOperationKind, targetLanguage: String) {
        guard let session = workspaceSession, let owner = captureLease else { return }
        shownResultOperation = operation
        guard let selection = providerSelection else {
            // With the model cleared, choosing another is what helps. Waiting and retrying is not.
            if case .pendingModel = providerReadiness {
                localResultFailures[operation] = ProviderAdapterError.modelUnavailable.normalizedCode
            } else {
                localResultFailures[operation] = ProviderAdapterError.providerUnavailable.normalizedCode
            }
            refreshResultSurfaces()
            return
        }
        localResultFailures[operation] = nil
        if operation == .translate { workspaceTargetLanguageCode = targetLanguage }
        workspaceProviderSummary = providerSummary(for: selection)
        runningResultOperation = operation
        refreshResultSurfaces()
        resultRunTask = Task { [weak self] in
            guard let self else { return }
            let accepted = await workflow.performInCapture(owner: owner) {
                await self.runResultRequest(operation, in: session, selection: selection, targetLanguage: targetLanguage)
            }
            await syncWorkspaceSnapshot(session)
            let snapshot = await session.snapshot()
            await reloadProviderIfRequestChangedModels(operation == .extract ? snapshot.extract : snapshot.translate)
            guard workspaceSession === session else { return }
            if !accepted { localResultFailures[operation] = "operation_failed" }
            runningResultOperation = nil
            refreshResultSurfaces()
        }
    }

    private func runResultRequest(
        _ operation: WorkspaceOperationKind,
        in session: OperationWorkspaceSession,
        selection: ProviderSelection,
        targetLanguage: String
    ) async {
        await session.select(operation)
        let observation = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncWorkspaceSnapshot(session)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        defer { observation.cancel() }
        do {
            try await session.startSelectedOperation(selection: selection, targetLanguage: targetLanguage)
        } catch OperationWorkspaceSessionError.busy, OperationWorkspaceSessionError.unsavedResultRequiresSave {
            localResultFailures[operation] = "operation_failed"
        } catch {
            // The session recorded the failure or cancellation in the operation's slot.
        }
        await syncWorkspaceSnapshot(session)
        await recordResultDiagnostic(session, operation: operation)
        await refreshHistory()
    }

    private func syncWorkspaceSnapshot(_ session: OperationWorkspaceSession) async {
        let snapshot = await session.snapshot()
        let hasUnsaved = await session.hasUnsavedResult
        guard workspaceSession === session else { return }
        workspaceSnapshot = snapshot
        hasUnsavedWorkspaceResult = hasUnsaved
        refreshResultSurfaces()
    }

    /// Brings the toolbar and the result box in line with the session. The toolbar moves aside only when
    /// the box opens or closes, not when the box is dragged (v1-core::REQ-013/AC-06).
    private func refreshResultSurfaces() {
        captureToolbarState.currentOperation = shownResultOperation
        captureToolbarState.isRequestRunning = runningResultOperation != nil
        captureToolbarState.unavailableOperations = hasUnsavedWorkspaceResult
            ? Set(WorkspaceOperationKind.allCases.filter(wouldStartRequest))
            : []
        guard let frame = confirmedSelectionFrame, let screen = confirmedSelectionScreen else { return }
        guard let operation = shownResultOperation else {
            guard resultBoxController.frame != nil else { return }
            resultBoxController.hide()
            captureToolbarController.reposition(below: frame, on: screen)
            return
        }
        let presentation = CaptureResultBoxPresentation(
            operation: operation,
            targetLanguageName: VLMSnapperLocalization.localizedLanguageName(
                for: workspaceTargetLanguageCode ?? selectedTargetLanguageCode
            ),
            providerSummary: workspaceProviderSummary ?? providerSummary,
            slot: resultSlot(operation),
            retryAvailable: !hasUnsavedWorkspaceResult
        )
        if resultBoxController.state.presentation != presentation {
            resultBoxController.state.presentation = presentation
        }
        guard resultBoxController.frame == nil, captureRequest == nil else { return }
        resultBoxController.show(on: screen)
        captureToolbarController.reposition(below: frame, on: screen, avoiding: resultBoxController.frame)
        captureToolbarController.orderFront()
    }

    func changeTargetLanguage(_ code: String) {
        guard TargetLanguageCatalog.standard.contains(code) else { return }
        selectedTargetLanguageCode = code
        defaults.set(code, forKey: "targetLanguageCode")
        refreshResultSurfaces()
        // SwiftUI applies the new abbreviation on its next update; its width changes the toolbar's.
        DispatchQueue.main.async { [weak self] in
            guard let self, let frame = confirmedSelectionFrame, let screen = confirmedSelectionScreen else { return }
            captureToolbarController.reposition(below: frame, on: screen, avoiding: resultBoxController.frame)
        }
    }

    private func retryShownResult() {
        guard !captureActionInProgress, runningResultOperation == nil, !hasUnsavedWorkspaceResult,
              let operation = shownResultOperation else { return }
        startResultRequest(operation, targetLanguage: workspaceTargetLanguageCode ?? selectedTargetLanguageCode)
    }

    private func retrySavingShownResult() async {
        guard !captureActionInProgress, let session = workspaceSession, let operation = shownResultOperation else { return }
        await session.select(operation)
        try? await session.retrySavingSelectedResult()
        await syncWorkspaceSnapshot(session)
        await refreshHistory()
    }

    /// Closes only the box; a running request ends with it (v1-core::REQ-012/AC-02). An unsaved result
    /// stays in the session until the capture ends.
    private func closeResultBox() {
        guard !captureActionInProgress, let session = workspaceSession else { return }
        shownResultOperation = nil
        refreshResultSurfaces()
        // A request task that has not reached the session yet must not start after this.
        resultRunTask?.cancel()
        Task { [weak self] in
            _ = await session.close()
            await self?.syncWorkspaceSnapshot(session)
        }
    }

    /// Leaves the capture on the user's request. An unsaved result asks first, on the overlay.
    private func requestCaptureExit(generation: UUID) async {
        guard activeCaptureGeneration == generation, captureRequest?.generation != generation else {
            await cancelCapture(generation: generation)
            return
        }
        guard await closeResultSessionForExit() else { return }
        await cancelCapture(generation: generation)
    }

    /// Cancels a running request and settles an unsaved result. Returns `false` if the user keeps it.
    private func closeResultSessionForExit() async -> Bool {
        guard let session = workspaceSession else { return true }
        guard await session.close() == .confirmDiscardUnsavedResult else { return true }
        // The toolbar and the box stay clickable beside the sheet: it is one question at a time.
        guard !isConfirmingResultExit else { return false }
        isConfirmingResultExit = true
        defer { isConfirmingResultExit = false }
        captureActionInProgress = true
        let response = await captureOverlayController.presentAlert(
            UnsavedResultConfirmation.makeAlert(),
            onDisplay: confirmedSelectionDisplayID
        )
        captureActionInProgress = false
        guard response == .alertFirstButtonReturn else { return false }
        await session.discardUnsavedResults()
        return true
    }

    /// The selection's display is gone, so the box has nowhere to stay (v1-core::REQ-012/AC-06).
    private func endCaptureAfterDisplayLoss(generation: UUID) async {
        let session = workspaceSession
        let hadUnsavedResult = await session?.hasUnsavedResult ?? false
        await session?.discardUnsavedResults()
        await cancelCapture(generation: generation)
        if hadUnsavedResult {
            await dependencies.captureResultLossNotifier.unsavedResultDiscarded()
        }
    }

    private func resetResultSurfaces() {
        workspaceSession = nil
        workspaceSnapshot = OperationWorkspaceSnapshot(
            selectedOperation: .extract,
            extract: WorkspaceOperationSlot(),
            translate: WorkspaceOperationSlot()
        )
        shownResultOperation = nil
        runningResultOperation = nil
        resultRunTask = nil
        hasUnsavedWorkspaceResult = false
        localResultFailures = [:]
        workspaceProviderSummary = nil
        workspaceTargetLanguageCode = nil
        confirmedSelectionFrame = nil
        confirmedSelectionScreen = nil
        captureToolbarState.currentOperation = nil
        captureToolbarState.isRequestRunning = false
        captureToolbarState.unavailableOperations = []
        resultBoxController.reset()
    }

    private func cancelCapture(generation: UUID) async {
        if let request = captureRequest, request.generation == generation {
            await abandonPendingCapture(request)
            return
        }
        guard activeCaptureGeneration == generation else { return }
        // A pending replacement shares this selection's activity, which ends here,
        // so it can never commit; clear it now rather than when its freeze returns.
        let replacement = captureRequest
        captureRequest = nil
        let session = captureSelectionSession
        let lease = captureLease
        let resultSession = workspaceSession
        let resultRun = resultRunTask
        captureLease = nil
        cancelCaptureSurfaces()
        await session?.cancel()
        // A canceled request has saved that state before the next activity can begin. A request task that
        // has not reached the session yet must not start after this.
        resultRun?.cancel()
        _ = await resultSession?.close()
        await resultRun?.value
        if let lease { await providerCoordinator.release(lease) }
        await replacement?.workspaceToRetire?.restoreAfterCaptureFailure()
    }

    private func cancelCaptureSurfaces() {
        dependencies.displayMonitor.stop()
        captureDisplayGeometries.removeAll()
        captureOverlayController.close()
        captureToolbarController.hide()
        resetResultSurfaces()
        captureSelectionSession = nil
        confirmedSelectionDisplayID = nil
        confirmedSelectionPNG = nil
        selectionCropTask = nil
        captureActionInProgress = false
        activeCaptureGeneration = nil
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

    private func providerSummary(for selection: ProviderSelection) -> String {
        let providerName = ProviderID(rawValue: selection.providerID).map {
            switch $0 {
            case .deepSeek: "DeepSeek"
            case .openAI: "OpenAI"
            case .gemini: "Gemini"
            }
        } ?? selection.providerID
        return "\(providerName) · \(selection.modelID)"
    }

    private var targetLanguageOptions: [TargetLanguageOption] {
        TargetLanguageCatalog.standard.codes.map {
            TargetLanguageOption(
                code: $0,
                name: VLMSnapperLocalization.localizedLanguageName(for: $0)
            )
        }
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

    private func recordResultDiagnostic(
        _ session: OperationWorkspaceSession,
        operation: WorkspaceOperationKind
    ) async {
        guard case let .ready(provider, modelID) = providerReadiness else { return }
        let snapshot = await session.snapshot()
        let attempt = operation == .extract ? snapshot.extract.attempt : snapshot.translate.attempt
        let stage: DiagnosticRequestStage
        let errorCode: String?
        switch attempt {
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
        historyRetry.allowsStart = providerSelection != nil && providerSnapshot.activity == nil
            && !historyRetry.isRunning && historyRetry.slot.unsavedResult == nil
        onSnapshotChange?()
    }
}
