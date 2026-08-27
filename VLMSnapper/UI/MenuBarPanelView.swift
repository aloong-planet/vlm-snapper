import SwiftUI
import VLMSnapperCore

public enum ManagementCenterDestination: Equatable, Sendable {
    case history
    case settings
}

public struct MenuRecentItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct MenuBarPanelView: View {
    private let recentItems: [MenuRecentItem]
    private let updateState: UpdateLifecycleState
    private let captureShortcut: String
    private let onCapture: () -> Void
    private let onOpenRecent: (String) -> Void
    private let onNavigate: (ManagementCenterDestination) -> Void
    private let onCheckUpdates: () -> Void
    private let onDownloadUpdate: () -> Void
    private let onOpenUpdateInformation: (URL) -> Void
    private let onQuit: () -> Void

    public init(
        recentItems: [MenuRecentItem],
        updateState: UpdateLifecycleState = .idle,
        captureShortcut: String = "⌥⇧S",
        onCapture: @escaping () -> Void,
        onOpenRecent: @escaping (String) -> Void,
        onNavigate: @escaping (ManagementCenterDestination) -> Void,
        onCheckUpdates: @escaping () -> Void,
        onDownloadUpdate: @escaping () -> Void = {},
        onOpenUpdateInformation: @escaping (URL) -> Void = { _ in },
        onQuit: @escaping () -> Void
    ) {
        self.recentItems = recentItems
        self.updateState = updateState
        self.captureShortcut = captureShortcut
        self.onCapture = onCapture
        self.onOpenRecent = onOpenRecent
        self.onNavigate = onNavigate
        self.onCheckUpdates = onCheckUpdates
        self.onDownloadUpdate = onDownloadUpdate
        self.onOpenUpdateInformation = onOpenUpdateInformation
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: onCapture) {
                HStack {
                    Label(VLMSnapperStrings.menuCapture, systemImage: VLMSnapperIcon.capture.rawValue)
                    Spacer()
                    Text(captureShortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
                .font(.headline)
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .buttonStyle(.plain)
            .background(VLMSnapperTheme.accent.opacity(0.12))
            if updateState.showsMenuNotice {
                updateNotice
            }
            Divider()
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).lineLimit(1)
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            menuButton(VLMSnapperStrings.menuHistory, icon: .history) {
                onNavigate(.history)
            }
            menuButton(VLMSnapperStrings.menuSettings, icon: .settings) {
                onNavigate(.settings)
            }
            Divider()
            menuButton(VLMSnapperStrings.menuCheckUpdates, icon: .update, action: onCheckUpdates)
            menuButton(VLMSnapperStrings.menuQuit, icon: .quit, action: onQuit)
        }
        .padding(.vertical, 6)
        .background(VLMSnapperTheme.window)
        .frame(width: 330)
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

    private func menuButton(
        _ title: String,
        icon: VLMSnapperIcon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon.rawValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 34)
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
