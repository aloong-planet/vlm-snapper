import SwiftUI
import VLMSnapperCore

public struct TargetLanguageOption: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct CaptureOperationToolbar: View {
    @Binding private var operation: WorkspaceOperationKind
    @Binding private var targetLanguageCode: String
    private let targetLanguages: [TargetLanguageOption]
    private let providerSummary: String
    private let onStart: (WorkspaceOperationKind) -> Void
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onCancel: () -> Void

    public init(
        operation: Binding<WorkspaceOperationKind>,
        targetLanguageCode: Binding<String>,
        targetLanguages: [TargetLanguageOption],
        providerSummary: String,
        onStart: @escaping (WorkspaceOperationKind) -> Void,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _operation = operation
        _targetLanguageCode = targetLanguageCode
        self.targetLanguages = targetLanguages
        self.providerSummary = providerSummary
        self.onStart = onStart
        self.onCopy = onCopy
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: VLMSnapperUIConstants.toolbarControlGap) {
            operationButton(.extract, icon: .extract, title: VLMSnapperStrings.extract)
            operationButton(.translate, icon: .translate, title: VLMSnapperStrings.translate)
            TargetLanguagePicker(
                selection: $targetLanguageCode,
                options: targetLanguages
            )
            valueLabel(icon: .provider, text: providerSummary)
            Divider().frame(height: 19)
            iconButton(VLMSnapperStrings.copyImage, action: onCopy) {
                VLMSnapperIcon.copy.image
            }
            iconButton(VLMSnapperStrings.saveImage, action: onSave) {
                FloppyDiskIcon()
            }
            iconButton(VLMSnapperStrings.cancel, action: onCancel) {
                VLMSnapperIcon.close.image
            }
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

    private func iconButton<Icon: View>(
        _ label: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 13, height: 13)
                .frame(
                    width: VLMSnapperUIConstants.toolbarControlHeight,
                    height: VLMSnapperUIConstants.toolbarControlHeight
                )
        }
        // The style makes the whole box take the press, not only the icon's drawn pixels: the floppy
        // disk is a thin outline that a press would mostly miss.
        .buttonStyle(CaptureToolbarButtonStyle(kind: .icon))
        .help(label)
        .accessibilityLabel(label)
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
        }
        // The style also gives an unselected button, whose background is clear, its whole shape to press.
        .buttonStyle(CaptureToolbarButtonStyle(kind: .action(isSelected: operation == kind)))
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

private struct TargetLanguagePicker: View {
    @Binding var selection: String
    let options: [TargetLanguageOption]
    @State private var isPresented = false
    @State private var searchText = ""

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                VLMSnapperIcon.language.image
                Text(selectedName).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VLMSnapperTheme.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
            .overlay {
                RoundedRectangle(
                    cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                    style: .continuous
                )
                .stroke(VLMSnapperTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(CaptureToolbarButtonStyle(kind: .field))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField(VLMSnapperStrings.targetLanguageSearch, text: $searchText)
                    .textFieldStyle(.roundedBorder)
                List(filteredOptions) { option in
                    Button {
                        selection = option.code
                        isPresented = false
                    } label: {
                        HStack {
                            Text(option.name)
                            Spacer()
                            Text(option.code)
                                .foregroundStyle(VLMSnapperTheme.secondaryText)
                            if selection == option.code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(VLMSnapperTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(10)
            .frame(width: 310, height: 360)
        }
    }

    private var selectedName: String {
        options.first { $0.code == selection }?.name ?? selection
    }

    private var filteredOptions: [TargetLanguageOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.code.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
        }
    }
}
