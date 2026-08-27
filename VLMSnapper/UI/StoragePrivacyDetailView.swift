import SwiftUI

public struct StoragePrivacyDetailView: View {
    private let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(VLMSnapperStrings.privacyDetailsTitle).font(.title2.bold())
                Spacer()
                Button(action: onClose) {
                    VLMSnapperIcon.close.image
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VLMSnapperStrings.close)
            }
            .padding(24)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                section(
                    icon: .provider,
                    title: VLMSnapperStrings.privacyUploadTitle,
                    body: VLMSnapperStrings.privacyUploadBody
                )
                Divider()
                section(
                    icon: .folder,
                    title: VLMSnapperStrings.privacyStorageTitle,
                    body: VLMSnapperStrings.privacyStorageBody
                )
                Divider()
                section(
                    icon: .history,
                    title: VLMSnapperStrings.privacyRetentionTitle,
                    body: VLMSnapperStrings.privacyRetentionBody
                )
                Divider()
                section(
                    icon: .info,
                    title: VLMSnapperStrings.privacyBackupTitle,
                    body: VLMSnapperStrings.privacyBackupBody
                )
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Spacer()
                Button(VLMSnapperStrings.close, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)
        }
        .background(VLMSnapperTheme.window)
        .clipShape(
            RoundedRectangle(
                cornerRadius: VLMSnapperUIConstants.attachedSheetCornerRadius,
                style: .continuous
            )
        )
        .frame(width: 620, height: 520)
    }

    private func section(
        icon: VLMSnapperIcon,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            icon.image
                .foregroundStyle(VLMSnapperTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(body)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 18)
    }
}
