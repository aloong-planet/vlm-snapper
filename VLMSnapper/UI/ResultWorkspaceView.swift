import AppKit
import SwiftUI
import VLMSnapperCore

public struct ResultWorkspaceView: View {
    @Binding private var operation: WorkspaceOperationKind
    private let snapshot: OperationWorkspaceSnapshot
    private let originalImage: NSImage?
    private let providerSummary: String
    private let targetLanguage: String
    private let onStart: (WorkspaceOperationKind) -> Void
    private let onCopy: (String) -> Void
    private let onRetrySave: () -> Void

    public init(
        operation: Binding<WorkspaceOperationKind>,
        snapshot: OperationWorkspaceSnapshot,
        originalImage: NSImage?,
        providerSummary: String,
        targetLanguage: String,
        onStart: @escaping (WorkspaceOperationKind) -> Void,
        onCopy: @escaping (String) -> Void,
        onRetrySave: @escaping () -> Void
    ) {
        _operation = operation
        self.snapshot = snapshot
        self.originalImage = originalImage
        self.providerSummary = providerSummary
        self.targetLanguage = targetLanguage
        self.onStart = onStart
        self.onCopy = onCopy
        self.onRetrySave = onRetrySave
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                screenshotCard.frame(minWidth: 300, maxWidth: .infinity)
                resultCard.frame(minWidth: 430, maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(VLMSnapperTheme.window)
        .frame(minWidth: 820, minHeight: 520)
    }

    private var header: some View {
        ZStack {
            Picker(VLMSnapperStrings.operationSelector, selection: $operation) {
                Text(VLMSnapperStrings.extract).tag(WorkspaceOperationKind.extract)
                Text(VLMSnapperStrings.translate).tag(WorkspaceOperationKind.translate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(VLMSnapperStrings.operationSelector)
            .frame(width: 210)
            HStack {
                Spacer()
                Text(providerSummary)
                if operation == .translate {
                    Text(targetLanguage)
                }
            }
            .font(.caption)
            .foregroundStyle(VLMSnapperTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private var screenshotCard: some View {
        card {
            cardHeader(title: VLMSnapperStrings.originalScreenshot)
            Divider()
            Group {
                if let originalImage {
                    Image(nsImage: originalImage)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(VLMSnapperStrings.originalScreenshot)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VLMSnapperTheme.subtleSurface)
                        .overlay {
                            VLMSnapperIcon.extract.image
                                .font(.system(size: 34))
                                .foregroundStyle(VLMSnapperTheme.secondaryText)
                        }
                }
            }
            .padding(18)
        }
    }

    private var resultCard: some View {
        let slot = operation == .extract ? snapshot.extract : snapshot.translate
        return card {
            cardHeader(title: VLMSnapperStrings.result) {
                if let committed = slot.committedResult ?? slot.unsavedResult {
                    Button {
                        onCopy(displayedText(from: committed))
                    } label: {
                        Label(VLMSnapperStrings.copy, systemImage: VLMSnapperIcon.copy.rawValue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Divider()
            ScrollView {
                resultContent(slot)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)
            }
        }
    }

    @ViewBuilder
    private func resultContent(_ slot: WorkspaceOperationSlot) -> some View {
        switch slot.attempt {
        case .neverStarted:
            emptyState(VLMSnapperStrings.neverStarted, action: VLMSnapperStrings.start)
        case .preparing:
            progressState(VLMSnapperStrings.preparing)
        case .streaming:
            VStack(alignment: .leading, spacing: 14) {
                progressState(VLMSnapperStrings.streaming)
                markdown(slot.sourceDelta)
                if operation == .translate {
                    markdown(slot.translationDelta)
                }
            }
        case .succeeded:
            if let committed = slot.committedResult {
                VStack(alignment: .leading, spacing: 18) {
                    markdown(committed.sourceMarkdown)
                    if let translation = committed.translationMarkdown {
                        Divider()
                        markdown(translation)
                    }
                    Button(VLMSnapperStrings.rerun) { onStart(operation) }
                }
            }
        case let .failed(code):
            emptyState(
                VLMSnapperStrings.failureMessage(code: code),
                action: VLMSnapperStrings.rerun
            )
        case .canceled:
            emptyState(VLMSnapperStrings.canceled, action: VLMSnapperStrings.rerun)
        case .resultPersistenceFailed:
            VStack(alignment: .leading, spacing: 14) {
                if let unsaved = slot.unsavedResult {
                    markdown(displayedText(from: unsaved))
                }
                Text(VLMSnapperStrings.persistenceFailed)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                Button(VLMSnapperStrings.retrySave, action: onRetrySave)
            }
        }
    }

    private func markdown(_ value: String) -> some View {
        MarkdownResultView(markdown: value)
    }

    private func progressState(_ title: String) -> some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text(title).foregroundStyle(VLMSnapperTheme.secondaryText)
        }
    }

    private func emptyState(_ title: String, action: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).foregroundStyle(VLMSnapperTheme.secondaryText)
            Button(action) { onStart(operation) }
        }
    }

    private func card<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0, content: content)
            .background(VLMSnapperTheme.surface)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VLMSnapperUIConstants.cardCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VLMSnapperUIConstants.cardCornerRadius,
                    style: .continuous
                )
                .stroke(VLMSnapperTheme.border, lineWidth: 1)
            }
    }

    private func cardHeader<Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 45)
    }

    private func cardHeader(title: String) -> some View {
        cardHeader(title: title) { EmptyView() }
    }

    private func displayedText(from result: WorkspaceCommittedResult) -> String {
        [result.sourceMarkdown, result.translationMarkdown]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}
