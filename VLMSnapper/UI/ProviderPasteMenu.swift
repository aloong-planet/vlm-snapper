import AppKit

@MainActor
final class ProviderPasteMenu: NSMenu {
    private let router: ProviderPasteRouter

    init(title: String, pasteboard: NSPasteboard, activeResponder: @escaping @MainActor () -> NSResponder?) {
        router = ProviderPasteRouter(pasteboard: pasteboard, activeResponder: activeResponder)
        super.init(title: title)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBeganTracking(_:)),
            name: NSMenu.didBeginTrackingNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func routePaste(in menu: NSMenu) {
        for item in menu.items where item.action == #selector(NSText.paste(_:))
            || item.action == #selector(NSTextView.pasteAsPlainText(_:)) {
            item.target = router
        }
    }

    @objc private func menuBeganTracking(_ notification: Notification) {
        // The system secure editor owns its context menu and does not consult
        // NSTextViewDelegate. Adapt only its existing Paste actions, without
        // replacing that editor, intercepting events, or changing other items.
        guard router.activeCredentialField != nil,
              let menu = notification.object as? NSMenu else { return }
        routePaste(in: menu)
    }
}

@MainActor
private final class ProviderPasteRouter: NSObject, NSMenuItemValidation {
    private let pasteboard: NSPasteboard
    private let activeResponder: @MainActor () -> NSResponder?

    init(pasteboard: NSPasteboard, activeResponder: @escaping @MainActor () -> NSResponder?) {
        self.pasteboard = pasteboard
        self.activeResponder = activeResponder
    }

    @objc func paste(_ sender: Any?) { perform(#selector(NSText.paste(_:)), sender: sender) }
    @objc func pasteAsPlainText(_ sender: Any?) { perform(#selector(NSTextView.pasteAsPlainText(_:)), sender: sender) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let field = activeCredentialField {
            return field.isEditable && pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue])
        }
        guard let action = menuItem.action, let target = normalTarget(for: action) else { return false }
        if let validator = target as? NSMenuItemValidation { return validator.validateMenuItem(menuItem) }
        if let validator = target as? NSUserInterfaceValidations { return validator.validateUserInterfaceItem(menuItem) }
        return true
    }

    var activeCredentialField: ProviderAPIKeyInputView? {
        guard let editor = activeResponder() as? NSTextView,
              let control = editor.delegate as? NSTextField,
              let field = control.superview as? ProviderAPIKeyInputView,
              control === field.activeField else { return nil }
        return field
    }

    private func normalTarget(for action: Selector) -> AnyObject? {
        var responder = activeResponder()
        while let candidate = responder {
            if candidate.responds(to: action) { return candidate }
            responder = candidate.nextResponder
        }
        return NSApp.target(forAction: action) as AnyObject?
    }

    private func perform(_ action: Selector, sender: Any?) {
        if let field = activeCredentialField {
            field.paste(from: pasteboard)
        } else {
            NSApp.sendAction(action, to: normalTarget(for: action), from: sender)
        }
    }
}
