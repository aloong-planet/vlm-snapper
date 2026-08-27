import AppKit
import SwiftUI
import VLMSnapperCore

public struct GlobalShortcutRecorder: NSViewRepresentable {
    private let shortcut: GlobalShortcut
    private let onChange: (GlobalShortcut) -> Void

    public init(
        shortcut: GlobalShortcut,
        onChange: @escaping (GlobalShortcut) -> Void
    ) {
        self.shortcut = shortcut
        self.onChange = onChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    public func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onChange = context.coordinator.onChange
        view.shortcut = shortcut
        return view
    }

    public func updateNSView(
        _ nsView: ShortcutRecorderNSView,
        context: Context
    ) {
        context.coordinator.onChange = onChange
        nsView.onChange = context.coordinator.onChange
        nsView.shortcut = shortcut
    }

    public final class Coordinator {
        var onChange: (GlobalShortcut) -> Void

        init(onChange: @escaping (GlobalShortcut) -> Void) {
            self.onChange = onChange
        }
    }
}

@MainActor
public final class ShortcutRecorderNSView: NSView {
    var onChange: ((GlobalShortcut) -> Void)?
    var shortcut = GlobalShortcut.defaultCapture {
        didSet { refreshLabel() }
    }

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = VLMSnapperUIConstants.compactCornerRadius
        layer?.borderWidth = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        refreshAppearance()
        refreshLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override var acceptsFirstResponder: Bool { true }
    public override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 28)
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        refreshAppearance()
        refreshLabel()
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            refreshAppearance()
            refreshLabel()
            return
        }
        let modifiers = GlobalShortcutModifiers(event.modifierFlags)
        onChange?(
            GlobalShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: modifiers
            )
        )
        isRecording = false
        refreshAppearance()
        refreshLabel()
    }

    public override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshAppearance()
        refreshLabel()
        return super.resignFirstResponder()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    private func refreshAppearance() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (
            isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        ).cgColor
    }

    private func refreshLabel() {
        label.stringValue = isRecording
            ? VLMSnapperStrings.shortcutRecording
            : GlobalShortcutDisplayFormatter.string(for: shortcut)
        setAccessibilityLabel(label.stringValue)
    }
}

private extension GlobalShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: GlobalShortcutModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }
}

public enum GlobalShortcutDisplayFormatter {
    public static func string(for shortcut: GlobalShortcut) -> String {
        let modifiers = [
            shortcut.modifiers.contains(.control) ? "⌃" : "",
            shortcut.modifiers.contains(.option) ? "⌥" : "",
            shortcut.modifiers.contains(.shift) ? "⇧" : "",
            shortcut.modifiers.contains(.command) ? "⌘" : "",
        ].joined()
        return modifiers + keyName(for: shortcut.keyCode)
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z",
            7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
            14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
            34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
            46: "M", 49: "Space",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
