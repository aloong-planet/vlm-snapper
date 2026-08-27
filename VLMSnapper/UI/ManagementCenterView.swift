import AppKit
import SwiftUI
import VLMSnapperCore

public struct ManagementCenterCallbacks {
    public let onSelectRecord: (UUID) -> Void
    public let onSetPinned: (UUID, Bool) -> Void
    public let onDelete: (UUID) -> Void
    public let onClearHistory: (Bool) -> Void
    public let onRetryCleanup: () -> Void
    public let onRetentionChange: (HistoryRetentionPeriod) -> Void

    public init(
        onSelectRecord: @escaping (UUID) -> Void = { _ in },
        onSetPinned: @escaping (UUID, Bool) -> Void = { _, _ in },
        onDelete: @escaping (UUID) -> Void = { _ in },
        onClearHistory: @escaping (Bool) -> Void = { _ in },
        onRetryCleanup: @escaping () -> Void = {},
        onRetentionChange: @escaping (HistoryRetentionPeriod) -> Void = { _ in }
    ) {
        self.onSelectRecord = onSelectRecord
        self.onSetPinned = onSetPinned
        self.onDelete = onDelete
        self.onClearHistory = onClearHistory
        self.onRetryCleanup = onRetryCleanup
        self.onRetentionChange = onRetentionChange
    }
}

public struct ManagementCenterView: View {
    private let records: [HistoryRecord]
    private let selectedImage: NSImage?
    private let cleanupFailureCount: Int
    private let callbacks: ManagementCenterCallbacks
    @State private var destination: ManagementCenterDestination
    @State private var kind: HistoryOperationKindFilter = .all
    @State private var searchText: String
    @State private var selectedRecordID: UUID?
    @State private var retention: HistoryRetentionPeriod
    @State private var pinnedOnly = false
    @State private var showGeneralSettings = false
    @State private var pendingDeletion: HistoryRecord?
    @State private var showingClearConfirmation = false

    public init(
        destination: ManagementCenterDestination,
        records: [HistoryRecord],
        selectedRecordID: UUID? = nil,
        selectedImage: NSImage? = nil,
        cleanupFailureCount: Int = 0,
        searchText: String = "",
        retention: HistoryRetentionPeriod = .thirtyDays,
        callbacks: ManagementCenterCallbacks = ManagementCenterCallbacks()
    ) {
        self.records = records
        self.selectedImage = selectedImage
        self.cleanupFailureCount = cleanupFailureCount
        self.callbacks = callbacks
        _destination = State(initialValue: destination)
        _selectedRecordID = State(initialValue: selectedRecordID ?? records.first?.id)
        _searchText = State(initialValue: searchText)
        _retention = State(initialValue: retention)
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
        .frame(width: 205)
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
        .frame(height: 54)
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
            } else {
                Section(VLMSnapperStrings.historyProviderSettings) {
                    Label(VLMSnapperStrings.providerSetupTitle, systemImage: VLMSnapperIcon.providerList.rawValue)
                    Text(VLMSnapperStrings.providerSetupSubtitle)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    @ViewBuilder
    private var detail: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.operation.sourceMarkdown ?? VLMSnapperStrings.failed)
                                .font(.title2.bold()).lineLimit(2)
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
                    screenshot(record)
                    resultSection(VLMSnapperStrings.historyOriginal, text: record.operation.sourceMarkdown)
                    if record.operation.kind == .translate {
                        resultSection(VLMSnapperStrings.historyTranslation, text: record.operation.translationMarkdown)
                    }
                    metrics(record)
                }
                .padding(22)
            }
        } else {
            ContentUnavailableView(VLMSnapperStrings.historyEmptyTitle, systemImage: VLMSnapperIcon.history.rawValue)
        }
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
}
