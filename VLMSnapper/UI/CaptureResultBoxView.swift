import AppKit
import SwiftUI
import VLMSnapperCore

public enum CaptureResultBoxText: Equatable, Sendable {
    case extraction(markdown: String)
    case translation(text: String, segments: [TranslationSegment]?)
}

/// What the result box shows for one operation's slot (v1-core::REQ-010).
public struct CaptureResultBoxPresentation: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case message(String)
        case failure(String)
        case canceled(String)
        case text(CaptureResultBoxText)
    }

    public let title: String
    public let providerSummary: String
    public let showsProgress: Bool
    public let followsNewText: Bool
    public let body: Body
    public let copyText: String
    public let canRetry: Bool
    public let saveNotice: String?

    public var canCopy: Bool { !copyText.isEmpty }

    public init(
        operation: WorkspaceOperationKind,
        targetLanguageName: String,
        providerSummary: String,
        slot: WorkspaceOperationSlot
    ) {
        title = operation == .extract
            ? VLMSnapperStrings.captureExtract
            : "\(VLMSnapperStrings.translate) · \(targetLanguageName)"
        self.providerSummary = providerSummary

        func text(_ result: WorkspaceCommittedResult?) -> (CaptureResultBoxText, String) {
            Self.text(
                operation,
                source: result?.sourceMarkdown ?? "",
                translation: result?.translationMarkdown ?? "",
                segments: result?.segments
            )
        }
        let hasNoText = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        switch slot.attempt {
        case .neverStarted, .preparing:
            showsProgress = true
            followsNewText = false
            body = .message(VLMSnapperStrings.preparing)
            copyText = ""
            canRetry = false
            saveNotice = nil
        case .streaming:
            let (value, copy) = Self.text(
                operation,
                source: slot.sourceDelta,
                translation: slot.translationDelta,
                segments: slot.segments
            )
            showsProgress = true
            followsNewText = true
            body = hasNoText(copy) ? .message(VLMSnapperStrings.preparing) : .text(value)
            copyText = hasNoText(copy) ? "" : copy
            canRetry = false
            saveNotice = nil
        case .succeeded:
            let (value, copy) = text(slot.committedResult)
            showsProgress = false
            followsNewText = false
            body = hasNoText(copy) ? .message(VLMSnapperStrings.resultNoText) : .text(value)
            copyText = hasNoText(copy) ? "" : copy
            canRetry = true
            saveNotice = nil
        case let .failed(code):
            showsProgress = false
            followsNewText = false
            body = .failure(VLMSnapperStrings.failureMessage(code: code))
            copyText = ""
            canRetry = true
            saveNotice = nil
        case .canceled:
            showsProgress = false
            followsNewText = false
            body = .canceled(VLMSnapperStrings.canceled)
            copyText = ""
            canRetry = true
            saveNotice = nil
        case .resultPersistenceFailed:
            let (value, copy) = text(slot.unsavedResult)
            showsProgress = false
            followsNewText = false
            body = .text(value)
            copyText = copy
            canRetry = false
            saveNotice = slot.persistenceFailureCode.map(VLMSnapperStrings.failureMessage(code:))
                ?? VLMSnapperStrings.persistenceFailed
        }
    }

    private static func text(
        _ operation: WorkspaceOperationKind,
        source: String,
        translation: String,
        segments: [TranslationSegment]?
    ) -> (CaptureResultBoxText, String) {
        switch operation {
        case .extract: (.extraction(markdown: source), source)
        case .translate: (.translation(text: translation, segments: segments), translation)
        }
    }
}

@MainActor
public final class CaptureResultBoxState: ObservableObject {
    @Published public var presentation: CaptureResultBoxPresentation?

    public init() {}
}

public struct CaptureResultBoxActions {
    public let onCopy: @MainActor (String) -> Void
    public let onRetry: @MainActor () -> Void
    public let onRetrySave: @MainActor () -> Void
    public let onClose: @MainActor () -> Void

    public init(
        onCopy: @escaping @MainActor (String) -> Void,
        onRetry: @escaping @MainActor () -> Void,
        onRetrySave: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.onCopy = onCopy
        self.onRetry = onRetry
        self.onRetrySave = onRetrySave
        self.onClose = onClose
    }
}

public struct CaptureResultBoxView: View {
    @ObservedObject private var state: CaptureResultBoxState
    private let actions: CaptureResultBoxActions
    private let onMove: @MainActor (CGPoint) -> Void
    @State private var copiedCount = 0
    @State private var showsCopied = false

    public init(
        state: CaptureResultBoxState,
        actions: CaptureResultBoxActions,
        onMove: @escaping @MainActor (CGPoint) -> Void = { _ in }
    ) {
        self.state = state
        self.actions = actions
        self.onMove = onMove
    }

    /// What the box is showing.
    public var presentation: CaptureResultBoxPresentation? { state.presentation }

    public var body: some View {
        Group {
            if let presentation = state.presentation {
                content(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VLMSnapperTheme.window)
        .clipShape(boxShape)
        .overlay { boxShape.stroke(VLMSnapperTheme.border, lineWidth: 1) }
    }

    private var boxShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CaptureResultBoxMetrics.cornerRadius, style: .continuous)
    }

    private func content(_ presentation: CaptureResultBoxPresentation) -> some View {
        VStack(spacing: 0) {
            header(presentation)
            Divider()
            resultBody(presentation)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let notice = presentation.saveNotice {
                Divider()
                HStack(spacing: 10) {
                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    bodyButton(VLMSnapperStrings.retrySave) { actions.onRetrySave() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func header(_ presentation: CaptureResultBoxPresentation) -> some View {
        HStack(spacing: 8) {
            Text(presentation.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                if presentation.showsProgress {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }
                Text(presentation.providerSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(VLMSnapperTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if showsCopied {
                    Text(VLMSnapperStrings.copied)
                        .font(.system(size: 11))
                        .foregroundStyle(VLMSnapperTheme.secondaryText)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            HStack(spacing: VLMSnapperUIConstants.toolbarControlGap) {
                iconButton(VLMSnapperStrings.copy, icon: .copy, enabled: presentation.canCopy) {
                    actions.onCopy(presentation.copyText)
                    copiedCount += 1
                    showsCopied = true
                }
                iconButton(VLMSnapperStrings.retry, icon: .retry, enabled: presentation.canRetry) { actions.onRetry() }
                iconButton(VLMSnapperStrings.close, icon: .close, enabled: true) { actions.onClose() }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: CaptureResultBoxMetrics.headerHeight)
        .background(ResultBoxDragArea(toolTip: presentation.providerSummary, onMove: onMove))
        .task(id: copiedCount) {
            guard showsCopied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { showsCopied = false }
        }
    }

    @ViewBuilder
    private func resultBody(_ presentation: CaptureResultBoxPresentation) -> some View {
        switch presentation.body {
        case let .message(message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(VLMSnapperTheme.secondaryText)
                .padding(.horizontal, CaptureResultBoxMetrics.bodyHorizontalInset)
                .padding(.vertical, CaptureResultBoxMetrics.bodyVerticalInset)
        case let .failure(reason):
            retryBody(reason, color: VLMSnapperTheme.destructive)
        case let .canceled(message):
            retryBody(message, color: VLMSnapperTheme.secondaryText)
        case let .text(text):
            ResultBoxTextBody(text: text, followsNewText: presentation.followsNewText, onCopy: actions.onCopy)
                // Another operation or language is another document: it starts at its top.
                .id(presentation.title)
        }
    }

    private func retryBody(_ message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            bodyButton(VLMSnapperStrings.retry) { actions.onRetry() }
        }
        .padding(.horizontal, CaptureResultBoxMetrics.bodyHorizontalInset)
        .padding(.vertical, CaptureResultBoxMetrics.bodyVerticalInset)
    }

    private func bodyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VLMSnapperTheme.primaryText)
                .padding(.horizontal, 9)
                .frame(height: VLMSnapperUIConstants.toolbarControlHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: VLMSnapperUIConstants.compactCornerRadius, style: .continuous)
                        .stroke(VLMSnapperTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(CaptureToolbarButtonStyle(kind: .field))
    }

    private func iconButton(
        _ label: String,
        icon: VLMSnapperIcon,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon.image
                .frame(width: 13, height: 13)
                .frame(
                    width: VLMSnapperUIConstants.toolbarControlHeight,
                    height: VLMSnapperUIConstants.toolbarControlHeight
                )
                .foregroundStyle(enabled ? VLMSnapperTheme.primaryText : VLMSnapperTheme.tertiaryText)
        }
        .buttonStyle(CaptureToolbarButtonStyle(kind: .icon))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The header's empty space drags the box. It also carries the Provider and model tooltip, because text
/// above it does not take the pointer.
private struct ResultBoxDragArea: NSViewRepresentable {
    let toolTip: String
    let onMove: @MainActor (CGPoint) -> Void

    func makeNSView(context: Context) -> ResultBoxDragView { ResultBoxDragView() }

    func updateNSView(_ view: ResultBoxDragView, context: Context) {
        view.toolTip = toolTip
        view.onMove = onMove
    }
}

final class ResultBoxDragView: NSView {
    var onMove: (@MainActor (CGPoint) -> Void)?
    private var dragStart: (origin: CGPoint, pointer: CGPoint)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKey()
        dragStart = (window.frame.origin, window.convertPoint(toScreen: event.locationInWindow))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        onMove?(CGPoint(
            x: dragStart.origin.x + pointer.x - dragStart.pointer.x,
            y: dragStart.origin.y + pointer.y - dragStart.pointer.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }
}

private struct ResultBoxTextBody: NSViewRepresentable {
    let text: CaptureResultBoxText
    let followsNewText: Bool
    let onCopy: @MainActor (String) -> Void

    func makeNSView(context: Context) -> ResultBoxScrollView { ResultBoxScrollView() }

    func updateNSView(_ view: ResultBoxScrollView, context: Context) {
        view.textView.onCopySelection = onCopy
        view.update(text, followsNewText: followsNewText)
    }
}

/// One native text view, so a selection can run across paragraphs (v1-core::REQ-010/AC-07).
@MainActor
final class ResultBoxScrollView: NSScrollView {
    let textView = ResultBoxTextView()
    private var currentText: CaptureResultBoxText?
    private var hasFollowed = false

    init() {
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        horizontalScrollElasticity = .none
        documentView = textView
    }

    required init?(coder: NSCoder) { nil }

    /// Read in the text's own coordinates: the text view's origin does not stay at zero (measured at -42).
    private var isAtEnd: Bool {
        textView.visibleRect.maxY >= textView.bounds.height - 4
    }

    /// The position decides following at the moment text arrives: scroll events come later, and one
    /// that has not arrived yet would let the new text pull a reader back down (v1-core::REQ-010/AC-06).
    func update(_ text: CaptureResultBoxText, followsNewText: Bool) {
        guard text != currentText else { return }
        let wasAtEnd = isAtEnd
        let origin = contentView.bounds.origin
        let selection = textView.selectedRange()
        let previous = textView.string
        let attributed = ResultBoxDocument.attributedString(for: text)
        textView.textStorage?.setAttributedString(attributed)
        let keepsSelection = attributed.string.utf16.starts(with: previous.utf16)
            && NSMaxRange(selection) <= attributed.length
        textView.setSelectedRange(keepsSelection ? selection : NSRange(location: 0, length: 0))
        currentText = text
        textView.layoutManager?.ensureLayout(for: textView.textContainer ?? NSTextContainer())
        textView.sizeToFit()
        if wasAtEnd, followsNewText || hasFollowed {
            hasFollowed = true
            textView.scrollToEndOfDocument(nil)
        } else {
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
        }
    }
}

@MainActor
final class ResultBoxTextView: NSTextView {
    /// Receives the selected text for the clipboard.
    var onCopySelection: (@MainActor (String) -> Void)?

    init() {
        let container = NSTextContainer(containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        let manager = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(
            width: CaptureResultBoxMetrics.bodyHorizontalInset,
            height: CaptureResultBoxMetrics.bodyVerticalInset
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        allowsUndo = false
    }

    required init?(coder: NSCoder) { nil }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any?) {
        guard let onCopySelection else { return super.copy(sender) }
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        onCopySelection((string as NSString).substring(with: selection))
    }

    /// Handled here as well as by the Edit menu: the capture screen does not activate the application,
    /// so the menu bar is not certain to see the keys.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c":
            copy(nil)
            return true
        case "a":
            window?.makeFirstResponder(self)
            selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.cancelOperation(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        window?.cancelOperation(sender)
    }

    /// Only Copy and Select All: the system's other items open apps hidden behind the capture overlay
    /// (v1-core::REQ-010/AC-11).
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.allowsContextMenuPlugIns = false
        let copyItem = NSMenuItem(title: VLMSnapperStrings.copy, action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let selectAllItem = NSMenuItem(title: VLMSnapperStrings.selectAll, action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)
        return menu
    }
}

/// Lays a result out as read-only text. Model output is never interpreted beyond these line styles: HTML,
/// links and media stay plain characters (v1-core::US-002/AC-10).
@MainActor
enum ResultBoxDocument {
    private enum LineStyle {
        case body, heading(CGFloat), list, monospaced
    }

    static func attributedString(for text: CaptureResultBoxText) -> NSAttributedString {
        switch text {
        case let .extraction(markdown):
            extraction(markdown)
        case let .translation(value, segments):
            AlignedTextDocument(segments: segments, translated: true, fallback: value).text
        }
    }

    private static func extraction(_ markdown: String) -> NSAttributedString {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let output = NSMutableAttributedString()
        var insideFence = false
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty, !insideFence { continue }
            let (value, style) = styled(line, trimmed: trimmed, insideFence: &insideFence)
            if output.length > 0 {
                output.append(NSAttributedString(string: "\n", attributes: attributes(style, endsBlock: false)))
            }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let endsBlock = next.trimmingCharacters(in: .whitespaces).isEmpty
            output.append(NSAttributedString(string: value, attributes: attributes(style, endsBlock: endsBlock)))
        }
        return output
    }

    private static func styled(_ line: String, trimmed: String, insideFence: inout Bool) -> (String, LineStyle) {
        if trimmed.hasPrefix("```") {
            insideFence.toggle()
            return (line, .monospaced)
        }
        if insideFence || trimmed.hasPrefix("|") { return (line, .monospaced) }
        let hashes = trimmed.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
            let title = String(trimmed.dropFirst(hashes + 1))
            return (title, .heading(hashes <= 2 ? 16 : 14))
        }
        if trimmed.range(of: #"^([-*•·]|\d+[.)])\s"#, options: .regularExpression) != nil {
            return (line, .list)
        }
        return (line, .body)
    }

    private static func attributes(_ style: LineStyle, endsBlock: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.baseWritingDirection = .natural
        paragraph.lineBreakMode = .byWordWrapping
        let font: NSFont
        switch style {
        case .body:
            font = .systemFont(ofSize: 13)
            paragraph.paragraphSpacing = endsBlock ? 10 : 0
        case let .heading(size):
            font = .systemFont(ofSize: size, weight: .semibold)
            paragraph.paragraphSpacing = 10
        case .list:
            font = .systemFont(ofSize: 13)
            paragraph.headIndent = 14
            paragraph.paragraphSpacing = endsBlock ? 10 : 3
        case .monospaced:
            font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            paragraph.paragraphSpacing = endsBlock ? 10 : 0
        }
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }
}
