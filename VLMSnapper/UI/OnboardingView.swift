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
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    OnboardingBrandMark()
                        .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(VLMSnapperTheme.onAccent)
                        .frame(width: 26, height: 26)
                        .frame(width: 44, height: 44)
                        .background(VLMSnapperTheme.accent, in: RoundedRectangle(cornerRadius: 11))
                        .frame(width: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(VLMSnapperStrings.onboardingIntroTitle).font(.system(size: 25, weight: .bold))
                        Text(VLMSnapperStrings.onboardingIntroDescription)
                            .font(.system(size: 13))
                            .foregroundStyle(VLMSnapperTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 12)
                VStack(spacing: 10) {
                    permissionRow
                    providerRow
                    privacyRow
                }
                readinessGate
                HStack(spacing: 14) {
                    Text(VLMSnapperStrings.onboardingPrivacyNote)
                        .font(.system(size: 11))
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button(VLMSnapperStrings.finishLater, action: onFinishLater)
                            .buttonStyle(.borderless)
                        Button(VLMSnapperStrings.startUsing, action: onStart)
                            .buttonStyle(.borderedProminent)
                            .disabled(!snapshot.canStart)
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 32)
            .padding(.top, 26)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
        }
        .background(VLMSnapperTheme.window)
        .frame(width: OnboardingMetrics.width)
        .frame(minHeight: OnboardingMetrics.minimumHeight)
    }

    private var permissionRow: some View {
        readinessRow(
            icon: .permission,
            title: VLMSnapperStrings.permissionTitle,
            detail: permissionStatus,
            description: VLMSnapperStrings.onboardingPermissionDescription,
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
            description: VLMSnapperStrings.onboardingProviderDescription,
            complete: providerIsReady,
            actionTitle: VLMSnapperStrings.onboardingProviderAction,
            action: onConfigureProvider
        )
    }

    private var privacyRow: some View {
        readinessRow(
            icon: .info,
            title: VLMSnapperStrings.privacyTitle,
            detail: VLMSnapperStrings.onboardingImportant,
            description: VLMSnapperStrings.onboardingPrivacyDescription,
            complete: true,
            actionTitle: VLMSnapperStrings.viewDetails,
            action: onViewPrivacy
        )
    }

    private func readinessRow(
        icon: VLMSnapperIcon,
        title: String,
        detail: String,
        description: String,
        complete: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            icon.image
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(VLMSnapperTheme.accent)
                .frame(width: 40, height: 40)
                .background(VLMSnapperTheme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 3)
                Text(detail)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(complete ? VLMSnapperTheme.success : VLMSnapperTheme.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(complete ? VLMSnapperTheme.successSoft : VLMSnapperTheme.warningSoft,
                                in: RoundedRectangle(cornerRadius: 9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(actionTitle, action: action)
                .buttonStyle(SetupActionButtonStyle(horizontalPadding: 12))
                .fixedSize()
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

    private var readinessGate: some View {
        HStack(alignment: .top, spacing: 10) {
            (snapshot.canStart ? VLMSnapperIcon.downloaded : VLMSnapperIcon.warning).image
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(gateTitle).font(.system(size: 11, weight: .semibold))
                Text(gateDetail + " " + VLMSnapperStrings.onboardingLaterNote)
                    .font(.system(size: 10))
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(snapshot.canStart ? VLMSnapperTheme.success : VLMSnapperTheme.warning)
        .background(snapshot.canStart ? VLMSnapperTheme.successSoft : VLMSnapperTheme.warningSoft,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke((snapshot.canStart ? VLMSnapperTheme.success : VLMSnapperTheme.warning).opacity(0.28)))
    }

    private var gateTitle: String {
        if snapshot.canStart { return VLMSnapperStrings.onboardingReadyTitle }
        if snapshot.permission == .ready { return VLMSnapperStrings.providerBlocker }
        if providerIsReady { return VLMSnapperStrings.permissionBlocker }
        return VLMSnapperStrings.onboardingBothMissingTitle
    }

    private var gateDetail: String {
        if snapshot.canStart { return VLMSnapperStrings.onboardingReadyDetail }
        if snapshot.permission == .ready { return VLMSnapperStrings.onboardingProviderDescription }
        if providerIsReady { return permissionDetail }
        return VLMSnapperStrings.onboardingBothMissingDetail
    }

    private var permissionDetail: String {
        switch snapshot.permission {
        case .notRequested: VLMSnapperStrings.permissionRecoveryInitial
        case .unavailable: VLMSnapperStrings.permissionRecoveryDenied
        case .restartRequired: VLMSnapperStrings.permissionRecoveryRestart
        case .ready: VLMSnapperStrings.permissionReady
        }
    }

    private var permissionStatus: String {
        switch snapshot.permission {
        case .notRequested, .unavailable: VLMSnapperStrings.onboardingPermissionMissing
        case .restartRequired: VLMSnapperStrings.onboardingPermissionRestart
        case .ready: VLMSnapperStrings.onboardingPermissionReady
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

}
