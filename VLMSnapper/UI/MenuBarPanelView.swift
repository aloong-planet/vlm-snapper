import AppKit
import SwiftUI
import VLMSnapperCore

public enum ManagementCenterDestination: Equatable, Sendable {
    case history
    case settings
}

public struct MenuRecentItem: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case active
        case succeeded
        case failed
        case canceled
    }

    public let id: String
    public let title: String
    public let detail: String
    public let status: Status
    public let screenshotURL: URL

    public init(
        id: String,
        title: String,
        detail: String,
        status: Status = .succeeded,
        screenshotURL: URL = URL(fileURLWithPath: "/dev/null")
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.screenshotURL = screenshotURL
    }

    public init(record: HistoryRecord, now: Date = Date()) {
        id = record.id.uuidString
        title = Self.title(for: record)
        detail = "\(Self.operationLabel(for: record.operation.kind)) · \(Self.relativeTime(from: record.createdAt, to: now))"
        status = Self.status(for: record.operation.status)
        screenshotURL = URL(fileURLWithPath: record.operation.screenshot.path)
    }

    private static func title(for record: HistoryRecord) -> String {
        if let source = record.operation.sourceMarkdown,
           let firstLine = source.split(whereSeparator: \.isNewline).first,
           !firstLine.isEmpty {
            let line = String(firstLine).trimmingCharacters(in: .whitespaces)
            let title = line.drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty {
                return title
            }
        }
        if record.operation.status == .failed {
            return VLMSnapperStrings.menuProviderRequestFailed
        }
        return operationLabel(for: record.operation.kind)
    }

    private static func operationLabel(for kind: PersistedOperationKind) -> String {
        switch kind {
        case .extract: VLMSnapperStrings.extract
        case .translate: VLMSnapperStrings.translate
        }
    }

    private static func status(for status: OperationStatus) -> Status {
        switch status {
        case .preparing, .uploading, .streaming: .active
        case .succeeded: .succeeded
        case .failed, .interrupted, .resultPersistenceFailed: .failed
        case .canceled: .canceled
        }
    }

    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return VLMSnapperStrings.menuTimeNow
        }
        if seconds < 3_600 {
            return String(format: VLMSnapperStrings.menuTimeMinutesFormat, seconds / 60)
        }
        if seconds < 86_400 {
            return String(format: VLMSnapperStrings.menuTimeHoursFormat, seconds / 3_600)
        }
        return String(format: VLMSnapperStrings.menuTimeDaysFormat, seconds / 86_400)
    }
}

public struct MenuProviderPresentation: Equatable, Sendable {
    public let providerName: String?
    public let isAvailable: Bool

    public init(readiness: ProviderReadiness) {
        switch readiness {
        case .missing:
            providerName = nil
            isAvailable = false
        case let .pendingModel(provider):
            providerName = VLMSnapperStrings.providerName(provider)
            isAvailable = false
        case let .ready(provider, _):
            providerName = VLMSnapperStrings.providerName(provider)
            isAvailable = true
        }
    }

    var label: String {
        guard let providerName else {
            return VLMSnapperStrings.menuSetupRequired
        }
        return isAvailable
            ? String(format: VLMSnapperStrings.menuProviderAvailableFormat, providerName)
            : String(format: VLMSnapperStrings.menuProviderNeedsModelFormat, providerName)
    }
}

public enum MenuBarPanelMetrics {
    public static let width: CGFloat = 370
    public static let outerCornerRadius: CGFloat = 13
    public static let captureButtonHeight: CGFloat = 36
    public static let recentThumbnailSize = CGSize(width: 58, height: 42)
}

public struct MenuBarPanelView: View {
    private let recentItems: [MenuRecentItem]
    private let provider: ProviderReadiness
    private let updateState: UpdateLifecycleState
    private let captureShortcut: String
    private let onCapture: () -> Void
    private let onOpenRecent: (String) -> Void
    private let onNavigate: (ManagementCenterDestination) -> Void
    private let onCheckUpdates: () -> Void
    private let onDownloadUpdate: () -> Void
    private let onOpenUpdateInformation: (URL) -> Void

    public init(
        recentItems: [MenuRecentItem],
        provider: ProviderReadiness = .missing,
        updateState: UpdateLifecycleState = .idle,
        captureShortcut: String = "⌥⇧S",
        onCapture: @escaping () -> Void,
        onOpenRecent: @escaping (String) -> Void,
        onNavigate: @escaping (ManagementCenterDestination) -> Void,
        onCheckUpdates: @escaping () -> Void,
        onDownloadUpdate: @escaping () -> Void = {},
        onOpenUpdateInformation: @escaping (URL) -> Void = { _ in }
    ) {
        self.recentItems = recentItems
        self.provider = provider
        self.updateState = updateState
        self.captureShortcut = captureShortcut
        self.onCapture = onCapture
        self.onOpenRecent = onOpenRecent
        self.onNavigate = onNavigate
        self.onCheckUpdates = onCheckUpdates
        self.onDownloadUpdate = onDownloadUpdate
        self.onOpenUpdateInformation = onOpenUpdateInformation
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("VLMSnapper")
                    .font(.title3.bold())
                Spacer()
                providerBadge
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            Button(action: onCapture) {
                HStack {
                    Label(VLMSnapperStrings.menuCapture, systemImage: VLMSnapperIcon.capture.rawValue)
                    Spacer()
                    Text(captureShortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
                .font(.headline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(height: MenuBarPanelMetrics.captureButtonHeight)
            }
            .buttonStyle(.plain)
            .background(VLMSnapperTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 10)
            if updateState.showsMenuNotice {
                updateNotice
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(VLMSnapperStrings.menuRecent)
                    .font(.caption.bold())
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                if recentItems.isEmpty {
                    Text(VLMSnapperStrings.noRecentItems)
                        .font(.callout)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    ForEach(recentItems.prefix(3)) { item in
                        Button { onOpenRecent(item.id) } label: {
                            HStack(spacing: 10) {
                                recentThumbnail(for: item)
                                    .frame(
                                        width: MenuBarPanelMetrics.recentThumbnailSize.width,
                                        height: MenuBarPanelMetrics.recentThumbnailSize.height
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(VLMSnapperTheme.border)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                statusBadge(for: item.status)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 8)
            Divider()
            HStack(spacing: 0) {
                footerButton(VLMSnapperStrings.menuHistory) { onNavigate(.history) }
                Divider().frame(height: 38)
                footerButton(VLMSnapperStrings.menuSettings) { onNavigate(.settings) }
            }
        }
        .background(VLMSnapperTheme.window)
        .clipShape(RoundedRectangle(cornerRadius: MenuBarPanelMetrics.outerCornerRadius))
        .frame(width: MenuBarPanelMetrics.width)
    }

    private var providerBadge: some View {
        let presentation = MenuProviderPresentation(readiness: provider)
        return Text(presentation.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(presentation.isAvailable ? Color.green : VLMSnapperTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (presentation.isAvailable ? Color.green : VLMSnapperTheme.secondaryText)
                    .opacity(0.10),
                in: Capsule()
            )
    }

    @ViewBuilder
    private func recentThumbnail(for item: MenuRecentItem) -> some View {
        if let image = NSImage(contentsOf: item.screenshotURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                VLMSnapperTheme.surface
                VLMSnapperIcon.capture.image
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
        }
    }

    private func statusBadge(for status: MenuRecentItem.Status) -> some View {
        let presentation: (String, Color) = switch status {
        case .active: (VLMSnapperStrings.menuStatusActive, VLMSnapperTheme.accent)
        case .succeeded: (VLMSnapperStrings.menuStatusSucceeded, .green)
        case .failed: (VLMSnapperStrings.menuStatusFailed, .red)
        case .canceled: (VLMSnapperStrings.menuStatusCanceled, VLMSnapperTheme.secondaryText)
        }
        return Text(presentation.0)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(presentation.1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(presentation.1.opacity(0.10), in: Capsule())
    }

    private var updateNotice: some View {
        HStack(spacing: 9) {
            updateNoticeIcon
                .frame(width: 28, height: 28)
                .background(VLMSnapperTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(updateState.menuTitle).font(.caption.bold()).lineLimit(1)
                Text(updateState.menuDetail)
                    .font(.caption2)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            switch updateState {
            case .available:
                Button(VLMSnapperStrings.updateDownload, action: onDownloadUpdate)
                    .buttonStyle(.bordered)
            case .readyToInstall:
                Button(VLMSnapperStrings.updateView) { onNavigate(.settings) }
                    .buttonStyle(.bordered)
            default:
                EmptyView()
            }
        }
        .padding(9)
        .background(VLMSnapperTheme.accent.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VLMSnapperTheme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var updateNoticeIcon: some View {
        switch updateState {
        case .downloading:
            ProgressView().controlSize(.small)
        case .readyToInstall:
            VLMSnapperIcon.downloaded.image.foregroundStyle(VLMSnapperTheme.accent)
        default:
            VLMSnapperIcon.update.image.foregroundStyle(VLMSnapperTheme.accent)
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .frame(height: 42)
        }
        .buttonStyle(.plain)
    }
}

private extension UpdateLifecycleState {
    var showsMenuNotice: Bool {
        showsAttentionIndicator
    }

    var menuTitle: String {
        switch self {
        case let .available(version):
            String(format: VLMSnapperStrings.updateAvailableTitleFormat, version.displayVersion)
        case let .downloading(version, _, _):
            String(format: VLMSnapperStrings.updateDownloadingTitleFormat, version.displayVersion)
        case let .readyToInstall(version):
            String(format: VLMSnapperStrings.updateReadyTitleFormat, version.displayVersion)
        default: ""
        }
    }

    var menuDetail: String {
        switch self {
        case .available: VLMSnapperStrings.updateAvailableMenuDetail
        case .downloading: VLMSnapperStrings.updateDownloadingMenuDetail
        case .readyToInstall: VLMSnapperStrings.updateReadyMenuDetail
        default: ""
        }
    }
}
