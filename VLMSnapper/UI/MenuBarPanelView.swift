import SwiftUI

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
    private let onCapture: () -> Void
    private let onOpenRecent: (String) -> Void
    private let onNavigate: (ManagementCenterDestination) -> Void
    private let onCheckUpdates: () -> Void
    private let onQuit: () -> Void

    public init(
        recentItems: [MenuRecentItem],
        onCapture: @escaping () -> Void,
        onOpenRecent: @escaping (String) -> Void,
        onNavigate: @escaping (ManagementCenterDestination) -> Void,
        onCheckUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.recentItems = recentItems
        self.onCapture = onCapture
        self.onOpenRecent = onOpenRecent
        self.onNavigate = onNavigate
        self.onCheckUpdates = onCheckUpdates
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button(action: onCapture) {
                Label(VLMSnapperStrings.menuCapture, systemImage: VLMSnapperIcon.capture.rawValue)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .background(VLMSnapperTheme.accent.opacity(0.12))
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
