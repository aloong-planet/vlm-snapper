import SwiftUI
import VLMSnapperCore

public struct ScreenCapturePermissionRecoveryView: View {
    private let state: ScreenCapturePermissionReadiness
    private let onPrimaryAction: () -> Void
    private let onDismiss: () -> Void

    public init(
        state: ScreenCapturePermissionReadiness,
        onPrimaryAction: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.state = state
        self.onPrimaryAction = onPrimaryAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.bold())
                    Text(subtitle)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onDismiss) {
                    VLMSnapperIcon.close.image.frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(VLMSnapperStrings.close)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VLMSnapperIcon.permission.image
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(VLMSnapperTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(VLMSnapperTheme.subtleSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(explanationTitle).font(.headline)
                        Text(explanation)
                            .font(.callout)
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if state != .restartRequired && state != .ready {
                    VStack(alignment: .leading, spacing: 9) {
                        recoveryStep(1, VLMSnapperStrings.permissionRecoveryStepOne)
                        recoveryStep(2, VLMSnapperStrings.permissionRecoveryStepTwo)
                    }
                    .padding(12)
                    .background(VLMSnapperTheme.subtleSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 17)
            Divider()
            HStack {
                Text(footerNote)
                    .font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .frame(maxWidth: 270, alignment: .leading)
                Spacer()
                Button(VLMSnapperStrings.cancel, action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                if state != .ready {
                    Button(primaryTitle, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .background(VLMSnapperTheme.window)
        .clipShape(
            RoundedRectangle(
                cornerRadius: PermissionRecoveryMetrics.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: PermissionRecoveryMetrics.cornerRadius,
                style: .continuous
            )
            .stroke(VLMSnapperTheme.border, lineWidth: 1)
        }
        .frame(width: PermissionRecoveryMetrics.width)
        .permitsApplicationTerminationWhilePresented()
    }

    private var title: String {
        state == .restartRequired
            ? VLMSnapperStrings.permissionRecoveryRestartTitle
            : VLMSnapperStrings.permissionRecoveryBlockedTitle
    }

    private var subtitle: String {
        state == .restartRequired
            ? VLMSnapperStrings.permissionRecoveryRestartSubtitle
            : VLMSnapperStrings.permissionRecoverySubtitle
    }

    private var explanationTitle: String {
        switch state {
        case .notRequested: VLMSnapperStrings.permissionRecoveryNotGrantedTitle
        case .unavailable: VLMSnapperStrings.permissionRecoveryRevokedTitle
        case .restartRequired: VLMSnapperStrings.permissionRecoveryEnabledTitle
        case .ready: VLMSnapperStrings.permissionReady
        }
    }

    private var explanation: String {
        switch state {
        case .notRequested: VLMSnapperStrings.permissionRecoveryInitial
        case .unavailable: VLMSnapperStrings.permissionRecoveryDenied
        case .restartRequired: VLMSnapperStrings.permissionRecoveryRestart
        case .ready: VLMSnapperStrings.permissionReady
        }
    }

    private var footerNote: String {
        state == .restartRequired
            ? VLMSnapperStrings.permissionRecoveryRestartNote
            : VLMSnapperStrings.permissionRecoveryLaterNote
    }

    private func recoveryStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(number))
                .font(.caption2.bold())
                .foregroundStyle(VLMSnapperTheme.accent)
                .frame(width: 20, height: 20)
                .background(VLMSnapperTheme.accent.opacity(0.10), in: Circle())
            Text(text)
                .font(.callout)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
        }
    }

    private var primaryTitle: String {
        switch state {
        case .notRequested: VLMSnapperStrings.configure
        case .unavailable: VLMSnapperStrings.openSettings
        case .restartRequired: VLMSnapperStrings.restart
        case .ready: VLMSnapperStrings.done
        }
    }
}
