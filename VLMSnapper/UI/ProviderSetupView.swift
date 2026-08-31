import SwiftUI
import VLMSnapperCore

public struct ProviderSetupView: View {
    private let snapshot: ProviderSetupSnapshot
    @Binding private var apiKey: String
    @Binding private var pendingModelID: String?
    private let onSelectProvider: (ProviderID) -> Void
    private let onValidate: () -> Void
    private let onRefresh: () -> Void
    private let onSelectModel: (String) -> Void
    private let onCancel: () -> Void
    private let onDone: () -> Void

    public init(
        snapshot: ProviderSetupSnapshot,
        apiKey: Binding<String>,
        pendingModelID: Binding<String?>,
        onSelectProvider: @escaping (ProviderID) -> Void,
        onValidate: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSelectModel: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        _apiKey = apiKey
        _pendingModelID = pendingModelID
        self.onSelectProvider = onSelectProvider
        self.onValidate = onValidate
        self.onRefresh = onRefresh
        self.onSelectModel = onSelectModel
        self.onCancel = onCancel
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                providerSidebar.disabled(snapshot.isReadOnly)
                Divider()
                detailPane.disabled(snapshot.isReadOnly)
            }
            Divider()
            footer
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
        .onChange(of: snapshot.phase) { _, phase in
            if phase == .selectingModel || phase == .ready {
                apiKey = ""
            }
        }
        .frame(minWidth: 720, idealWidth: 820, minHeight: 590)
        .permitsApplicationTerminationWhilePresented()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(VLMSnapperStrings.providerSetupTitle).font(.title2.bold())
                Text(VLMSnapperStrings.providerSetupSubtitle)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            Spacer()
            Button(action: onCancel) {
                VLMSnapperIcon.close.image
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VLMSnapperStrings.close)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var providerSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VLMSnapperStrings.providerSection)
                .font(.caption.bold())
                .foregroundStyle(VLMSnapperTheme.secondaryText)
                .accessibilityHidden(true)
            ForEach(providerDisplayOrder, id: \.self) { provider in
                Button {
                    onSelectProvider(provider)
                } label: {
                    HStack(spacing: 12) {
                        VLMSnapperIcon.provider.image
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VLMSnapperTheme.accent)
                            .frame(
                                width: VLMSnapperUIConstants.providerMarkSize,
                                height: VLMSnapperUIConstants.providerMarkSize
                            )
                            .background(VLMSnapperTheme.subtleSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(VLMSnapperStrings.providerName(provider))
                            .font(.headline)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 50)
                    .background(
                        provider == snapshot.selectedProvider
                            ? VLMSnapperTheme.accent.opacity(0.12)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 240)
        .background(VLMSnapperTheme.subtleSurface)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(VLMSnapperStrings.providerName(snapshot.selectedProvider))
                        .font(.title2.bold())
                    Text(VLMSnapperStrings.officialEndpoint)
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
                Spacer()
                statusBadge
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(VLMSnapperStrings.apiKey).font(.headline)
                HStack(spacing: 10) {
                    SecureField(VLMSnapperStrings.apiKey, text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button(VLMSnapperStrings.validate, action: onValidate)
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty || snapshot.phase == .validating)
                }
            }
            if !snapshot.availableModelIDs.isEmpty {
                modelSelection
            }
            if let failure = snapshot.failure {
                Label(failureText(failure), systemImage: VLMSnapperIcon.warning.rawValue)
                    .foregroundStyle(VLMSnapperTheme.destructive)
            }
            if snapshot.isReadOnly {
                Label(
                    VLMSnapperStrings.providerReadOnly,
                    systemImage: VLMSnapperIcon.info.rawValue
                )
                .foregroundStyle(VLMSnapperTheme.secondaryText)
            }
            Label(
                VLMSnapperStrings.visionValidationHint,
                systemImage: VLMSnapperIcon.info.rawValue
            )
                .font(.callout)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VLMSnapperTheme.subtleSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var modelSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VLMSnapperStrings.currentModel).font(.headline)
            HStack(spacing: 10) {
                Picker(VLMSnapperStrings.currentModel, selection: $pendingModelID) {
                    Text(VLMSnapperStrings.chooseModel).tag(String?.none)
                    ForEach(snapshot.availableModelIDs, id: \.self) { modelID in
                        Text(modelID).tag(Optional(modelID))
                    }
                }
                .labelsHidden()
                .onChange(of: pendingModelID) { _, value in
                    if let value { onSelectModel(value) }
                }
                Button(VLMSnapperStrings.refresh, action: onRefresh)
            }
            Text(VLMSnapperStrings.modelListHint)
                .font(.callout)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(VLMSnapperStrings.cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(VLMSnapperStrings.done, action: onDone)
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.canFinish)
        }
        .padding(18)
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.callout.bold())
            .foregroundStyle(snapshot.canFinish ? VLMSnapperTheme.success : VLMSnapperTheme.warning)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (snapshot.canFinish ? VLMSnapperTheme.success : VLMSnapperTheme.warning)
                    .opacity(0.12)
            )
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch snapshot.phase {
        case .awaitingValidation: VLMSnapperStrings.notConfigured
        case .validating: VLMSnapperStrings.validating
        case .selectingModel: VLMSnapperStrings.modelPending
        case .ready: VLMSnapperStrings.configured
        case .failed: VLMSnapperStrings.failed
        }
    }

    private var providerDisplayOrder: [ProviderID] {
        [.deepSeek, .openAI, .gemini]
    }

    private func failureText(_ failure: ProviderSetupFailure) -> String {
        switch failure {
        case .configurationLocked: VLMSnapperStrings.failed
        case .invalidConfiguration: VLMSnapperStrings.failureMessage(code: "invalid_credential")
        case .unavailable: VLMSnapperStrings.failureMessage(code: "provider_unavailable")
        }
    }
}
