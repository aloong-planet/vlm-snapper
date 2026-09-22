import AppKit
import SwiftUI
import VLMSnapperCore

public struct ProviderSettingsFocusRequest: Equatable {
    public let id = UUID()
    public let provider: ProviderID

    public init(provider: ProviderID) { self.provider = provider }
}

public struct ProviderSettingsConfiguration {
    public let snapshot: ProviderSetupSnapshot
    public let focusRequest: ProviderSettingsFocusRequest?
    public let configurations: [ProviderID: ProviderConfiguration]
    public let currentProvider: ProviderID?
    public let credentialEditor: ProviderCredentialEditor
    public let pendingModelID: Binding<String?>
    public let onSelectProvider: (ProviderID) -> Void
    public let onValidate: (ProviderCredentialSubmission) -> Void
    public let onRefresh: () -> Void
    public let onSelectModel: (String) -> Void
    public let onSetCurrentProvider: (ProviderID) -> Void
    public let onRemoveProvider: (ProviderID) -> Void

    public init(
        snapshot: ProviderSetupSnapshot,
        focusRequest: ProviderSettingsFocusRequest? = nil,
        configurations: [ProviderID: ProviderConfiguration] = [:],
        currentProvider: ProviderID? = nil,
        credentialEditor: ProviderCredentialEditor,
        pendingModelID: Binding<String?>,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidate: @escaping (ProviderCredentialSubmission) -> Void,
        onRefresh: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onSetCurrentProvider: @escaping (ProviderID) -> Void = { _ in },
        onRemoveProvider: @escaping (ProviderID) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.focusRequest = focusRequest
        self.configurations = configurations
        self.currentProvider = currentProvider
        self.credentialEditor = credentialEditor
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

@MainActor
public struct ManagementCenterCallbacks {
    public let historyRetry: HistoryRetryPresentation
    public let onRetryHistorySave: () -> Void
    public let onSelectRecord: (UUID) -> Void
    public let onOpenRecord: (UUID) -> Void
    public let onRetryRecord: (UUID) -> Void
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
        historyRetry: HistoryRetryPresentation = HistoryRetryPresentation(),
        onRetryHistorySave: @escaping () -> Void = {},
        onSelectRecord: @escaping (UUID) -> Void = { _ in },
        onOpenRecord: @escaping (UUID) -> Void = { _ in },
        onRetryRecord: @escaping (UUID) -> Void = { _ in },
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
        self.historyRetry = historyRetry
        self.onRetryHistorySave = onRetryHistorySave
        self.onSelectRecord = onSelectRecord
        self.onOpenRecord = onOpenRecord
        self.onRetryRecord = onRetryRecord
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
    @ObservedObject private var historyRetry: HistoryRetryPresentation
    private let requestedDestination: ManagementCenterDestination
    private let navigationRequestID: UUID?
    private let records: [HistoryRecord]
    private let selectedImage: NSImage?
    private let imageRecordID: UUID?
    private let cleanupFailureCount: Int
    private let callbacks: ManagementCenterCallbacks
    private let settings: GeneralSettingsSnapshot
    private let providerSettings: ProviderSettingsConfiguration?
    @ObservedObject private var credentialEditor: ProviderCredentialEditor
    @State private var destination: ManagementCenterDestination
    @State private var kind: HistoryOperationKindFilter = .all
    @State private var historyProviderID: String?
    @State private var searchText: String
    @State private var selectedRecordID: UUID?
    @State private var retention: HistoryRetentionPeriod
    @State private var pinnedOnly = false
    @State private var showGeneralSettings = false
    @State private var pendingDeletion: HistoryRecord?
    @State private var showingClearConfirmation = false
    @State private var expandedProvider: ProviderID?
    @State private var showsAPIKey = false
    @State private var providerPendingRemoval: ProviderID?

    public init(
        destination: ManagementCenterDestination,
        navigationRequestID: UUID? = nil,
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
        self.requestedDestination = destination
        self.navigationRequestID = navigationRequestID
        self.records = records
        self.selectedImage = selectedImage
        self.imageRecordID = selectedRecordID ?? records.first?.id
        self.cleanupFailureCount = cleanupFailureCount
        self.callbacks = callbacks
        _historyRetry = ObservedObject(wrappedValue: callbacks.historyRetry)
        self.settings = settings
        self.providerSettings = providerSettings
        _credentialEditor = ObservedObject(wrappedValue: providerSettings?.credentialEditor ?? ProviderCredentialEditor())
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
                    explicitTarget: $0.focusRequest?.provider ?? (destination == .providerSettings
                        ? $0.snapshot.selectedProvider
                        : nil),
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
        .onChange(of: filteredRecords.map(\.id), initial: true) { _, _ in reconcileHistorySelection() }
        .onChange(of: selectedRecordID, initial: true) { _, value in
            if let value { callbacks.onSelectRecord(value) }
        }
        .onChange(of: navigationRequestID) { _, _ in
            destination = requestedDestination
            showGeneralSettings = requestedDestination == .settings
            if requestedDestination == .providerSettings { openInitialProviderIfNeeded() }
        }
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
                showsAPIKey = false
                providerPendingRemoval = nil
            }
        }
        .onChange(of: credentialEditor.provider) { _, _ in
            showsAPIKey = false
        }
        .onChange(of: providerSettings?.focusRequest) { _, request in
            guard let request else { return }
            destination = .providerSettings
            showGeneralSettings = false
            expandedProvider = request.provider
            showsAPIKey = false
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
            sidebarHeading(VLMSnapperStrings.historyLibrary)
            navButton(VLMSnapperStrings.menuHistory, icon: .history, count: records.count, selected: destination == .history && !pinnedOnly) {
                destination = .history
                pinnedOnly = false
            }
            navButton(VLMSnapperStrings.historyPinned, icon: .pinned, count: records.filter(\.isPinned).count, selected: destination == .history && pinnedOnly) {
                destination = .history
                pinnedOnly = true
            }
            sidebarHeading(VLMSnapperStrings.menuSettings)
            navButton(VLMSnapperStrings.historyProviderSettings, icon: .providerList, count: ProviderID.allCases.count, selected: destination == .providerSettings) {
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
        .padding(.horizontal, 9)
        .padding(.vertical, 12)
        .frame(width: ManagementCenterMetrics.sidebarWidth)
        .background(VLMSnapperTheme.subtleSurface)
    }

    private var contentToolbar: some View {
        HStack(spacing: 12) {
            if destination == .history {
                HStack(spacing: 2) {
                    historyTypeButton(VLMSnapperStrings.historyAll, kind: .all)
                    historyTypeButton(VLMSnapperStrings.historyExtract, kind: .extract)
                    historyTypeButton(VLMSnapperStrings.translate, kind: .translate)
                }
                .padding(3)
                .background(VLMSnapperTheme.subtleSurface, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(VLMSnapperStrings.operationSelector)
                Picker(VLMSnapperStrings.historyProviderSettings, selection: $historyProviderID) {
                    Text(VLMSnapperStrings.historyAllProviders).tag(String?.none)
                    ForEach(historyProviderOptions, id: \.self) { providerID in
                        Text(historyProviderName(providerID)).tag(Optional(providerID))
                    }
                }
                .labelsHidden()
                .frame(width: 145)
                HStack(spacing: 7) {
                    VLMSnapperIcon.search.image.foregroundStyle(VLMSnapperTheme.secondaryText)
                    TextField(VLMSnapperStrings.historySearch, text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 9)
                .frame(minWidth: 110, maxWidth: .infinity)
                .frame(height: 31)
                .background(VLMSnapperTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(VLMSnapperTheme.border))
            } else {
                Text(VLMSnapperStrings.menuSettings).font(.headline)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: destination == .history ? 58 : ManagementCenterMetrics.titlebarHeight)
    }

    private func historyTypeButton(_ title: String, kind value: HistoryOperationKindFilter) -> some View {
        Button(title) { kind = value }
            .buttonStyle(HistoryTypeButtonStyle(isSelected: kind == value))
            .accessibilityAddTraits(kind == value ? .isSelected : [])
    }

    private var historyProviderOptions: [String] {
        var values = Set(records.map { $0.operation.selection.providerID })
        // Keep an active filter visible if its last record is removed.
        if let historyProviderID { values.insert(historyProviderID) }
        return values.sorted()
    }

    private func historyProviderName(_ id: String) -> String {
        ProviderID(rawValue: id).map(VLMSnapperStrings.providerName) ?? id
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 5) {
                                ForEach(filteredRecords) { record in
                                    Button { selectedRecordID = record.id } label: {
                                        historyRow(record)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .modifier(HistoryRecordSurface(isSelected: selectedRecordID == record.id))
                                    }
                                    .buttonStyle(.plain)
                                    .id(record.id)
                                    .accessibilityElement(children: .combine)
                                    .accessibilityIdentifier("history-record-\(record.id)")
                                    .accessibilityAddTraits(selectedRecordID == record.id ? .isSelected : [])
                                    .accessibilityAction { selectedRecordID = record.id }
                                }
                            }
                            .padding(5)
                        }
                        .background(VLMSnapperTheme.historySurface)
                        .onMoveCommand { direction in
                            guard direction == .up || direction == .down,
                                  let index = filteredRecords.firstIndex(where: { $0.id == selectedRecordID }) else { return }
                            let next = max(0, min(filteredRecords.count - 1, index + (direction == .down ? 1 : -1)))
                            selectedRecordID = filteredRecords[next].id
                            proxy.scrollTo(filteredRecords[next].id)
                        }
                    }
                }
                Divider()
                Button(VLMSnapperStrings.historyClear) { showingClearConfirmation = true }
                    .buttonStyle(.plain)
                    .disabled(historyRetry.preventsDiscard)
                    .foregroundStyle(VLMSnapperTheme.destructive)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 259)
            Rectangle().fill(VLMSnapperTheme.historyDivider).frame(width: 1)
            detail
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if showGeneralSettings {
            Form {
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
            }
            .formStyle(.grouped)
            .padding(18)
        } else {
            providerSettingsContent
        }
    }

    private var providerSettingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(VLMSnapperStrings.historyProviderSettings)
                        .font(.title3.weight(.semibold))
                    Text(VLMSnapperStrings.providerSetupSubtitle)
                        .font(.callout)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
                VStack(spacing: 12) {
                    ForEach([ProviderID.deepSeek, .openAI, .gemini], id: \.self) { provider in
                        providerSettingsCard(provider)
                    }
                }
            }
            .frame(maxWidth: ManagementCenterMetrics.providerContentWidth)
            .frame(maxWidth: .infinity)
            .padding(22)
        }
        .background(VLMSnapperTheme.subtleSurface)
    }

    private func providerSettingsCard(_ provider: ProviderID) -> some View {
        let isExpanded = expandedProvider == provider
        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedProvider = nil
                    credentialEditor.close()
                } else {
                    expandedProvider = provider
                    showsAPIKey = false
                    providerSettings?.onSelectProvider(provider)
                }
            } label: {
                HStack(spacing: 14) {
                    ProviderIdentityMark(provider: provider)
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
                .frame(minHeight: ManagementCenterMetrics.providerHeaderHeight)
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
            VStack(alignment: .leading, spacing: 12) {
                if providerSettings.snapshot.blocksConfigurationChanges,
                   providerSettings.snapshot.refreshingProvider == nil,
                   providerSettings.snapshot.phase != .recovering,
                   providerSettings.snapshot.failure != .secureStorage {
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

                providerConfigurationFields(
                    providerSettings,
                    presentation: presentation
                )

                HStack {
                    if providerSettings.configurations[provider] != nil {
                        Button(VLMSnapperStrings.providerRemove, role: .destructive) {
                            providerPendingRemoval = provider
                        }
                        .buttonStyle(SetupActionButtonStyle(isDestructive: true))
                        .disabled(providerSettings.snapshot.blocksConfigurationChanges
                                  || credentialEditor.isSubmitting || credentialEditor.isLoading)
                    }
                    Spacer()
                    if providerSettings.currentProvider == provider {
                        Text(VLMSnapperStrings.providerCurrent)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VLMSnapperTheme.success)
                    } else if providerIsReady(provider) {
                        Button(VLMSnapperStrings.providerSetCurrent) {
                            providerSettings.onSetCurrentProvider(provider)
                        }
                        .buttonStyle(SetupActionButtonStyle(horizontalPadding: 12))
                        .disabled(providerSettings.snapshot.blocksConfigurationChanges
                                  || credentialEditor.isSubmitting || credentialEditor.isLoading)
                    }
                }
                .frame(minHeight: 32)
            }
            .padding(16)
            .background(VLMSnapperTheme.subtleSurface)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(24)
        }
    }

    @ViewBuilder
    private func providerConfigurationFields(
        _ providerSettings: ProviderSettingsConfiguration,
        presentation: ProviderInlineCredentialPresentation
    ) -> some View {
        if providerSettings.snapshot.availableModelIDs.isEmpty {
            providerCredentialField(providerSettings, presentation: presentation)
        } else {
            ProviderFieldLayout {
                providerCredentialField(providerSettings, presentation: presentation)
                providerModelField(providerSettings)
            }
        }
    }

    private func providerCredentialField(
        _ providerSettings: ProviderSettingsConfiguration,
        presentation: ProviderInlineCredentialPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(VLMSnapperStrings.apiKey)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                Spacer()
                Label(
                    providerCredentialStatusText(presentation.status),
                    systemImage: providerCredentialStatusIcon(presentation.status)
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(providerCredentialStatusColor(presentation.status))
            }
            .frame(height: 18)
            HStack(spacing: 0) {
                ProviderAPIKeyField(
                    text: providerAPIKeyBinding,
                    placeholder: VLMSnapperStrings.apiKeyPlaceholder,
                    isRevealed: showsAPIKey,
                    isEnabled: !providerSettings.snapshot.isReadOnly
                        && !credentialEditor.isSubmitting && !credentialEditor.isLoading,
                    onSubmit: {
                        if presentation.canValidate {
                            credentialEditor.submit(for: providerSettings.snapshot.selectedProvider,
                                                    isReadOnly: providerSettings.snapshot.blocksConfigurationChanges,
                                                    operation: providerSettings.onValidate)
                        }
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                Button {
                    providerAPIKeyBinding.wrappedValue = ""
                } label: {
                    VLMSnapperIcon.close.image.frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(
                    credentialEditor.value.isEmpty
                        || providerSettings.snapshot.isReadOnly || credentialEditor.isSubmitting
                        || credentialEditor.isLoading
                )
                .accessibilityLabel(VLMSnapperStrings.clearAPIKey)
                Button {
                    showsAPIKey.toggle()
                } label: {
                    (showsAPIKey ? VLMSnapperIcon.eyeSlash : VLMSnapperIcon.eye)
                        .image.frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(providerSettings.snapshot.isReadOnly || credentialEditor.isSubmitting
                          || credentialEditor.isLoading)
                .accessibilityLabel(
                    showsAPIKey
                        ? VLMSnapperStrings.hideAPIKey
                        : VLMSnapperStrings.showAPIKey
                )
            }
            .padding(.horizontal, 11)
            .frame(height: ManagementCenterMetrics.providerCredentialFieldHeight)
            .background(VLMSnapperTheme.window)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(VLMSnapperTheme.border)
            }

            if presentation.showsValidation {
                HStack {
                    Text(presentation.localInputHint ?? providerValidationHint(presentation.status))
                        .font(.caption)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                    Spacer()
                    Button(VLMSnapperStrings.validate) {
                        credentialEditor.submit(for: providerSettings.snapshot.selectedProvider,
                                                    isReadOnly: providerSettings.snapshot.blocksConfigurationChanges,
                                                    operation: providerSettings.onValidate)
                    }
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
    }

    private func providerModelField(
        _ providerSettings: ProviderSettingsConfiguration
    ) -> some View {
        let isRefreshing = providerSettings.snapshot.refreshingProvider
            == providerSettings.snapshot.selectedProvider
        let refreshFailed = providerSettings.snapshot.modelRefreshFailure != nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(VLMSnapperStrings.currentModel).font(.system(size: 13))
                .frame(height: 18)
            HStack(spacing: 8) {
                ProviderModelPicker(
                    modelIDs: providerSettings.snapshot.availableModelIDs,
                    selection: providerModelBinding
                )
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(VLMSnapperTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(VLMSnapperTheme.border))
                .disabled(providerSettings.snapshot.blocksConfigurationChanges
                                  || credentialEditor.isSubmitting || credentialEditor.isLoading)
                Button(action: providerSettings.onRefresh) {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        }
                        Text(isRefreshing
                             ? VLMSnapperStrings.refreshingModels
                             : (refreshFailed ? VLMSnapperStrings.retryModelRefresh : VLMSnapperStrings.refresh))
                    }
                    .frame(width: 128)
                }
                    .buttonStyle(SetupActionButtonStyle())
                    .disabled(providerSettings.snapshot.blocksConfigurationChanges
                                  || credentialEditor.isSubmitting || credentialEditor.isLoading)
            }
            // Both messages share a content-sized row; no separate blank error slot.
            ZStack(alignment: .topLeading) {
                Text(VLMSnapperStrings.visionValidationHint)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .opacity(refreshFailed ? 0 : 1)
                    .accessibilityHidden(refreshFailed)
                Text(VLMSnapperStrings.modelRefreshFailureHint)
                    .foregroundStyle(VLMSnapperTheme.destructive)
                    .opacity(refreshFailed ? 1 : 0)
                    .accessibilityHidden(!refreshFailed)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var providerAPIKeyBinding: Binding<String> {
        Binding(
            get: { credentialEditor.value },
            set: { credentialEditor.edit($0) }
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
                && credentialEditor.isDirty,
            phase: credentialEditor.isSubmitting ? .validating : providerSettings.snapshot.phase,
            hasAPIKey: !credentialEditor.value.isEmpty,
            isReadOnly: providerSettings.snapshot.isReadOnly
                || credentialEditor.isLoading || credentialEditor.provider != provider,
            isValidationBlocked: providerSettings.snapshot.blocksConfigurationChanges,
            inputIssue: ProviderAPIKeyInput.issue(in: credentialEditor.value),
            failure: providerSettings.snapshot.failure
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
                && credentialEditor.isDirty
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
        case .recovering: VLMSnapperStrings.recovering
        case .storageFailure: VLMSnapperStrings.providerStorageFailure
        case .configured: VLMSnapperStrings.configured
        case .failed: VLMSnapperStrings.failed
        }
    }

    private func providerCardStatusText(_ status: ProviderInlineCardStatus) -> String {
        switch status {
        case .notConfigured: VLMSnapperStrings.providerSetupRequired
        case .pendingValidation: VLMSnapperStrings.providerPendingValidation
        case .validating: VLMSnapperStrings.validating
        case .recovering: VLMSnapperStrings.recovering
        case .storageFailure: VLMSnapperStrings.providerStorageFailure
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
        case .validating, .recovering: VLMSnapperIcon.retry.rawValue
        case .notConfigured, .pending, .failed, .storageFailure: VLMSnapperIcon.warningBadge.rawValue
        }
    }

    private func providerCredentialStatusColor(
        _ status: ProviderInlineCredentialStatus
    ) -> Color {
        switch status {
        case .configured: VLMSnapperTheme.success
        case .failed, .storageFailure: VLMSnapperTheme.destructive
        case .notConfigured, .pending, .validating, .recovering: VLMSnapperTheme.warning
        }
    }

    private func providerCardStatusColor(_ status: ProviderInlineCardStatus) -> Color {
        switch status {
        case .ready: VLMSnapperTheme.success
        case .failed, .storageFailure: VLMSnapperTheme.destructive
        case .notConfigured, .pendingValidation, .validating, .recovering, .pendingModel:
            VLMSnapperTheme.warning
        }
    }

    private func providerValidationHint(
        _ status: ProviderInlineCredentialStatus
    ) -> String {
        switch status {
        case .pending: VLMSnapperStrings.providerNewKeyPending
        case .validating: VLMSnapperStrings.validating
        case .recovering: VLMSnapperStrings.recovering
        case .storageFailure: VLMSnapperStrings.providerStorageFailure
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
            providerSettings?.snapshot.isReadOnly == true
                ? VLMSnapperStrings.providerStorageReadFailure
                : VLMSnapperStrings.failureMessage(code: "local_storage")
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
                        if historyRetry.recordID == record.id {
                            historyRetryContent
                            if historyRetry.slot.attempt == .succeeded { metrics(record) }
                        }
                        if historyRetry.recordID != record.id || (!historyRetry.isRunning
                            && historyRetry.slot.attempt != .succeeded && historyRetry.slot.unsavedResult == nil) {
                            resultSection(VLMSnapperStrings.historyOriginal, text: record.operation.sourceMarkdown)
                            if record.operation.kind == .translate {
                                resultSection(VLMSnapperStrings.historyTranslation, text: record.operation.translationMarkdown)
                            }
                            metrics(record)
                        }
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
            Button { callbacks.onRetryRecord(record.id) } label: {
                Group {
                    if historyRetry.isRunning && historyRetry.recordID == record.id {
                        ProgressView().controlSize(.small)
                    } else {
                        VLMSnapperIcon.retry.image
                    }
                }
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!historyRetry.allowsStart || historyRetry.isRunning
                      || record.operation.status.isActive || selectedImage == nil || imageRecordID != record.id)
            .help(VLMSnapperStrings.retry)
            .accessibilityLabel(VLMSnapperStrings.retry)
            .accessibilityIdentifier("history-retry")
            Button {
                callbacks.onSetPinned(record.id, !record.isPinned)
            } label: {
                (record.isPinned ? VLMSnapperIcon.pinned : VLMSnapperIcon.pin).image
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) { pendingDeletion = record } label: {
                VLMSnapperIcon.delete.image
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(record.operation.status.isActive || historyRetry.preventsDiscard)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
    }

    private var historyRetryContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(VLMSnapperStrings.retry).font(.headline)
                Spacer()
                Text(historyRetry.providerSummary).font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            switch historyRetry.slot.attempt {
            case .neverStarted, .preparing:
                Text(VLMSnapperStrings.preparing)
            case .streaming:
                Text(VLMSnapperStrings.streaming)
                resultSection(VLMSnapperStrings.historyOriginal, text: historyRetry.slot.sourceDelta)
                resultSection(VLMSnapperStrings.historyTranslation, text: historyRetry.slot.translationDelta)
            case .succeeded:
                Text(VLMSnapperStrings.menuStatusSucceeded).foregroundStyle(VLMSnapperTheme.success)
                resultSection(VLMSnapperStrings.historyOriginal, text: historyRetry.slot.committedResult?.sourceMarkdown)
                resultSection(VLMSnapperStrings.historyTranslation, text: historyRetry.slot.committedResult?.translationMarkdown)
            case let .failed(code):
                Text(code == "history_screenshot_unavailable" ? VLMSnapperStrings.historyScreenshotUnavailable
                     : VLMSnapperStrings.failureMessage(code: code))
                    .foregroundStyle(VLMSnapperTheme.destructive)
            case .canceled:
                Text(VLMSnapperStrings.canceled)
            case .resultPersistenceFailed:
                resultSection(VLMSnapperStrings.historyOriginal, text: historyRetry.slot.unsavedResult?.sourceMarkdown)
                resultSection(VLMSnapperStrings.historyTranslation, text: historyRetry.slot.unsavedResult?.translationMarkdown)
                Text(historyRetry.slot.persistenceFailureCode.map(VLMSnapperStrings.failureMessage(code:))
                     ?? VLMSnapperStrings.persistenceFailed).foregroundStyle(VLMSnapperTheme.destructive)
                Button(VLMSnapperStrings.retrySave, action: callbacks.onRetryHistorySave)
                    .disabled(historyRetry.isRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                && (historyProviderID == nil || record.operation.selection.providerID == historyProviderID)
                && (query.isEmpty || searchable.contains(query))
        }
    }

    private var selectedRecord: HistoryRecord? {
        filteredRecords.first { $0.id == selectedRecordID } ?? filteredRecords.first
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VLMSnapperTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.top, 14)
    }

    private func navButton(_ title: String, icon: VLMSnapperIcon, count: Int? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon.rawValue)
                Spacer(minLength: 0)
                if let count {
                    Text(count, format: .number)
                        .font(.caption)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
                .background(selected ? VLMSnapperTheme.accent.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: VLMSnapperUIConstants.compactCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func historyRow(_ record: HistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(record.operation.sourceMarkdown ?? VLMSnapperStrings.failed)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VLMSnapperTheme.historyTitle)
                .lineLimit(1)
                .padding(.bottom, 6)
            Text(historySummary(record))
                .font(.system(size: 11))
                .foregroundStyle(VLMSnapperTheme.historySummary)
                .lineLimit(1)
                .padding(.bottom, 7)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    historyRowTags(record).fixedSize()
                    Spacer(minLength: 10)
                    historyRowDate(record).fixedSize()
                }
                VStack(alignment: .leading, spacing: 5) {
                    historyRowTags(record)
                    historyRowDate(record).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.system(size: 10))
        }
    }

    private func historySummary(_ record: HistoryRecord) -> String {
        if let translation = record.operation.translationMarkdown, !translation.isEmpty { return translation }
        if let source = record.operation.sourceMarkdown, !source.isEmpty { return source }
        return historyStatus(record.operation.status).text
    }

    private func historyRowTags(_ record: HistoryRecord) -> some View {
        HStack(spacing: 7) {
            Text(record.operation.kind == .extract ? VLMSnapperStrings.historyExtract : VLMSnapperStrings.translate)
                .foregroundStyle(VLMSnapperTheme.historyType)
            Text(historyStatus(record.operation.status).text)
                .foregroundStyle(historyStatus(record.operation.status).color)
        }
    }

    private func historyRowDate(_ record: HistoryRecord) -> some View {
        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
            .foregroundStyle(VLMSnapperTheme.historyDate)
            .multilineTextAlignment(.trailing)
    }

    private func historyStatus(_ status: OperationStatus) -> (text: String, color: Color) {
        switch status {
        case .succeeded: (VLMSnapperStrings.menuStatusSucceeded, VLMSnapperTheme.historySucceeded)
        case .canceled: (VLMSnapperStrings.menuStatusCanceled, VLMSnapperTheme.historyCanceled)
        case .interrupted: (VLMSnapperStrings.historyInterrupted, VLMSnapperTheme.historyFailed)
        case .failed, .resultPersistenceFailed: (VLMSnapperStrings.menuStatusFailed, VLMSnapperTheme.historyFailed)
        case .preparing, .uploading, .streaming: (VLMSnapperStrings.menuStatusActive, VLMSnapperTheme.secondaryText)
        }
    }

    @ViewBuilder
    private func screenshot(_ record: HistoryRecord) -> some View {
        if let selectedImage, imageRecordID == record.id {
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

    private func reconcileHistorySelection() {
        if !filteredRecords.contains(where: { $0.id == selectedRecordID }) {
            selectedRecordID = filteredRecords.first?.id
        }
    }

    private var retentionShorteningTitle: String {
        String(
            format: VLMSnapperStrings.historyRetentionShorteningConfirm,
            settings.retentionShorteningRecordCount ?? 0
        )
    }
}
