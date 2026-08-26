import SwiftUI
import VLMSnapperCore

public struct CaptureOperationToolbar: View {
    @Binding private var operation: WorkspaceOperationKind
    private let targetLanguage: String
    private let providerSummary: String
    private let onStart: (WorkspaceOperationKind) -> Void
    private let onCancel: () -> Void

    public init(
        operation: Binding<WorkspaceOperationKind>,
        targetLanguage: String,
        providerSummary: String,
        onStart: @escaping (WorkspaceOperationKind) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _operation = operation
        self.targetLanguage = targetLanguage
        self.providerSummary = providerSummary
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: VLMSnapperUIConstants.toolbarControlGap) {
            operationButton(.extract, icon: .extract, title: VLMSnapperStrings.extract)
            operationButton(.translate, icon: .translate, title: VLMSnapperStrings.translate)
            valueLabel(icon: .language, text: targetLanguage)
            valueLabel(icon: .provider, text: providerSummary)
            Divider().frame(height: 19)
            Button(action: onCancel) {
                VLMSnapperIcon.close.image
                    .frame(width: 13, height: 13)
                    .frame(
                        width: VLMSnapperUIConstants.toolbarControlHeight,
                        height: VLMSnapperUIConstants.toolbarControlHeight
                    )
            }
            .buttonStyle(.plain)
            .help(VLMSnapperStrings.cancel)
            .accessibilityLabel(VLMSnapperStrings.cancel)
        }
        .padding(VLMSnapperUIConstants.toolbarPadding)
        .background(.regularMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                style: .continuous
            )
            .stroke(VLMSnapperTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .fixedSize()
    }

    private func operationButton(
        _ kind: WorkspaceOperationKind,
        icon: VLMSnapperIcon,
        title: String
    ) -> some View {
        Button {
            operation = kind
            onStart(kind)
        } label: {
            Label(title, systemImage: icon.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
                .foregroundStyle(operation == kind ? Color.white : VLMSnapperTheme.primaryText)
                .background(operation == kind ? VLMSnapperTheme.accent : Color.clear)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func valueLabel(icon: VLMSnapperIcon, text: String) -> some View {
        Label(text, systemImage: icon.rawValue)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VLMSnapperTheme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
            .background(VLMSnapperTheme.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                    style: .continuous
                )
                .stroke(VLMSnapperTheme.border, lineWidth: 1)
            }
    }
}
