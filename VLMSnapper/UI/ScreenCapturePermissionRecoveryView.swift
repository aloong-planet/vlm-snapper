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
            HStack(alignment: .top, spacing: 14) {
                VLMSnapperIcon.permission.image
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(VLMSnapperTheme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(VLMSnapperStrings.permissionRecoveryTitle).font(.title2.bold())
                    Text(detail)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            Divider()
            HStack {
                Button(VLMSnapperStrings.cancel, action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if state != .ready {
                    Button(primaryTitle, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                }
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
        .overlay {
            RoundedRectangle(
                cornerRadius: VLMSnapperUIConstants.attachedSheetCornerRadius,
                style: .continuous
            )
            .stroke(VLMSnapperTheme.border, lineWidth: 1)
        }
        .frame(width: 470)
    }

    private var detail: String {
        switch state {
        case .notRequested: VLMSnapperStrings.permissionRecoveryInitial
        case .unavailable: VLMSnapperStrings.permissionRecoveryDenied
        case .restartRequired: VLMSnapperStrings.permissionRecoveryRestart
        case .ready: VLMSnapperStrings.permissionReady
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
