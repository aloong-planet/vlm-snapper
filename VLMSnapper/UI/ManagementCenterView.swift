import AppKit
import SwiftUI
import VLMSnapperCore

public struct ProviderSettingsConfiguration {
    public let snapshot: ProviderSetupSnapshot
    public let configurations: [ProviderID: ProviderConfiguration]
    public let apiKey: Binding<String>
    public let pendingModelID: Binding<String?>
    public let onSelectProvider: (ProviderID) -> Void
    public let onValidate: () -> Void
    public let onRefresh: () -> Void
    public let onSelectModel: (String) -> Void
    public let onDone: () -> Void

    public init(
        snapshot: ProviderSetupSnapshot,
        configurations: [ProviderID: ProviderConfiguration] = [:],
        apiKey: Binding<String>,
        pendingModelID: Binding<String?>,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidate: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onDone: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.configurations = configurations
        self.apiKey = apiKey
        self.pendingModelID = pendingModelID
        self.onSelectProvider = onSelectProvider
        self.onValidate = onValidate
        self.onRefresh = onRefresh
        self.onSelectModel = onSelectModel
        self.onDone = onDone
    }
}

public struct GeneralSettingsSnapshot: Equatable, Sendable {
    public let language: ApplicationLanguagePreference
    public let languageRestartRequired: Bool
    public let loginItemEnabled: Bool
    public let loginItemState: LoginItemState
    public let automaticallyChecksForUpdates: Bool
    public let updateState: UpdateLifecycleState
    public let retentionShorteningRecordCount: Int?
    public let captureShortcut: GlobalShortcut
    public let shortcutFailure: ShortcutSettingsFailure?

    public init(
        language: ApplicationLanguagePreference = .system,
        languageRestartRequired: Bool = false,
        loginItemEnabled: Bool = true,
        loginItemState: LoginItemState = .enabled,
        automaticallyChecksForUpdates: Bool = true,
        updateState: UpdateLifecycleState = .idle,
        retentionShorteningRecordCount: Int? = nil,
        captureShortcut: GlobalShortcut = .defaultCapture,
        shortcutFailure: ShortcutSettingsFailure? = nil
    ) {
        self.language = language
        self.languageRestartRequired = languageRestartRequired
        self.loginItemEnabled = loginItemEnabled
        self.loginItemState = loginItemState
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.updateState = updateState
        self.retentionShorteningRecordCount = retentionShorteningRecordCount
        self.captureShortcut = captureShortcut
        self.shortcutFailure = shortcutFailure
    }
}

public enum ShortcutSettingsFailure: Equatable, Sendable {
    case invalid
    case conflict
    case registrationFailed
}

public struct ManagementCenterCallbacks {
    public let onSelectRecord: (UUID) -> Void
    public let onSetPinned: (UUID, Bool) -> Void
    public let onDelete: (UUID) -> Void
    public let onClearHistory: (Bool) -> Void
    public let onRetryCleanup: () -> Void
    public let onRetentionChange: (HistoryRetentionPeriod) -> Void
    public let onConfirmRetentionShortening: () -> Void
    public let onCancelRetentionShortening: () -> Void
    public let onLanguageChange: (ApplicationLanguagePreference) -> Void
    public let onRestartForLanguageChange: () -> Void
    public let onLoginItemChange: (Bool) -> Void
    public let onShortcutChange: (GlobalShortcut) -> Void
    public let onOpenLoginItemSettings: () -> Void
    public let onAutomaticUpdateChecksChange: (Bool) -> Void
    public let onCheckUpdates: () -> Void
    public let onDownloadUpdate: () -> Void
    public let onOpenUpdateInformation: (URL) -> Void
    public let onInstallUpdate: () -> Void
    public let onExportDiagnostics: () -> Void

    public init(
        onSelectRecord: @escaping (UUID) -> Void = { _ in },
        onSetPinned: @escaping (UUID, Bool) -> Void = { _, _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onClearHistory: @escaping (Bool) -> Void = { _ in },
        onRetryCleanup: @escaping () -> Void = {},
        onRetentionChange: @escaping (HistoryRetentionPeriod) -> Void = { _ in },
        onConfirmRetentionShortening: @escaping () -> Void = {},
        onCancelRetentionShortening: @escaping () -> Void = {},
        onLanguageChange: @escaping (ApplicationLanguagePreference) -> Void = { _ in },
        onRestartForLanguageChange: @escaping () -> Void = {},
        onLoginItemChange: @escaping (Bool) -> Void = { _ in },
        onShortcutChange: @escaping (GlobalShortcut) -> Void = { _ in },
        onOpenLoginItemSettings: @escaping () -> Void = {},
        onAutomaticUpdateChecksChange: @escaping (Bool) -> Void = { _ in },
        onCheckUpdates: @escaping () -> Void = {},
        onDownloadUpdate: @escaping () -> Void = {},
        onOpenUpdateInformation: @escaping (URL) -> Void = { _ in },
        onInstallUpdate: @escaping () -> Void = {},
        onExportDiagnostics: @escaping () -> Void = {}
    ) {
        self.onSelectRecord = onSelectRecord
        self.onSetPinned = onSetPinned
        self.onDelete = onDelete
        self.onClearHistory = onClearHistory
        self.onRetryCleanup = onRetryCleanup
        self.onRetentionChange = onRetentionChange
        self.onConfirmRetentionShortening = onConfirmRetentionShortening
        self.onCancelRetentionShortening = onCancelRetentionShortening
        self.onLanguageChange = onLanguageChange
        self.onRestartForLanguageChange = onRestartForLanguageChange
        self.onLoginItemChange = onLoginItemChange
        self.onShortcutChange = onShortcutChange
        self.onOpenLoginItemSettings = onOpenLoginItemSettings
        self.onAutomaticUpdateChecksChange = onAutomaticUpdateChecksChange
        self.onCheckUpdates = onCheckUpdates
        self.onDownloadUpdate = onDownloadUpdate
        self.onOpenUpdateInformation = onOpenUpdateInformation
        self.onInstallUpdate = onInstallUpdate
        self.onExportDiagnostics = onExportDiagnostics
    }
}

public struct ManagementCenterView: View {
    private let records: [HistoryRecord]
    private let selectedImage: NSImage?
    private let cleanupFailureCount: Int
    private let callbacks: ManagementCenterCallbacks
    private let settings: GeneralSettingsSnapshot
    private let providerSettings: ProviderSettingsConfiguration?
    @State private var destination: ManagementCenterDestination
    @State private var kind: HistoryOperationKindFilter = .all
    @State private var searchText: String
    @State private var selectedRecordID: UUID?
    @State private var retention: HistoryRetentionPeriod
    @State private var pinnedOnly = false
    @State private var showGeneralSettings = false
    @State private var pendingDeletion: HistoryRecord?
    @State private var showingClearConfirmation = false
    @State private var showingProviderSetup = false

    public init(
        destination: ManagementCenterDestination,
        records: [HistoryRecord],
        selectedRecordID: UUID? = nil,
        selectedImage: NSImage? = nil,
        cleanupFailureCount: Int = 0,
        searchText: String = "",
        showsGeneralSettings: Bool? = nil,
        retention: HistoryRetentionPeriod = .thirtyDays,
        settings: GeneralSettingsSnapshot = GeneralSettingsSnapshot(),
        providerSettings: ProviderSettingsConfiguration? = nil,
        callbacks: ManagementCenterCallbacks = ManagementCenterCallbacks()
    ) {
        self.records = records
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.callbacks = callbacks
        self.settings = settings
        self.providerSettings = providerSettings
        _destination = State(initialValue: destination)
        _selectedRecordID = State(initialValue: selectedRecordID ?? records.first?.id)
        _searchText = State(initialValue: searchText)
        _retention = State(initialValue: retention)
        _showGeneralSettings = State(
            initialValue: showsGeneralSettings ?? (destination == .settings)
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                contentToolbar
                Divider()
                if destination == .history { historyContent } else { settingsContent }
            }
        }
        .background(VLMSnapperTheme.window)
        .frame(minWidth: 920, minHeight: 620)
        .onChange(of: kind) { _, _ in selectFirstVisibleRecord() }
        .onChange(of: searchText) { _, _ in selectFirstVisibleRecord() }
        .onChange(of: pinnedOnly) { _, _ in selectFirstVisibleRecord() }
        .confirmationDialog(
            VLMSnapperStrings.historyDeleteConfirm,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { record in
            Button(VLMSnapperStrings.historyDelete, role: .destructive) {
                callbacks.onDelete(record.id)
                pendingDeletion = nil
            }
        }
        .confirmationDialog(
            VLMSnapperStrings.historyClearConfirm,
            isPresented: $showingClearConfirmation
        ) {
            Button(VLMSnapperStrings.historyClearUnpinned, role: .destructive) {
                callbacks.onClearHistory(false)
            }
            Button(VLMSnapperStrings.historyClearIncludingPinned, role: .destructive) {
                callbacks.onClearHistory(true)
            }
        }
        .confirmationDialog(
            retentionShorteningTitle,
            isPresented: Binding(
                get: { settings.retentionShorteningRecordCount != nil },
                set: { if !$0 { callbacks.onCancelRetentionShortening() } }
            )
        ) {
            Button(
                VLMSnapperStrings.historyRetentionShorteningAction,
                role: .destructive,
                action: callbacks.onConfirmRetentionShortening
            )
        }
        .sheet(isPresented: $showingProviderSetup) {
            if let providerSettings {
                ProviderSetupView(
                    snapshot: providerSettings.snapshot,
                    configurations: providerSettings.configurations,
                    apiKey: providerSettings.apiKey,
                    pendingModelID: providerSettings.pendingModelID,
                    onSelectProvider: providerSettings.onSelectProvider,
                    onValidate: providerSettings.onValidate,
                    onRefresh: providerSettings.onRefresh,
                    onSelectModel: providerSettings.onSelectModel,
                    onCancel: { showingProviderSetup = false },
                    onDone: {
                        providerSettings.onDone()
                        showingProviderSetup = false
                    }
                )
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            navButton(VLMSnapperStrings.menuHistory, icon: .history, selected: destination == .history && !pinnedOnly) {
                destination = .history
                pinnedOnly = false
            }
            navButton(VLMSnapperStrings.historyPinned, icon: .pinned, selected: destination == .history && pinnedOnly) {
                destination = .history
                kind = .all
                pinnedOnly = true
            }
            Divider().padding(.vertical, 6)
            navButton(VLMSnapperStrings.historyProviderSettings, icon: .providerList, selected: destination == .settings && !showGeneralSettings) {
                destination = .settings
                showGeneralSettings = false
            }
            navButton(VLMSnapperStrings.historyGeneralSettings, icon: .general, selected: destination == .settings && showGeneralSettings) {
                destination = .settings
                showGeneralSettings = true
            }
            Spacer()
        }
        .padding(12)
        .frame(width: ManagementCenterMetrics.sidebarWidth)
        .background(VLMSnapperTheme.subtleSurface)
    }

    private var contentToolbar: some View {
        HStack(spacing: 16) {
            if destination == .history {
                Picker(VLMSnapperStrings.operationSelector, selection: $kind) {
                    Text(VLMSnapperStrings.historyAll).tag(HistoryOperationKindFilter.all)
                    Text(VLMSnapperStrings.extract).tag(HistoryOperationKindFilter.extract)
                    Text(VLMSnapperStrings.translate).tag(HistoryOperationKindFilter.translate)
                }
                .pickerStyle(.segmented)
                .frame(width: 286)
                Spacer()
                HStack(spacing: 7) {
                    VLMSnapperIcon.search.image.foregroundStyle(VLMSnapperTheme.secondaryText)
                    TextField(VLMSnapperStrings.historySearch, text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(width: 290, height: 31)
                .background(VLMSnapperTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(VLMSnapperTheme.border))
            } else {
                Text(VLMSnapperStrings.menuSettings).font(.headline)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: ManagementCenterMetrics.titlebarHeight)
    }

    private var historyContent: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if cleanupFailureCount > 0 {
                    Button(action: callbacks.onRetryCleanup) {
                        Label(VLMSnapperStrings.historyCleanupFailures, systemImage: VLMSnapperIcon.warningBadge.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VLMSnapperTheme.warning)
                    .padding(10)
                }
                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        VLMSnapperStrings.historyEmptyTitle,
                        systemImage: VLMSnapperIcon.search.rawValue,
                        description: Text(VLMSnapperStrings.historyEmptyBody)
                    )
                } else {
                    List(filteredRecords, selection: $selectedRecordID) { record in
                        historyRow(record).tag(record.id)
                    }
                    .onChange(of: selectedRecordID) { _, value in
                        if let value { callbacks.onSelectRecord(value) }
                    }
                }
                Divider()
                Button(VLMSnapperStrings.historyClear) { showingClearConfirmation = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(VLMSnapperTheme.destructive)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 330)
            Divider()
            detail
        }
    }

    private var settingsContent: some View {
        Form {
            if showGeneralSettings {
                Section {
                    settingsRow(
                        title: VLMSnapperStrings.languageTitle,
                        detail: VLMSnapperStrings.languageHint
                    ) {
                        Picker("", selection: languageBinding) {
                            Text(VLMSnapperStrings.languageSystem)
                                .tag(ApplicationLanguagePreference.system)
                            Text(VLMSnapperStrings.languageSimplifiedChinese)
                                .tag(ApplicationLanguagePreference.simplifiedChinese)
                            Text(VLMSnapperStrings.languageEnglish)
                                .tag(ApplicationLanguagePreference.english)
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    if settings.languageRestartRequired {
                        settingsRow(
                            title: VLMSnapperStrings.languageRestartRequired,
                            detail: VLMSnapperStrings.languageRestartHint
                        ) {
                            Button(
                                VLMSnapperStrings.restart,
                                action: callbacks.onRestartForLanguageChange
                            )
                        }
                    }
                    settingsRow(
                        title: VLMSnapperStrings.shortcutTitle,
                        detail: VLMSnapperStrings.shortcutHint
                    ) {
                        GlobalShortcutRecorder(
                            shortcut: settings.captureShortcut,
                            onChange: callbacks.onShortcutChange
                        )
                        .frame(width: 150, height: 28)
                    }
                    if let shortcutFailure = settings.shortcutFailure {
                        Text(shortcutFailureMessage(shortcutFailure))
                            .font(.caption)
                            .foregroundStyle(VLMSnapperTheme.destructive)
                    }
                    settingsRow(
                        title: VLMSnapperStrings.loginItemTitle,
                        detail: VLMSnapperStrings.loginItemHint
                    ) {
                        Toggle("", isOn: loginItemBinding).labelsHidden()
                    }
                    if settings.loginItemState == .requiresApproval {
                        Button(
                            VLMSnapperStrings.loginItemApproval,
                            action: callbacks.onOpenLoginItemSettings
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(VLMSnapperStrings.historyGeneralSettings)
                        Text(VLMSnapperStrings.generalSettingsSubtitle)
                            .font(.caption)
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                    }
                }
                Section(VLMSnapperStrings.updateSection) {
                    settingsRow(
                        title: VLMSnapperStrings.updateAutomaticChecks,
                        detail: VLMSnapperStrings.updateAutomaticChecksHint
                    ) {
                        Toggle("", isOn: automaticChecksBinding).labelsHidden()
                    }
                    updateStatus
                }
                Section(VLMSnapperStrings.historyRetention) {
                    Picker(VLMSnapperStrings.historyRetention, selection: $retention) {
                        ForEach(HistoryRetentionPeriod.allCases, id: \.self) { period in
                            Text(String(format: VLMSnapperStrings.historyRetentionDaysFormat, period.rawValue))
                                .tag(period)
                        }
                    }
                    .onChange(of: retention) { _, value in callbacks.onRetentionChange(value) }
                    Text(VLMSnapperStrings.historyRetentionHint)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
                Section(VLMSnapperStrings.diagnosticsSection) {
                    settingsRow(
                        title: VLMSnapperStrings.diagnosticsTitle,
                        detail: VLMSnapperStrings.diagnosticsHint
                    ) {
                        Button(
                            VLMSnapperStrings.diagnosticsExport,
                            action: callbacks.onExportDiagnostics
                        )
                    }
                }
            } else {
                Section {
                    ForEach([ProviderID.deepSeek, .openAI, .gemini], id: \.self) { provider in
                        providerSettingsRow(provider)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(VLMSnapperStrings.historyProviderSettings)
                        Text(VLMSnapperStrings.providerSetupSubtitle)
                            .font(.caption)
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    private func providerSettingsRow(_ provider: ProviderID) -> some View {
        HStack(spacing: 14) {
            VLMSnapperIcon.provider.image
                .foregroundStyle(VLMSnapperTheme.accent)
                .frame(width: 34, height: 34)
                .background(VLMSnapperTheme.subtleSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(VLMSnapperStrings.providerName(provider)).fontWeight(.semibold)
                Text(providerStatusDetail(provider))
                    .font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(providerStatusTitle(provider))
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    providerIsReady(provider)
                        ? VLMSnapperTheme.success
                        : VLMSnapperTheme.warning
                )
            Button(
                providerIsReady(provider)
                    ? VLMSnapperStrings.modify
                    : VLMSnapperStrings.configure
            ) {
                providerSettings?.onSelectProvider(provider)
                showingProviderSetup = true
            }
            .disabled(providerSettings == nil)
        }
        .padding(.vertical, 8)
    }

    private func providerIsReady(_ provider: ProviderID) -> Bool {
        guard let providerSettings else { return false }
        return ProviderSidebarPresentation(
            provider: provider,
            snapshot: providerSettings.snapshot,
            configurations: providerSettings.configurations
        ).isConfigured
    }

    private func providerStatusTitle(_ provider: ProviderID) -> String {
        providerIsReady(provider) ? VLMSnapperStrings.configured : VLMSnapperStrings.notConfigured
    }

    private func providerStatusDetail(_ provider: ProviderID) -> String {
        guard let providerSettings else {
            return VLMSnapperStrings.officialEndpoint
        }
        return ProviderSidebarPresentation(
            provider: provider,
            snapshot: providerSettings.snapshot,
            configurations: providerSettings.configurations
        ).detail
    }

    private var languageBinding: Binding<ApplicationLanguagePreference> {
        Binding(
            get: { settings.language },
            set: { value in callbacks.onLanguageChange(value) }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { settings.loginItemEnabled },
            set: { value in callbacks.onLoginItemChange(value) }
        )
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { settings.automaticallyChecksForUpdates },
            set: { value in callbacks.onAutomaticUpdateChecksChange(value) }
        )
    }

    private func shortcutFailureMessage(
        _ failure: ShortcutSettingsFailure
    ) -> String {
        switch failure {
        case .conflict:
            return VLMSnapperStrings.shortcutConflict
        case .invalid, .registrationFailed:
            return VLMSnapperStrings.shortcutInvalid
        }
    }

    private func settingsRow<Accessory: View>(
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 4)
    }

    private var updateStatus: some View {
        HStack(spacing: 12) {
            updateStatusIcon.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(updateStatusTitle).fontWeight(.semibold)
                Text(updateStatusDetail)
                    .font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            Spacer()
            updateStatusAction
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var updateStatusIcon: some View {
        switch settings.updateState {
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        case .readyToInstall:
            VLMSnapperIcon.downloaded.image.foregroundStyle(VLMSnapperTheme.accent)
        case .failed:
            VLMSnapperIcon.warningBadge.image.foregroundStyle(VLMSnapperTheme.destructive)
        default:
            VLMSnapperIcon.update.image.foregroundStyle(VLMSnapperTheme.accent)
        }
    }

    @ViewBuilder
    private var updateStatusAction: some View {
        switch settings.updateState {
        case .available:
            Button(VLMSnapperStrings.updateDownload, action: callbacks.onDownloadUpdate)
                .buttonStyle(.borderedProminent)
        case .readyToInstall:
            Button(VLMSnapperStrings.updateInstallNow, action: callbacks.onInstallUpdate)
                .buttonStyle(.borderedProminent)
        case .checking, .downloading:
            EmptyView()
        case .failed:
            Button(VLMSnapperStrings.updateRetry, action: callbacks.onCheckUpdates)
        default:
            Button(VLMSnapperStrings.updateCheck, action: callbacks.onCheckUpdates)
        }
    }

    private var updateStatusTitle: String {
        switch settings.updateState {
        case .idle, .current: VLMSnapperStrings.updateCurrent
        case .checking: VLMSnapperStrings.updateChecking
        case let .available(version):
            String(format: VLMSnapperStrings.updateAvailableTitleFormat, version.displayVersion)
        case let .downloading(version, _, _):
            String(format: VLMSnapperStrings.updateDownloadingTitleFormat, version.displayVersion)
        case let .readyToInstall(version):
            String(format: VLMSnapperStrings.updateReadyTitleFormat, version.displayVersion)
        case .failed: VLMSnapperStrings.updateFailedTitle
        }
    }

    private var updateStatusDetail: String {
        switch settings.updateState {
        case .idle, .current: VLMSnapperStrings.updateAutomaticChecksHint
        case .checking: VLMSnapperStrings.updateAutomaticChecksHint
        case .available: VLMSnapperStrings.updateAvailableDetail
        case .downloading: VLMSnapperStrings.updateDownloadingDetail
        case .readyToInstall: VLMSnapperStrings.updateReadyDetail
        case .failed: VLMSnapperStrings.updateFailedDetail
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(spacing: 0) {
                    historyDetailHeader(record)
                    Divider()
                    VStack(alignment: .leading, spacing: 18) {
                        screenshot(record)
                        resultSection(VLMSnapperStrings.historyOriginal, text: record.operation.sourceMarkdown)
                        if record.operation.kind == .translate {
                            resultSection(VLMSnapperStrings.historyTranslation, text: record.operation.translationMarkdown)
                        }
                        metrics(record)
                    }
                    .padding(15)
                }
                .background(VLMSnapperTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(VLMSnapperTheme.border, lineWidth: 1)
                }
                .padding(16)
            }
            .background(VLMSnapperTheme.subtleSurface)
        } else {
            ContentUnavailableView(VLMSnapperStrings.historyEmptyTitle, systemImage: VLMSnapperIcon.history.rawValue)
        }
    }

    private func historyDetailHeader(_ record: HistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.operation.sourceMarkdown ?? VLMSnapperStrings.failed)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text("\(record.operation.selection.providerID) · \(record.operation.selection.modelID)")
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            Spacer()
            Button {
                callbacks.onSetPinned(record.id, !record.isPinned)
            } label: {
                (record.isPinned ? VLMSnapperIcon.pinned : VLMSnapperIcon.pin).image
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) { pendingDeletion = record } label: {
                VLMSnapperIcon.delete.image
            }
            .buttonStyle(.borderless)
            .disabled(record.operation.status.isActive)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
    }

    private var filteredRecords: [HistoryRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            let kindMatches = kind == .all
                || (kind == .extract && record.operation.kind == .extract)
                || (kind == .translate && record.operation.kind == .translate)
            let searchable = [record.operation.sourceMarkdown, record.operation.translationMarkdown]
                .compactMap { $0 }.joined(separator: "\n").lowercased()
            return kindMatches && (!pinnedOnly || record.isPinned)
                && (query.isEmpty || searchable.contains(query))
        }
    }

    private var selectedRecord: HistoryRecord? {
        filteredRecords.first { $0.id == selectedRecordID } ?? filteredRecords.first
    }

    private func navButton(_ title: String, icon: VLMSnapperIcon, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon.rawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(selected ? VLMSnapperTheme.accent.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: VLMSnapperUIConstants.compactCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func historyRow(_ record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(record.operation.sourceMarkdown ?? VLMSnapperStrings.failed).fontWeight(.semibold).lineLimit(1)
                Spacer()
                if record.isPinned { VLMSnapperIcon.pinned.image.foregroundStyle(VLMSnapperTheme.accent) }
            }
            Text(record.operation.translationMarkdown ?? record.operation.normalizedErrorCode ?? record.operation.selection.modelID)
                .font(.caption).foregroundStyle(VLMSnapperTheme.secondaryText).lineLimit(2)
            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2).foregroundStyle(VLMSnapperTheme.secondaryText)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func screenshot(_ record: HistoryRecord) -> some View {
        if let selectedImage {
            Image(nsImage: selectedImage).resizable().scaledToFit()
                .frame(maxHeight: 210)
                .frame(maxWidth: .infinity)
                .background(VLMSnapperTheme.subtleSurface)
                .clipShape(RoundedRectangle(cornerRadius: VLMSnapperUIConstants.cardCornerRadius))
        } else {
            Label(VLMSnapperStrings.historyScreenshotUnavailable, systemImage: VLMSnapperIcon.warning.rawValue)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(VLMSnapperTheme.subtleSurface)
                .clipShape(RoundedRectangle(cornerRadius: VLMSnapperUIConstants.cardCornerRadius))
        }
    }

    private func resultSection(_ title: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(text ?? VLMSnapperStrings.historyUnavailable).textSelection(.enabled)
        }
    }

    private func metrics(_ record: HistoryRecord) -> some View {
        HStack(spacing: 24) {
            metric(VLMSnapperStrings.historyFirstTextLatency, value: latency(record.metrics.firstTextLatencyMilliseconds))
            metric(VLMSnapperStrings.historyTotalLatency, value: latency(record.metrics.totalLatencyMilliseconds))
            metric(
                VLMSnapperStrings.historyTokenUsage,
                value: record.metrics.usage.map {
                    String(
                        format: VLMSnapperStrings.historyTokenUsageFormat,
                        $0.inputTokens,
                        $0.outputTokens,
                        $0.totalTokens
                    )
                } ?? VLMSnapperStrings.historyUnavailable
            )
        }
        .padding(12)
        .background(VLMSnapperTheme.subtleSurface)
        .clipShape(RoundedRectangle(cornerRadius: VLMSnapperUIConstants.compactCornerRadius))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(VLMSnapperTheme.secondaryText)
            Text(value).fontWeight(.medium)
        }
    }

    private func latency(_ milliseconds: Int?) -> String {
        milliseconds.map {
            Measurement(value: Double($0) / 1_000, unit: UnitDuration.seconds)
                .formatted(
                    .measurement(
                        width: .abbreviated,
                        usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(2))
                    )
                )
        }
            ?? VLMSnapperStrings.historyUnavailable
    }

    private func selectFirstVisibleRecord() {
        selectedRecordID = filteredRecords.first?.id
    }

    private var retentionShorteningTitle: String {
        String(
            format: VLMSnapperStrings.historyRetentionShorteningConfirm,
            settings.retentionShorteningRecordCount ?? 0
        )
    }
}
