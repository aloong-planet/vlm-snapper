import AppKit
import SwiftUI

@MainActor
final class ProviderAPIKeyInputView: NSView, NSTextFieldDelegate {
    private let secureField = NSSecureTextField()
    private let plainField = NSTextField()
    var onValueChange: (String) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    private(set) var isRevealed = false
    var activeField: NSTextField { isRevealed ? plainField : secureField }
    var isEditable: Bool { activeField.isEditable && activeField.isEnabled }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [secureField as NSTextField, plainField] {
            field.delegate = self
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.alignment = .left
            field.font = .systemFont(ofSize: NSFont.systemFontSize)
            field.cell?.wraps = false
            field.cell?.isScrollable = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: leadingAnchor),
                field.trailingAnchor.constraint(equalTo: trailingAnchor),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        plainField.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 22) }

    func update(value: String, placeholder: String, revealed: Bool, enabled: Bool) {
        let focused = activeField.currentEditor()
        let selection = focused?.selectedRange
        if revealed != isRevealed, focused != nil { window?.makeFirstResponder(nil) }
        let changedVisibility = revealed != isRevealed
        isRevealed = revealed
        for field in [secureField as NSTextField, plainField] {
            if !field.stringValue.utf8.elementsEqual(value.utf8) { field.stringValue = value }
            field.placeholderString = value.isEmpty ? placeholder : ""
            field.isEnabled = enabled
            field.isEditable = enabled
            field.isSelectable = enabled
        }
        secureField.isHidden = revealed
        plainField.isHidden = !revealed
        if changedVisibility, let selection, enabled {
            window?.makeFirstResponder(activeField)
            activeField.currentEditor()?.selectedRange = selection
        }
    }

    func paste(from pasteboard: NSPasteboard) {
        guard isEditable, var value = pasteboard.string(forType: .string),
              let editor = activeField.currentEditor() as? NSTextView else { return }
        if let last = value.last, last == "\r\n" || last == "\n" || last == "\r" {
            value.removeLast()
        }
        editor.insertText(value, replacementRange: editor.selectedRange())
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === activeField else { return }
        onValueChange(activeField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        onSubmit()
        return true
    }
}

struct ProviderAPIKeyField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isRevealed: Bool
    let isEnabled: Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> ProviderAPIKeyInputView {
        ProviderAPIKeyInputView(frame: .zero)
    }

    func updateNSView(_ view: ProviderAPIKeyInputView, context: Context) {
        view.onValueChange = { text = $0 }
        view.onSubmit = onSubmit
        view.update(value: text, placeholder: placeholder, revealed: isRevealed, enabled: isEnabled)
    }
}
