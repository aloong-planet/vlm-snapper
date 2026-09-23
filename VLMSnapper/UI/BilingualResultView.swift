import AppKit
import SwiftUI
import VLMSnapperCore

struct ResultCopyButton: View {
    let text: String
    let onCopy: (String) -> Void
    @State private var copied = false

    var body: some View {
        Button {
            onCopy(text)
            copied = true
        } label: {
            VLMSnapperIcon.copy.image.frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty)
        .help(VLMSnapperStrings.copy)
        .accessibilityLabel(VLMSnapperStrings.copy)
        .overlay(alignment: .trailing) {
            if copied {
                Text(VLMSnapperStrings.copied).font(.caption)
                    .fixedSize().padding(.trailing, 36).allowsHitTesting(false)
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { copied = false }
        }
    }
}

/// Both production entry points use this native surface. Independent text
/// containers keep selection/copy within one language; only IDs cross columns.
struct BilingualResultView: NSViewRepresentable {
    let source: String
    let translation: String
    let segments: [TranslationSegment]?
    var onCopy: (String) -> Void = {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString($0, forType: .string)
    }

    func makeNSView(context: Context) -> BilingualResultContentView {
        BilingualResultContentView()
    }

    func updateNSView(_ view: BilingualResultContentView, context: Context) {
        view.update(source: source, translation: translation, segments: segments, onCopy: onCopy)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BilingualResultContentView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 500
        let width = proposed.isFinite ? max(1, proposed) : 500
        return CGSize(width: width, height: nsView.height(for: width))
    }
}

@MainActor
final class BilingualResultContentView: NSView {
    private let sourceColumn = BilingualColumnView(translated: false)
    private let translationColumn = BilingualColumnView(translated: true)
    private let selection: BilingualSelectionCoordinator
    var sourceView: AlignedTextView { sourceColumn.textView }
    var translationView: AlignedTextView { translationColumn.textView }
    override var isFlipped: Bool { true }

    init() {
        selection = BilingualSelectionCoordinator(views: [sourceColumn.textView, translationColumn.textView])
        super.init(frame: .zero)
        for column in [sourceColumn, translationColumn] {
            column.onClearSelection = { [weak selection] in selection?.clear() }
            addSubview(column)
        }
    }

    required init?(coder: NSCoder) { nil }

    func update(source: String, translation: String, segments: [TranslationSegment]?, onCopy: @escaping (String) -> Void) {
        var changed = false
        selection.updateContents {
            let sourceUpdate = sourceColumn.update(value: source, segments: segments, onCopy: onCopy)
            let translationUpdate = translationColumn.update(value: translation, segments: segments, onCopy: onCopy)
            changed = sourceUpdate.changed || translationUpdate.changed
            return sourceUpdate.resetsSelection || translationUpdate.resetsSelection
        }
        guard changed else { return }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func height(for width: CGFloat) -> CGFloat {
        let columnWidth = max(1, (width - 1) / 2)
        return max(sourceColumn.height(for: columnWidth), translationColumn.height(for: columnWidth))
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(for: max(100, bounds.width)))
    }

    override func layout() {
        super.layout()
        let half = max(1, (bounds.width - 1) / 2)
        sourceColumn.frame = NSRect(x: 0, y: 0, width: half, height: bounds.height)
        translationColumn.frame = NSRect(x: half + 1, y: 0, width: half, height: bounds.height)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(VLMSnapperTheme.border).setFill()
        NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        selection.clear()
    }
}

/// One language owns its text layout, header and copy action. Measurement uses
/// a separate TextKit stack, so a proposed size never mutates displayed glyphs.
@MainActor
private final class BilingualColumnView: NSView {
    let textView = AlignedTextView()
    var onClearSelection: (() -> Void)?
    private let translated: Bool
    private let title = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let feedback = NSTextField(labelWithString: "")
    private var feedbackTask: Task<Void, Never>?
    private var copyValue: String?
    private var lastSegments: [TranslationSegment]?
    private var onCopy: (String) -> Void = { _ in }
    override var isFlipped: Bool { true }

    init(translated: Bool) {
        self.translated = translated
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        textView.setAccessibilityIdentifier(translated ? "bilingual-translation" : "bilingual-source")
        copyButton.isBordered = false
        copyButton.image = NSImage(systemSymbolName: VLMSnapperIcon.copy.rawValue, accessibilityDescription: nil)
        copyButton.imagePosition = .imageOnly
        copyButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyColumn)
        copyButton.setAccessibilityIdentifier(translated ? "bilingual-copy-translation" : "bilingual-copy-source")
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor
        feedback.isHidden = true
        for view in [textView, title, copyButton, feedback] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    func update(value: String, segments: [TranslationSegment]?, onCopy: @escaping (String) -> Void) -> (changed: Bool, resetsSelection: Bool) {
        self.onCopy = onCopy
        title.stringValue = translated ? VLMSnapperStrings.historyTranslation : VLMSnapperStrings.historyOriginal
        textView.setAccessibilityLabel(title.stringValue)
        copyButton.toolTip = "\(VLMSnapperStrings.copy) · \(title.stringValue)"
        copyButton.setAccessibilityLabel(copyButton.toolTip)
        copyButton.isEnabled = !value.isEmpty
        guard copyValue != value || lastSegments != segments else { return (false, false) }
        copyValue = value
        lastSegments = segments
        let document = AlignedTextDocument(segments: segments, translated: translated, fallback: value)
        let canPreserve = document.text.string.utf16.starts(with: textView.string.utf16)
            && textView.segmentIDs.isSubset(of: Set(document.ranges.keys))
        let range = textView.selectedRange()
        textView.replaceText(document.text)
        textView.segmentRanges = document.ranges
        textView.setSelectedRange(canPreserve && NSMaxRange(range) <= textView.string.utf16.count
            ? range : NSRange(location: 0, length: 0))
        feedbackTask?.cancel()
        feedback.isHidden = true
        needsLayout = true
        return (true, !canPreserve)
    }

    func height(for width: CGFloat) -> CGFloat {
        46 + 12 + textView.contentHeight(for: max(1, width - 30)) + 8
    }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 15, y: 14, width: max(1, bounds.width - 75), height: 20)
        copyButton.frame = NSRect(x: bounds.width - 45, y: 8, width: 30, height: 30)
        feedback.stringValue = VLMSnapperStrings.copied
        feedback.sizeToFit()
        feedback.frame.origin = NSPoint(x: bounds.width - 51 - feedback.frame.width, y: 16)
        let width = max(1, bounds.width - 30)
        textView.frame = NSRect(x: 15, y: 58, width: width, height: textView.contentHeight(for: width))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(VLMSnapperTheme.border).setFill()
        NSRect(x: 0, y: 45, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) { onClearSelection?() }

    @objc private func copyColumn() {
        guard let copyValue, !copyValue.isEmpty else { return }
        onCopy(copyValue)
        feedbackTask?.cancel()
        feedback.isHidden = false
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.feedback.isHidden = true
        }
    }
}

/// Shared identity/selection only: neither column needs the other's geometry.
@MainActor
private final class BilingualSelectionCoordinator: NSObject, NSTextViewDelegate {
    private let views: [AlignedTextView]
    private var selectedIDs = Set<String>()
    private var hoveredID: String?
    private var updating = false

    init(views: [AlignedTextView]) {
        self.views = views
        super.init()
        for text in views {
            text.delegate = self
            text.onHover = { [weak self] id in
                self?.hoveredID = id
                self?.refreshHighlights()
            }
            text.onClick = { [weak self, weak text] id in
                guard let self, let text else { return }
                self.updating = true
                for other in self.views where other !== text {
                    other.setSelectedRange(NSRange(location: 0, length: 0))
                }
                self.updating = false
                self.selectedIDs = id.map { [$0] } ?? []
                self.hoveredID = nil
                self.refreshHighlights()
            }
        }
    }

    func updateContents(_ update: () -> Bool) {
        updating = true
        let resetsSelection = update()
        updating = false
        if resetsSelection { selectedIDs = []; hoveredID = nil }
        refreshHighlights()
    }

    func clear() {
        updating = true
        for view in views { view.setSelectedRange(NSRange(location: 0, length: 0)) }
        updating = false
        selectedIDs = []
        hoveredID = nil
        refreshHighlights()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !updating, let view = notification.object as? AlignedTextView else { return }
        let range = view.selectedRange()
        selectedIDs = Set(view.segmentRanges.compactMap { id, span in
            NSIntersectionRange(range, span).length > 0 ? id : nil
        })
        if range.length > 0 {
            updating = true
            for other in views where other !== view { other.setSelectedRange(NSRange(location: 0, length: 0)) }
            updating = false
        }
        refreshHighlights()
    }

    private func refreshHighlights() {
        for view in views {
            guard let manager = view.layoutManager else { continue }
            manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: view.string.utf16.count))
            for (id, range) in view.segmentRanges {
                let color: NSColor?
                if selectedIDs.contains(id) { color = NSColor(VLMSnapperTheme.historySelected) }
                else if selectedIDs.isEmpty, hoveredID == id { color = NSColor(VLMSnapperTheme.historyHover) }
                else { color = nil }
                if let color { manager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range) }
            }
            view.needsDisplay = true
        }
    }

}

@MainActor
private struct AlignedTextDocument {
    let text: NSAttributedString
    let ranges: [String: NSRange]

    init(segments: [TranslationSegment]?, translated: Bool, fallback: String) {
        let output = NSMutableAttributedString(string: "")
        var spans: [String: NSRange] = [:]
        let items = segments ?? [TranslationSegment(id: "", block: "", kind: .paragraph, source: fallback, translation: fallback)]
        var lastBlock: String?
        for item in items {
            let value = translated ? item.translation : item.source
            guard !value.isEmpty else { continue }
            let startsBlock = lastBlock != item.block
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            style.paragraphSpacing = item.kind == .listItem ? 3 : 10
            style.baseWritingDirection = .natural
            style.lineBreakMode = .byWordWrapping
            if item.kind == .listItem { style.headIndent = 14 }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: item.kind == .heading ? 16 : 13,
                                        weight: item.kind == .heading ? .semibold : .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
            if startsBlock, lastBlock != nil { output.append(NSAttributedString(string: "\n", attributes: attributes)) }
            if startsBlock, item.kind == .listItem { output.append(NSAttributedString(string: "- ", attributes: attributes)) }
            let start = output.length
            output.append(NSAttributedString(string: value, attributes: attributes))
            if segments != nil { spans[item.id] = NSRange(location: start, length: output.length - start) }
            lastBlock = item.block
        }
        text = output
        ranges = spans
    }
}

@MainActor
final class AlignedTextView: NSTextView {
    var segmentRanges: [String: NSRange] = [:]
    var segmentIDs: Set<String> { Set(segmentRanges.keys) }
    var onHover: ((String?) -> Void)?
    var onClick: ((String?) -> Void)?
    private var hoverTracking: NSTrackingArea?
    private let measurementStorage = NSTextStorage()
    private let measurementManager = NSLayoutManager()
    private let measurementContainer = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
    private var measuredHeights: [CGFloat: CGFloat] = [:]

    init() {
        let container = NSTextContainer(containerSize: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        let manager = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        measurementStorage.addLayoutManager(measurementManager)
        measurementManager.addTextContainer(measurementContainer)
        measurementContainer.lineFragmentPadding = 0
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = false
        textContainerInset = .zero
        container.lineFragmentPadding = 0
        // Only committed frame changes control displayed wrapping. Candidate
        // measurements below have their own storage/container/layout manager.
        container.widthTracksTextView = true
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isAutomaticLinkDetectionEnabled = false
        allowsUndo = false
    }

    required init?(coder: NSCoder) { nil }

    func replaceText(_ value: NSAttributedString) {
        textStorage?.setAttributedString(value)
        measurementStorage.setAttributedString(value)
        measuredHeights.removeAll(keepingCapacity: true)
    }

    func contentHeight(for width: CGFloat) -> CGFloat {
        let width = width.isFinite ? max(1, width) : 500
        if let cached = measuredHeights[width] { return cached }
        measurementContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        measurementManager.ensureLayout(for: measurementContainer)
        let height = max(21, ceil(measurementManager.usedRect(for: measurementContainer).height))
        if measuredHeights.count >= 8 { measuredHeights.removeAll(keepingCapacity: true) }
        measuredHeights[width] = height
        return height
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) { onHover?(segment(at: event)) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        if selectedRange().length == 0 { onClick?(segment(at: event)) }
    }

    private func segment(at event: NSEvent) -> String? {
        guard let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = manager.glyphIndex(for: point, in: container)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return nil }
        let character = manager.characterIndexForGlyph(at: glyph)
        return segmentRanges.first { NSLocationInRange(character, $0.value) }?.key
    }
}
