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
    @Published var selectedOperation: WorkspaceOperationKind = .extract
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
    var onRetireManagementCenter: (@MainActor (@escaping @MainActor () -> Void) -> Void)?
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
    private var captureRequest: CaptureRequest?
    private var activeCaptureGeneration: UUID?
    private var captureLease: UUID?
    private var workspaceSession: OperationWorkspaceSession?
    private var workspaceSnapshot = OperationWorkspaceSnapshot(
        selectedOperation: .extract,
        extract: WorkspaceOperationSlot(),
        translate: WorkspaceOperationSlot()
    )
    private var originalImage: NSImage?
    private var workspaceProviderSummary: String?
    private var workspaceTargetLanguageCode: String?
    private var workspaceAllowsOperationStart = true
    private var historyOpenGeneration: UUID?
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
        dependencies: ApplicationModelDependencies
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
                if self.workspaceSession != nil { self.showResultWorkspace() }
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
            callbacks: onboardingCallbacks()
        )
    }

    func managementCallbacks() -> ManagementCenterCallbacks {
        ManagementCenterCallbacks(
            onSelectRecord: { [weak self] id in
                Task { await self?.selectHistoryRecord(id) }
            },
            onOpenRecord: { [weak self] id in
                Task { await self?.openHistoryRecord(id) }
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
                }
                credentialEditor.attachLoadTask(task, for: request)
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
        if let request = captureRequest {
            captureRequest = nil
            await request.workspaceToRetire?.restoreAfterCaptureFailure()
        }
        if let activeCaptureGeneration {
            await cancelCapture(generation: activeCaptureGeneration)
        }
        if workspaceSession != nil {
            let disposition = await closeWorkspace()
            if disposition == .confirmDiscardUnsavedResult {
                guard UnsavedResultConfirmation.confirm() else { return false }
                await discardUnsavedWorkspace()
            }
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

    private func openHistoryRecord(_ id: UUID) async {
        let generation = UUID()
        historyOpenGeneration = generation
        guard let record = try? await historyStore.historyRecord(id: id) else {
            if historyOpenGeneration == generation {
                historyOpenGeneration = nil
            }
            return
        }
        let originalPNG = try? await screenshotStore.loadIfOwned(
            record.operation.screenshot
        )
        let operation: WorkspaceOperationKind = record.operation.kind == .extract
            ? .extract
            : .translate
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: historyStore,
            provider: providerStreamer
        )
        let session = OperationWorkspaceSession(
            originalPNG: originalPNG ?? Data(),
            runner: runner,
            activeGate: operationGate
        )
        await session.select(operation)
        guard historyOpenGeneration == generation else { return }
        if let workspaceSession,
           await !workspaceSession.reserveReplacementWithSavedHistory() {
            historyOpenGeneration = nil
            resultController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        historyOpenGeneration = nil
        workspaceSession = session
        selectedOperation = operation
        workspaceSnapshot = OperationWorkspaceSnapshot(restoring: record.operation)
        originalImage = originalPNG.flatMap(NSImage.init(data:))
        workspaceProviderSummary = providerSummary(for: record.operation.selection)
        workspaceTargetLanguageCode = record.operation.targetLanguage
        workspaceAllowsOperationStart = originalPNG != nil
        let present: @MainActor @Sendable () -> Void = { [weak self] in
            self?.showResultWorkspace(bringToFront: true)
        }
        if let onRetireManagementCenter {
            onRetireManagementCenter(present)
        } else {
            present()
        }
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
                presentOperation: { [weak self] in
                    self?.resultController.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
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
                        guard preparation == .beginCapture else {
                            if preparation == .presentWorkspace {
                                resultController.window?.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
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
        let result = await captureCoordinator.startCapture()
        guard captureRequest?.generation == request.generation else {
            if case let .ready(session, _, _) = result {
                await session.cancel()
            }
            return false
        }
        switch result {
        case let .ready(session, frozenDisplays, _):
            guard captureRequestCanCommit(request) else {
                captureRequest = nil
                await session.cancel()
                await request.workspaceToRetire?.restoreAfterCaptureFailure()
                return false
            }
            let replacementPresented = captureOverlayController.replace(
                displays: frozenDisplays,
                onSelection: { [weak self] selection in
                    Task {
                        await self?.finishSelection(
                            selection,
                            generation: request.generation
                        )
                    }
                },
                onCancel: { [weak self] in
                    Task {
                        await self?.cancelCapture(
                            generation: request.generation
                        )
                    }
                }
            )
            guard replacementPresented else {
                captureRequest = nil
                await session.cancel()
                await request.workspaceToRetire?.restoreAfterCaptureFailure()
                await releaseFailedCaptureIfNeeded(request)
                showCaptureFailure()
                return false
            }
            let retiredSelectionSession = captureSelectionSession
            captureSelectionSession = session
            activeCaptureGeneration = request.generation
            captureRequest = nil
            captureToolbarController.hide()
            if let workspaceToRetire = request.workspaceToRetire,
               workspaceSession === workspaceToRetire {
                workspaceSession = nil
                originalImage = nil
                resetWorkspacePresentation()
                resultController.hideForCapture()
            }
            onRetireCaptureSources?()
            await retiredSelectionSession?.cancel()
            return true
        case .permissionRequired:
            captureRequest = nil
            await request.workspaceToRetire?.restoreAfterCaptureFailure()
            permission = .unavailable
            publish()
            onShowOnboarding?()
        case .allDisplaysFailed:
            captureRequest = nil
            await request.workspaceToRetire?.restoreAfterCaptureFailure()
            await releaseFailedCaptureIfNeeded(request)
            showCaptureFailure()
        }
        return false
    }

    private func releaseFailedCaptureIfNeeded(_ request: CaptureRequest) async {
        // A retry from the failure alert must not inherit a failed new attempt's
        // lease. A replacement failure still belongs to the existing selection.
        guard activeCaptureGeneration == nil, captureLease == request.lease else { return }
        captureLease = nil
        await providerCoordinator.release(request.lease)
    }

    private func captureRequestCanCommit(_ request: CaptureRequest) -> Bool {
        guard captureLease == request.lease else { return false }
        if let workspaceToRetire = request.workspaceToRetire {
            return workspaceSession === workspaceToRetire
        }
        return workspaceSession == nil
    }

    private func showCaptureFailure() {
        let alert = NSAlert()
        captureOverlayController.prepareFailurePresentation(alert)
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
            capture()
        }
    }

    private func finishSelection(
        _ selection: FrozenCaptureOverlayController.Selection,
        generation: UUID
    ) async {
        guard activeCaptureGeneration == generation,
              let captureSelectionSession,
              let currentScreen = NSScreen.screens.first(where: { screen in
                  guard let number = screen.deviceDescription[
                      NSDeviceDescriptionKey("NSScreenNumber")
                  ] as? NSNumber else {
                      return false
                  }
                  return number.uint32Value == selection.displayID
              }),
              let currentGeometry = currentCaptureDisplayGeometry(
                  for: selection.displayID,
                  pointPixelScale: Float(currentScreen.backingScaleFactor)
              )
        else {
            await cancelCapture(generation: generation)
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
            await cancelCapture(generation: generation)
        }
    }

    private func showCaptureToolbar(
        originalPNG: Data,
        selectionFrame: CGRect,
        screen: NSScreen
    ) {
        guard let generation = activeCaptureGeneration else { return }
        captureToolbarController.show(
            content: CaptureOperationToolbar(
                operation: binding(\.selectedOperation),
                targetLanguageCode: targetLanguageBinding,
                targetLanguages: targetLanguageOptions,
                providerSummary: providerSummary,
                onStart: { [weak self] operation in
                    guard self?.activeCaptureGeneration == generation else { return }
                    self?.openWorkspace(originalPNG: originalPNG, operation: operation)
                },
                onCancel: { [weak self] in
                    Task {
                        await self?.cancelCapture(generation: generation)
                    }
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
        guard let owner = captureLease, providerSelection != nil else { return }
        Task {
            _ = try? await workflow.performOperation(continuingCapture: owner) {
                captureLease = nil
                await runCapturedWorkspace(originalPNG: originalPNG, operation: operation)
            }
        }
    }

    private func runCapturedWorkspace(
        originalPNG: Data,
        operation: WorkspaceOperationKind
    ) async {
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
        workspaceProviderSummary = providerSummary
        workspaceTargetLanguageCode = selectedTargetLanguageCode
        workspaceAllowsOperationStart = true
        await session.select(operation)
        workspaceSnapshot = await session.snapshot()
        showResultWorkspace(bringToFront: true)
        let previousAttempt = selectedAttempt
        let run = Task { [weak self] in
            guard let self else { return }
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
                _ = try? await run.value
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

    private func showResultWorkspace(bringToFront: Bool = false) {
        let content = ResultWorkspaceView(
            operation: binding(\.selectedOperation),
            snapshot: workspaceSnapshot,
            originalImage: originalImage,
            providerSummary: workspaceProviderSummary ?? providerSummary,
            targetLanguage: workspaceTargetLanguageName,
            allowsOperationStart: workspaceAllowsOperationStart && providerSnapshot.activity == nil,
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
        if bringToFront {
            resultController.present(content: content)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            resultController.update(content: content)
        }
    }

    private func rerunWorkspace(_ operation: WorkspaceOperationKind) async {
        _ = try? await workflow.performOperation {
            await runExistingWorkspace(operation)
        }
    }

    private func runExistingWorkspace(_ operation: WorkspaceOperationKind) async {
        guard workspaceAllowsOperationStart,
              let workspaceSession,
              let providerSelection else { return }
        workspaceProviderSummary = providerSummary
        workspaceTargetLanguageCode = selectedTargetLanguageCode
        await workspaceSession.select(operation)
        selectedOperation = operation
        workspaceSnapshot = await workspaceSession.snapshot()
        let previousAttempt = selectedAttempt
        let run = Task { [weak self] in
            guard let self else { return }
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
                _ = try? await run.value
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
            resetWorkspacePresentation()
        }
        return disposition
    }

    private func discardUnsavedWorkspace() async {
        await workspaceSession?.discardUnsavedResults()
        workspaceSession = nil
        originalImage = nil
        resetWorkspacePresentation()
    }

    private func cancelCapture(generation: UUID) async {
        guard activeCaptureGeneration == generation else { return }
        let session = captureSelectionSession
        let lease = captureLease
        captureLease = nil
        cancelCaptureSurfaces()
        await session?.cancel()
        if let lease { await providerCoordinator.release(lease) }
    }

    private func cancelCaptureSurfaces() {
        captureOverlayController.close()
        captureToolbarController.hide()
        captureSelectionSession = nil
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

    private var workspaceTargetLanguageName: String {
        VLMSnapperLocalization.localizedLanguageName(
            for: workspaceTargetLanguageCode ?? selectedTargetLanguageCode
        )
    }

    private func resetWorkspacePresentation() {
        workspaceProviderSummary = nil
        workspaceTargetLanguageCode = nil
        workspaceAllowsOperationStart = true
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
