import SwiftUI
import VLMSnapperCore

public struct OnboardingView: View {
    private let snapshot: OnboardingSnapshot
    private let onConfigurePermission: () -> Void
    private let onConfigureProvider: () -> Void
    private let onViewPrivacy: () -> Void
    private let onStart: () -> Void
    private let onFinishLater: () -> Void

    public init(
        snapshot: OnboardingSnapshot,
        onConfigurePermission: @escaping () -> Void,
        onConfigureProvider: @escaping () -> Void,
        onViewPrivacy: @escaping () -> Void,
        onStart: @escaping () -> Void,
        onFinishLater: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.onConfigurePermission = onConfigurePermission
        self.onConfigureProvider = onConfigureProvider
        self.onViewPrivacy = onViewPrivacy
        self.onStart = onStart
        self.onFinishLater = onFinishLater
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(VLMSnapperStrings.onboardingTitle).font(.title.bold())
                Text(VLMSnapperStrings.onboardingSubtitle)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .frame(height: 76)
            Divider()
            VStack(spacing: 12) {
                permissionRow
                providerRow
                privacyRow
                if let blocker = snapshot.blocker {
                    Label(
                        blocker == .screenCapturePermission
                            ? VLMSnapperStrings.permissionBlocker
                            : VLMSnapperStrings.providerBlocker,
                        systemImage: VLMSnapperIcon.warning.rawValue
                    )
                    .font(.callout)
                    .foregroundStyle(VLMSnapperTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button(VLMSnapperStrings.finishLater, action: onFinishLater)
                Spacer()
                Button(VLMSnapperStrings.startUsing, action: onStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(!snapshot.canStart)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
        }
        .background(VLMSnapperTheme.window)
        .frame(width: OnboardingMetrics.width)
        .frame(minHeight: OnboardingMetrics.minimumHeight)
    }

    private var permissionRow: some View {
        readinessRow(
            icon: .permission,
            title: VLMSnapperStrings.permissionTitle,
            detail: permissionDetail,
            complete: snapshot.permission == .ready,
            actionTitle: snapshot.permission == .ready
                ? VLMSnapperStrings.modify
                : VLMSnapperStrings.configure,
            action: onConfigurePermission
        )
    }

    private var providerRow: some View {
        readinessRow(
            icon: .provider,
            title: VLMSnapperStrings.providerTitle,
            detail: providerDetail,
            complete: providerIsReady,
            actionTitle: providerActionTitle,
            action: onConfigureProvider
        )
    }

    private var privacyRow: some View {
        readinessRow(
            icon: .info,
            title: VLMSnapperStrings.privacyTitle,
            detail: VLMSnapperStrings.privacySummary,
            complete: true,
            actionTitle: VLMSnapperStrings.viewDetails,
            action: onViewPrivacy
        )
    }

    private func readinessRow(
        icon: VLMSnapperIcon,
        title: String,
        detail: String,
        complete: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            icon.image
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(VLMSnapperTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if complete {
                VLMSnapperIcon.complete.image
                    .foregroundStyle(VLMSnapperTheme.success)
                    .accessibilityHidden(true)
            }
            Button(actionTitle, action: action)
        }
        .padding(14)
        .frame(minHeight: OnboardingMetrics.rowMinimumHeight)
        .background(VLMSnapperTheme.surface)
        .clipShape(
            RoundedRectangle(cornerRadius: OnboardingMetrics.rowCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingMetrics.rowCornerRadius, style: .continuous)
                .stroke(VLMSnapperTheme.border, lineWidth: 1)
        }
    }

    private var permissionDetail: String {
        switch snapshot.permission {
        case .notRequested: VLMSnapperStrings.permissionRecoveryInitial
        case .unavailable: VLMSnapperStrings.permissionRecoveryDenied
        case .restartRequired: VLMSnapperStrings.permissionRecoveryRestart
        case .ready: VLMSnapperStrings.permissionReady
        }
    }

    private var providerDetail: String {
        switch snapshot.provider {
        case .missing:
            VLMSnapperStrings.notConfigured
        case let .pendingModel(provider):
            "\(VLMSnapperStrings.providerName(provider)) · \(VLMSnapperStrings.modelPending)"
        case let .ready(provider, modelID):
            "\(VLMSnapperStrings.providerName(provider)) · \(modelID)"
        }
    }

    private var providerIsReady: Bool {
        if case .ready = snapshot.provider { true } else { false }
    }

    private var providerActionTitle: String {
        switch snapshot.provider {
        case .missing: VLMSnapperStrings.configure
        case .pendingModel: VLMSnapperStrings.continueSetup
        case .ready: VLMSnapperStrings.modify
        }
    }
}
