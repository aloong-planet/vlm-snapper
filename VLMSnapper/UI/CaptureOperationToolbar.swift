import SwiftUI
import VLMSnapperCore

public struct TargetLanguageOption: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    /// What the toolbar and the language list show first (v1-core::REQ-013/AC-03).
    public var abbreviation: String { TargetLanguageCatalog.abbreviation(for: code) }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    /// The list's search matches the abbreviation or the name (v1-core::REQ-013/AC-04).
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return abbreviation.lowercased().contains(query) || name.lowercased().contains(query)
    }
}

/// What the toolbar shows as operations run, updated in place so an open language list stays open.
@MainActor
public final class CaptureToolbarState: ObservableObject {
    @Published public var targetLanguageCode: String
    /// The operation whose result box is showing.
    @Published public var currentOperation: WorkspaceOperationKind?
    @Published public var isRequestRunning = false
    /// Operations that cannot start now, while a result is unsaved (v1-core::REQ-011/AC-07).
    @Published public var unavailableOperations: Set<WorkspaceOperationKind> = []

    public init(targetLanguageCode: String) {
        self.targetLanguageCode = targetLanguageCode
    }

    func isBlocked(_ operation: WorkspaceOperationKind) -> Bool {
        (isRequestRunning && currentOperation != operation) || unavailableOperations.contains(operation)
    }
}

public struct CaptureOperationToolbar: View {
    @ObservedObject private var state: CaptureToolbarState
    private let targetLanguages: [TargetLanguageOption]
    private let onStart: (WorkspaceOperationKind) -> Void
    private let onTargetLanguageChange: (String) -> Void
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onCancel: () -> Void

    public init(
        state: CaptureToolbarState,
        targetLanguages: [TargetLanguageOption],
        onStart: @escaping (WorkspaceOperationKind) -> Void,
        onTargetLanguageChange: @escaping (String) -> Void,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.targetLanguages = targetLanguages
        self.onStart = onStart
        self.onTargetLanguageChange = onTargetLanguageChange
        self.onCopy = onCopy
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: VLMSnapperUIConstants.toolbarControlGap) {
            extractButton
            TranslateControl(
                state: state,
                options: targetLanguages,
                onStart: { onStart(.translate) },
                onTargetLanguageChange: onTargetLanguageChange
            )
            Divider().frame(height: 19)
            iconButton(VLMSnapperStrings.copyImage, enabled: !state.isRequestRunning, action: onCopy) {
                VLMSnapperIcon.copy.image
            }
            iconButton(VLMSnapperStrings.saveImage, enabled: !state.isRequestRunning, action: onSave) {
                FloppyDiskIcon()
            }
            iconButton(VLMSnapperStrings.cancel, enabled: true, action: onCancel) {
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
        enabled: Bool,
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
                .foregroundStyle(enabled ? VLMSnapperTheme.primaryText : VLMSnapperTheme.tertiaryText)
        }
        // The style makes the whole box take the press, not only the icon's drawn pixels: the floppy
        // disk is a thin outline that a press would mostly miss.
        .buttonStyle(CaptureToolbarButtonStyle(kind: .icon))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private var extractButton: some View {
        let isCurrent = state.currentOperation == .extract
        let isBlocked = state.isBlocked(.extract)
        return Button {
            onStart(.extract)
        } label: {
            Label(VLMSnapperStrings.captureExtract, systemImage: VLMSnapperIcon.extract.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
                .foregroundStyle(
                    isBlocked ? VLMSnapperTheme.tertiaryText : isCurrent ? VLMSnapperTheme.accent : VLMSnapperTheme.primaryText
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: VLMSnapperUIConstants.compactCornerRadius,
                        style: .continuous
                    )
                    .stroke(isCurrent ? VLMSnapperTheme.accent : VLMSnapperTheme.border, lineWidth: 1)
                }
        }
        // Both actions look alike until the user picks one.
        .buttonStyle(CaptureToolbarButtonStyle(kind: .field, isCurrent: isCurrent))
        .disabled(isBlocked)
    }
}

/// Translate and its target language as one control (v1-core::REQ-013/AC-02).
private struct TranslateControl: View {
    @ObservedObject var state: CaptureToolbarState
    let options: [TargetLanguageOption]
    let onStart: () -> Void
    let onTargetLanguageChange: (String) -> Void
    @State private var isPresented = false
    @State private var searchText = ""

    private var isCurrent: Bool { state.currentOperation == .translate }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VLMSnapperUIConstants.compactCornerRadius, style: .continuous)
    }

    private var lineColor: Color {
        isCurrent ? VLMSnapperTheme.accent : VLMSnapperTheme.border
    }

    var body: some View {
        HStack(spacing: 0) {
            translateButton
            Rectangle()
                .fill(lineColor)
                .frame(width: 1)
            languageButton
        }
        .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
        .background(VLMSnapperTheme.surface)
        .clipShape(shape)
        .overlay { shape.stroke(lineColor, lineWidth: 1) }
    }

    private var translateButton: some View {
        let isBlocked = state.isBlocked(.translate)
        return Button(action: onStart) {
            Label(VLMSnapperStrings.translate, systemImage: VLMSnapperIcon.translate.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity)
                .foregroundStyle(
                    isBlocked ? VLMSnapperTheme.tertiaryText : isCurrent ? VLMSnapperTheme.accent : VLMSnapperTheme.primaryText
                )
        }
        .buttonStyle(CaptureToolbarButtonStyle(kind: .part, isCurrent: isCurrent))
        .disabled(isBlocked)
    }

    private var languageButton: some View {
        Button {
            searchText = ""
            isPresented.toggle()
        } label: {
            HStack(spacing: 2) {
                Text(TargetLanguageCatalog.abbreviation(for: state.targetLanguageCode))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .frame(maxHeight: .infinity)
            .foregroundStyle(isCurrent ? VLMSnapperTheme.accent : VLMSnapperTheme.secondaryText)
        }
        .buttonStyle(CaptureToolbarButtonStyle(kind: .part, isCurrent: isCurrent))
        .help(selectedLanguageHint)
        .accessibilityLabel(selectedLanguageHint)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField(VLMSnapperStrings.targetLanguageSearch, text: $searchText)
                    .textFieldStyle(.roundedBorder)
                List(options.filter { $0.matches(searchText) }) { option in
                    Button {
                        state.targetLanguageCode = option.code
                        onTargetLanguageChange(option.code)
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.abbreviation)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 30, alignment: .leading)
                            Text(option.name)
                                .foregroundStyle(VLMSnapperTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            if state.targetLanguageCode == option.code {
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
            .frame(width: 260, height: 340)
        }
    }

    private var selectedLanguageHint: String {
        let name = options.first { $0.code == state.targetLanguageCode }?.name ?? state.targetLanguageCode
        return VLMSnapperStrings.targetLanguageHint(name)
    }
}
