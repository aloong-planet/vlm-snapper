import AppKit
import SwiftUI
import VLMSnapperCore

public struct ResultWorkspaceView: View {
    @Binding private var operation: WorkspaceOperationKind
    private let snapshot: OperationWorkspaceSnapshot
    private let originalImage: NSImage?
    private let providerSummary: String
    private let targetLanguage: String
    private let allowsOperationStart: Bool
    private let onStart: (WorkspaceOperationKind) -> Void
    private let onCopy: (String) -> Void
    private let onRetrySave: () -> Void

    public init(
        operation: Binding<WorkspaceOperationKind>,
        snapshot: OperationWorkspaceSnapshot,
        originalImage: NSImage?,
        providerSummary: String,
        targetLanguage: String,
        allowsOperationStart: Bool = true,
        onStart: @escaping (WorkspaceOperationKind) -> Void,
        onCopy: @escaping (String) -> Void,
        onRetrySave: @escaping () -> Void
    ) {
        _operation = operation
        self.snapshot = snapshot
        self.originalImage = originalImage
        self.providerSummary = providerSummary
        self.targetLanguage = targetLanguage
        self.allowsOperationStart = allowsOperationStart
        self.onStart = onStart
        self.onCopy = onCopy
        self.onRetrySave = onRetrySave
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 16) {
                screenshotCard.frame(minWidth: 360, maxWidth: .infinity)
                resultCard.frame(minWidth: 500, maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .background(VLMSnapperTheme.window)
        .frame(
            minWidth: ResultWorkspaceMetrics.minimumSize.width,
            minHeight: ResultWorkspaceMetrics.minimumSize.height
        )
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
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(VLMSnapperTheme.subtleSurface, in: Capsule())
                if operation == .translate {
                    Text(targetLanguage)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(VLMSnapperTheme.subtleSurface, in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(VLMSnapperTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: ResultWorkspaceMetrics.headerHeight)
    }

    private var screenshotCard: some View {
        card {
            cardHeader(title: VLMSnapperStrings.originalScreenshot) {
                if let originalImage {
                    Text(
                        "\(Int(originalImage.size.width)) × \(Int(originalImage.size.height))"
                    )
                    .font(.caption)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                }
            }
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
            cardHeader(title: VLMSnapperStrings.result)
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
                resultBody(source: slot.sourceDelta, translation: slot.translationDelta, segments: slot.segments)
            }
        case .succeeded:
            if let committed = slot.committedResult {
                VStack(alignment: .leading, spacing: 18) {
                    resultBody(source: committed.sourceMarkdown, translation: committed.translationMarkdown, segments: committed.segments)
                    Button(VLMSnapperStrings.rerun) { onStart(operation) }
                        .disabled(!allowsOperationStart)
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
                    resultBody(source: unsaved.sourceMarkdown, translation: unsaved.translationMarkdown, segments: unsaved.segments)
                }
                Text(slot.persistenceFailureCode.map(VLMSnapperStrings.failureMessage(code:))
                     ?? VLMSnapperStrings.persistenceFailed)
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                Button(VLMSnapperStrings.retrySave, action: onRetrySave)
                    .disabled(!allowsOperationStart)
            }
        }
    }

    @ViewBuilder
    private func resultBody(source: String, translation: String?, segments: [TranslationSegment]?) -> some View {
        if operation == .translate {
            BilingualResultView(source: source, translation: translation ?? "", segments: segments, onCopy: onCopy)
                .padding(.horizontal, -22)
        } else {
            resultSection(VLMSnapperStrings.historyOriginal, text: source)
        }
    }

    private func markdown(_ value: String) -> some View {
        MarkdownResultView(markdown: value)
    }

    private func resultSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                Spacer()
                ResultCopyButton(text: text, onCopy: onCopy)
            }
            markdown(text)
        }
    }

    private var footer: some View {
        let slot = operation == .extract ? snapshot.extract : snapshot.translate
        return HStack(spacing: 8) {
            Circle()
                .fill(statusColor(for: slot.attempt))
                .frame(width: 7, height: 7)
            Text(statusText(for: slot.attempt))
                .font(.caption)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
            Spacer()
            Text(providerSummary)
                .font(.caption)
                .foregroundStyle(VLMSnapperTheme.secondaryText)
        }
        .padding(.horizontal, 18)
        .frame(height: ResultWorkspaceMetrics.footerHeight)
    }

    private func statusText(for attempt: WorkspaceAttemptState) -> String {
        switch attempt {
        case .neverStarted: VLMSnapperStrings.neverStarted
        case .preparing: VLMSnapperStrings.preparing
        case .streaming: VLMSnapperStrings.streaming
        case .succeeded: VLMSnapperStrings.menuStatusSucceeded
        case let .failed(code): VLMSnapperStrings.failureMessage(code: code)
        case .canceled: VLMSnapperStrings.canceled
        case .resultPersistenceFailed: VLMSnapperStrings.persistenceFailed
        }
    }

    private func statusColor(for attempt: WorkspaceAttemptState) -> Color {
        switch attempt {
        case .succeeded: VLMSnapperTheme.success
        case .failed, .resultPersistenceFailed: VLMSnapperTheme.destructive
        case .canceled, .neverStarted: VLMSnapperTheme.secondaryText
        case .preparing, .streaming: VLMSnapperTheme.accent
        }
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
                .disabled(!allowsOperationStart)
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

}
