import AppKit
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 13 application menu", .serialized)
@MainActor
struct ApplicationMenuTests {
    @Test("the Edit menu exposes the complete confirmed hierarchy")
    func completeEditMenuHierarchy() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        defer {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        }

        let menu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper"
        )
        #expect(menu.items.map(\.title) == ["VLMSnapper", "File", "Edit", "Window", "Help"])

        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)
        #expect(nonSeparatorTitles(in: edit) == [
            "Undo", "Redo",
            "Cut", "Copy", "Paste", "Paste and Match Style", "Delete", "Select All",
            "Find", "Spelling and Grammar", "Substitutions", "Transformations", "Speech",
            "Start Dictation…", "Emoji & Symbols",
        ])
        #expect(try submenuTitles(named: "Find", in: edit) == [
            "Find…", "Find Next", "Find Previous", "Use Selection for Find", "Jump to Selection",
        ])
        #expect(try submenuTitles(named: "Spelling and Grammar", in: edit) == [
            "Show Spelling and Grammar", "Check Document Now", "Check Spelling While Typing",
            "Check Grammar With Spelling", "Correct Spelling Automatically",
        ])
        #expect(try submenuTitles(named: "Substitutions", in: edit) == [
            "Show Substitutions", "Smart Copy/Paste", "Smart Quotes", "Smart Dashes",
            "Smart Links", "Data Detectors", "Text Replacement",
        ])
        #expect(try submenuTitles(named: "Transformations", in: edit) == [
            "Make Upper Case", "Make Lower Case", "Capitalize",
        ])
        #expect(try submenuTitles(named: "Speech", in: edit) == [
            "Start Speaking", "Stop Speaking",
        ])
    }

    @Test("editing commands use native responder selectors and confirmed shortcuts")
    func responderSelectorsAndShortcuts() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        defer {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        }
        let menu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper"
        )
        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)

        try expectItem(
            "Paste",
            in: edit,
            selector: "paste:",
            key: "v",
            modifiers: [.command]
        )
        try expectItem(
            "Paste and Match Style",
            in: edit,
            selector: "pasteAsPlainText:",
            key: "v",
            modifiers: [.command, .option, .shift]
        )
        let find = try #require(edit.item(withTitle: "Find")?.submenu)
        try expectItem(
            "Find Next",
            in: find,
            selector: "performTextFinderAction:",
            key: "g",
            modifiers: [.command],
            tag: NSTextFinder.Action.nextMatch.rawValue
        )
        try expectItem(
            "Find Previous",
            in: find,
            selector: "performTextFinderAction:",
            key: "g",
            modifiers: [.command, .shift],
            tag: NSTextFinder.Action.previousMatch.rawValue
        )

        for item in edit.items where !item.isSeparatorItem && !item.hasSubmenu {
            if item.action != #selector(NSText.paste(_:))
                && item.action != #selector(NSTextView.pasteAsPlainText(_:)) {
                #expect(item.target == nil)
            }
        }
    }

    @Test("Paste resolves through the active responder")
    func pasteUsesActiveResponder() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("ordinary text\r\n", forType: .string)
        let responder = PasteRecordingTextView(pasteboard: board)
        let menu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper", activeResponder: { responder }
        )
        let edit = try #require(menu.item(withTitle: "Edit")?.submenu)
        let paste = try #require(edit.item(withTitle: "Paste"))
        edit.performActionForItem(at: edit.index(of: paste))
        #expect(responder.pasteCount == 1)
        #expect(responder.receivedText.map { Array($0.utf8) } == Array("ordinary text\r\n".utf8))
    }

    @Test("the complete Edit menu is localized in Simplified Chinese")
    func simplifiedChineseMenu() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        let menu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper"
        )
        #expect(menu.items.map(\.title) == ["VLMSnapper", "文件", "编辑", "窗口", "帮助"])
        let edit = try #require(menu.item(withTitle: "编辑")?.submenu)
        #expect(nonSeparatorTitles(in: edit) == [
            "撤销", "重做", "剪切", "拷贝", "粘贴", "粘贴并匹配样式", "删除", "全选",
            "查找", "拼写与语法", "替换", "转换", "语音", "开始听写…", "表情与符号",
        ])
    }

    private func nonSeparatorTitles(in menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    private func submenuTitles(named title: String, in menu: NSMenu) throws -> [String] {
        let submenu = try #require(menu.item(withTitle: title)?.submenu)
        return nonSeparatorTitles(in: submenu)
    }

    private func expectItem(
        _ title: String,
        in menu: NSMenu,
        selector: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        tag: Int? = nil
    ) throws {
        let item = try #require(menu.item(withTitle: title))
        #expect(item.action == Selector(selector))
        #expect(item.keyEquivalent == key)
        #expect(item.keyEquivalentModifierMask == modifiers)
        if let tag {
            #expect(item.tag == tag)
        }
    }
}

@MainActor
private final class PasteRecordingTextView: NSTextView {
    private(set) var pasteCount = 0
    private(set) var receivedText: String?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        super.init(frame: .init(x: 0, y: 0, width: 200, height: 40), textContainer: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func paste(_ sender: Any?) {
        pasteCount += 1
        receivedText = pasteboard.string(forType: .string)
    }
}
