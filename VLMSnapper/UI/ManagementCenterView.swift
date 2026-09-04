import AppKit
import SwiftUI
import VLMSnapperCore

public struct ProviderSettingsConfiguration {
    public let snapshot: ProviderSetupSnapshot
    public let configurations: [ProviderID: ProviderConfiguration]
    public let currentProvider: ProviderID?
    public let apiKey: Binding<String>
    public let pendingModelID: Binding<String?>
    public let onSelectProvider: (ProviderID) -> Void
    public let onValidate: () -> Void
    public let onRefresh: () -> Void
    public let onSelectModel: (String) -> Void
    public let onSetCurrentProvider: (ProviderID) -> Void
    public let onRemoveProvider: (ProviderID) -> Void

    public init(
        snapshot: ProviderSetupSnapshot,
        configurations: [ProviderID: ProviderConfiguration] = [:],
        currentProvider: ProviderID? = nil,
        apiKey: Binding<String>,
        pendingModelID: Binding<String?>,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidate: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onSetCurrentProvider: @escaping (ProviderID) -> Void = { _ in },
        onRemoveProvider: @escaping (ProviderID) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.configurations = configurations
        self.currentProvider = currentProvider
        self.apiKey = apiKey
        self.pendingModelID = pendingModelID
        self.onSelectProvider = onSelectProvider
        self.onValidate = onValidate
        self.onRefresh = onRefresh
        self.onSelectModel = onSelectModel
        self.onSetCurrentProvider = onSetCurrentProvider
        self.onRemoveProvider = onRemoveProvider
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
    public let onOpenRecord: (UUID) -> Void
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
        onOpenRecord: @escaping (UUID) -> Void = { _ in },
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
        self.onOpenRecord = onOpenRecord
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
    @State private var expandedProvider: ProviderID?
    @State private var showsAPIKey = false
    @State private var apiKeyIsDirty = false
    @State private var providerPendingRemoval: ProviderID?

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
        _expandedProvider = State(
            initialValue: providerSettings.map {
                ProviderSettingsInitialSelection.resolve(
                    explicitTarget: destination == .providerSettings
                        ? $0.snapshot.selectedProvider
                        : nil,
                    currentProvider: $0.currentProvider
                )
            }
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
        .confirmationDialog(
            VLMSnapperStrings.providerRemoveConfirmation,
            isPresented: Binding(
                get: { providerPendingRemoval != nil },
                set: { if !$0 { providerPendingRemoval = nil } }
            ),
            presenting: providerPendingRemoval
        ) { provider in
            Button(VLMSnapperStrings.providerRemove, role: .destructive) {
                providerSettings?.onRemoveProvider(provider)
                apiKeyIsDirty = false
                showsAPIKey = false
                providerPendingRemoval = nil
            }
        }
        .onChange(of: providerSettings?.snapshot.selectedProvider) { _, _ in
            apiKeyIsDirty = false
            showsAPIKey = false
        }
        .onChange(of: providerSettings?.snapshot.phase) { _, phase in
            if phase == .selectingModel || phase == .ready {
                apiKeyIsDirty = false
            }
        }
        .onAppear {
            guard destination != .history,
                  !showGeneralSettings,
                  let expandedProvider,
                  providerSettings?.snapshot.selectedProvider != expandedProvider else {
                return
            }
            providerSettings?.onSelectProvider(expandedProvider)
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
            navButton(VLMSnapperStrings.historyProviderSettings, icon: .providerList, selected: destination == .providerSettings) {
                destination = .providerSettings
                showGeneralSettings = false
                openInitialProviderIfNeeded()
            }
            navButton(VLMSnapperStrings.historyGeneralSettings, icon: .general, selected: destination == .settings) {
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
                        historyRow(record)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                callbacks.onOpenRecord(record.id)
                            }
                            .tag(record.id)
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
                    VStack(spacing: 12) {
                        ForEach([ProviderID.deepSeek, .openAI, .gemini], id: \.self) { provider in
                            providerSettingsCard(provider)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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

    private func providerSettingsCard(_ provider: ProviderID) -> some View {
        let isExpanded = expandedProvider == provider
        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedProvider = nil
                } else {
                    expandedProvider = provider
                    apiKeyIsDirty = false
                    showsAPIKey = false
                    providerSettings?.onSelectProvider(provider)
                }
            } label: {
                HStack(spacing: 14) {
                    VLMSnapperIcon.provider.image
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VLMSnapperTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(VLMSnapperTheme.accent.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(VLMSnapperStrings.providerName(provider))
                            .font(.headline)
                        Text(providerCardSubtitle(provider))
                            .font(.caption)
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                    }
                    Spacer()
                    providerStatusBadge(provider)
                    VLMSnapperIcon.chevronDown.image
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 68)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(providerSettings == nil)

            if isExpanded {
                Divider()
                providerEditor(provider)
            }
        }
        .background(VLMSnapperTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VLMSnapperTheme.border.opacity(0.8))
        }
    }

    @ViewBuilder
    private func providerEditor(_ provider: ProviderID) -> some View {
        if let providerSettings,
           providerSettings.snapshot.selectedProvider == provider {
            let presentation = providerCredentialPresentation(provider)
            VStack(alignment: .leading, spacing: 18) {
                if providerSettings.snapshot.isReadOnly {
                    Label(
                        VLMSnapperStrings.providerReadOnly,
                        systemImage: VLMSnapperIcon.lock.rawValue
                    )
                    .font(.callout)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VLMSnapperTheme.subtleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(VLMSnapperStrings.apiKey).font(.headline)
                        Spacer()
                        Label(
                            providerCredentialStatusText(presentation.status),
                            systemImage: providerCredentialStatusIcon(presentation.status)
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(providerCredentialStatusColor(presentation.status))
                    }
                    HStack(spacing: 0) {
                        Group {
                            if showsAPIKey {
                                TextField(
                                    providerSettings.apiKey.wrappedValue.isEmpty
                                        ? VLMSnapperStrings.apiKeyPlaceholder
                                        : "",
                                    text: providerAPIKeyBinding
                                )
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                SecureField(
                                    providerSettings.apiKey.wrappedValue.isEmpty
                                        ? VLMSnapperStrings.apiKeyPlaceholder
                                        : "",
                                    text: providerAPIKeyBinding
                                )
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .disabled(providerSettings.snapshot.isReadOnly)
                        .onSubmit {
                            if presentation.canValidate {
                                providerSettings.onValidate()
                            }
                        }
                        .padding(.trailing, 8)
                        Button {
                            providerSettings.apiKey.wrappedValue = ""
                            apiKeyIsDirty = true
                        } label: {
                            VLMSnapperIcon.close.image.frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(providerSettings.apiKey.wrappedValue.isEmpty || providerSettings.snapshot.isReadOnly)
                        .accessibilityLabel(VLMSnapperStrings.clearAPIKey)
                        Button {
                            showsAPIKey.toggle()
                        } label: {
                            (showsAPIKey ? VLMSnapperIcon.eyeSlash : VLMSnapperIcon.eye)
                                .image.frame(width: 28, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(providerSettings.snapshot.isReadOnly)
                        .accessibilityLabel(
                            showsAPIKey
                                ? VLMSnapperStrings.hideAPIKey
                                : VLMSnapperStrings.showAPIKey
                        )
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(VLMSnapperTheme.window)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(VLMSnapperTheme.border)
                    }

                    if presentation.showsValidation {
                        HStack {
                            Text(providerValidationHint(presentation.status))
                                .font(.caption)
                                .foregroundStyle(VLMSnapperTheme.secondaryText)
                            Spacer()
                            Button(VLMSnapperStrings.validate, action: providerSettings.onValidate)
                                .buttonStyle(.borderedProminent)
                                .disabled(!presentation.canValidate)
                        }
                    }
                    if let failure = providerSettings.snapshot.failure {
                        Label(
                            providerFailureText(failure),
                            systemImage: VLMSnapperIcon.warning.rawValue
                        )
                        .font(.callout)
                        .foregroundStyle(VLMSnapperTheme.destructive)
                    }
                    Text(VLMSnapperStrings.providerReplacementHint)
                        .font(.caption)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }

                if !providerSettings.snapshot.availableModelIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VLMSnapperStrings.currentModel).font(.headline)
                        HStack(spacing: 10) {
                            Picker(
                                VLMSnapperStrings.currentModel,
                                selection: providerModelBinding
                            ) {
                                Text(VLMSnapperStrings.chooseModel).tag(String?.none)
                                ForEach(providerSettings.snapshot.availableModelIDs, id: \.self) {
                                    Text($0).tag(Optional($0))
                                }
                            }
                            .labelsHidden()
                            .disabled(providerSettings.snapshot.isReadOnly)
                            Button(VLMSnapperStrings.refresh, action: providerSettings.onRefresh)
                                .disabled(providerSettings.snapshot.isReadOnly)
                        }
                        Text(VLMSnapperStrings.visionValidationHint)
                            .font(.caption)
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                    }
                }

                HStack {
                    if providerSettings.configurations[provider] != nil {
                        Button(VLMSnapperStrings.providerRemove, role: .destructive) {
                            providerPendingRemoval = provider
                        }
                        .disabled(providerSettings.snapshot.isReadOnly)
                    }
                    Spacer()
                    if providerSettings.currentProvider == provider {
                        Text(VLMSnapperStrings.providerCurrent)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                    } else if providerIsReady(provider) {
                        Button(VLMSnapperStrings.providerSetCurrent) {
                            providerSettings.onSetCurrentProvider(provider)
                        }
                        .disabled(providerSettings.snapshot.isReadOnly)
                    }
                }
            }
            .padding(16)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    private var providerAPIKeyBinding: Binding<String> {
        Binding(
            get: { providerSettings?.apiKey.wrappedValue ?? "" },
            set: { value in
                providerSettings?.apiKey.wrappedValue = value
                apiKeyIsDirty = true
            }
        )
    }

    private var providerModelBinding: Binding<String?> {
        Binding(
            get: { providerSettings?.pendingModelID.wrappedValue },
            set: { value in
                providerSettings?.pendingModelID.wrappedValue = value
                if let value { providerSettings?.onSelectModel(value) }
            }
        )
    }

    private func providerIsReady(_ provider: ProviderID) -> Bool {
        guard let providerSettings else { return false }
        return ProviderSettingsDetailPresentation(
            provider: provider,
            snapshot: providerSettings.snapshot,
            configurations: providerSettings.configurations
        ).isConfigured
    }

    private func providerCredentialPresentation(
        _ provider: ProviderID
    ) -> ProviderInlineCredentialPresentation {
        guard let providerSettings else {
            return ProviderInlineCredentialPresentation(
                isConfigured: false,
                isSelected: false,
                isDirty: false,
                phase: .awaitingValidation,
                hasAPIKey: false,
                isReadOnly: false
            )
        }
        return ProviderInlineCredentialPresentation(
            isConfigured: providerSettings.configurations[provider] != nil,
            isSelected: providerSettings.snapshot.selectedProvider == provider,
            isDirty: providerSettings.snapshot.selectedProvider == provider
                && apiKeyIsDirty,
            phase: providerSettings.snapshot.phase,
            hasAPIKey: !providerSettings.apiKey.wrappedValue
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isReadOnly: providerSettings.snapshot.isReadOnly
        )
    }

    private func providerStatusBadge(_ provider: ProviderID) -> some View {
        let status = providerCardPresentation(provider).status
        return Text(providerCardStatusText(status))
            .font(.caption.weight(.semibold))
            .foregroundStyle(providerCardStatusColor(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(providerCardStatusColor(status).opacity(0.1))
            .clipShape(Capsule())
    }

    private func providerCardPresentation(
        _ provider: ProviderID
    ) -> ProviderInlineCardPresentation {
        guard let providerSettings else {
            return ProviderInlineCardPresentation(
                provider: provider,
                snapshot: ProviderSetupSnapshot(
                    selectedProvider: .deepSeek,
                    availableModelIDs: [],
                    selectedModelID: nil,
                    phase: .awaitingValidation,
                    failure: nil
                ),
                configuration: nil,
                isDirty: false
            )
        }
        return ProviderInlineCardPresentation(
            provider: provider,
            snapshot: providerSettings.snapshot,
            configuration: providerSettings.configurations[provider],
            isDirty: providerSettings.snapshot.selectedProvider == provider
                && apiKeyIsDirty
        )
    }

    private func providerCardSubtitle(_ provider: ProviderID) -> String {
        let state = providerStatusDetail(provider)
        if providerSettings?.currentProvider == provider {
            return String(format: VLMSnapperStrings.providerCurrentDetailFormat, state)
        }
        return state
    }

    private func providerStatusDetail(_ provider: ProviderID) -> String {
        guard let providerSettings else { return VLMSnapperStrings.notConfigured }
        return ProviderSettingsDetailPresentation(
            provider: provider,
            snapshot: providerSettings.snapshot,
            configurations: providerSettings.configurations
        ).detail
    }

    private func providerCredentialStatusText(
        _ status: ProviderInlineCredentialStatus
    ) -> String {
        switch status {
        case .notConfigured: VLMSnapperStrings.notConfigured
        case .pending: VLMSnapperStrings.providerPendingValidation
        case .validating: VLMSnapperStrings.validating
        case .configured: VLMSnapperStrings.configured
        case .failed: VLMSnapperStrings.failed
        }
    }

    private func providerCardStatusText(_ status: ProviderInlineCardStatus) -> String {
        switch status {
        case .notConfigured: VLMSnapperStrings.providerSetupRequired
        case .pendingValidation: VLMSnapperStrings.providerPendingValidation
        case .validating: VLMSnapperStrings.validating
        case .pendingModel: VLMSnapperStrings.modelPending
        case .ready: VLMSnapperStrings.providerAvailable
        case .failed: VLMSnapperStrings.failed
        }
    }

    private func providerCredentialStatusIcon(
        _ status: ProviderInlineCredentialStatus
    ) -> String {
        switch status {
        case .configured: VLMSnapperIcon.complete.rawValue
        case .validating: VLMSnapperIcon.retry.rawValue
        case .notConfigured, .pending, .failed: VLMSnapperIcon.warningBadge.rawValue
        }
    }

    private func providerCredentialStatusColor(
        _ status: ProviderInlineCredentialStatus
    ) -> Color {
        switch status {
        case .configured: VLMSnapperTheme.success
        case .failed: VLMSnapperTheme.destructive
        case .notConfigured, .pending, .validating: VLMSnapperTheme.warning
        }
    }

    private func providerCardStatusColor(_ status: ProviderInlineCardStatus) -> Color {
        switch status {
        case .ready: VLMSnapperTheme.success
        case .failed: VLMSnapperTheme.destructive
        case .notConfigured, .pendingValidation, .validating, .pendingModel:
            VLMSnapperTheme.warning
        }
    }

    private func providerValidationHint(
        _ status: ProviderInlineCredentialStatus
    ) -> String {
        switch status {
        case .pending: VLMSnapperStrings.providerNewKeyPending
        case .validating: VLMSnapperStrings.validating
        case .failed: VLMSnapperStrings.providerRetryValidation
        case .notConfigured: VLMSnapperStrings.providerEnterKey
        case .configured: ""
        }
    }

    private func providerFailureText(_ failure: ProviderSetupFailure) -> String {
        switch failure {
        case .configurationLocked: VLMSnapperStrings.providerReadOnly
        case .invalidConfiguration:
            VLMSnapperStrings.failureMessage(code: "invalid_credential")
        case .secureStorage:
            VLMSnapperStrings.failureMessage(code: "local_storage")
        case .unavailable:
            VLMSnapperStrings.failureMessage(code: "provider_unavailable")
        }
    }

    private func openInitialProviderIfNeeded() {
        guard expandedProvider == nil, let providerSettings else { return }
        let provider = ProviderSettingsInitialSelection.resolve(
            explicitTarget: nil,
            currentProvider: providerSettings.currentProvider
        )
        expandedProvider = provider
        providerSettings.onSelectProvider(provider)
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
