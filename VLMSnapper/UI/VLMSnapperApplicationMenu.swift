import AppKit

@MainActor
public enum VLMSnapperApplicationMenuBuilder {
    public static func makeMainMenu(applicationName: String) -> NSMenu {
        let mainMenu = NSMenu(title: applicationName)
        mainMenu.addItem(topLevelItem(title: applicationName, submenu: applicationMenu(applicationName)))
        mainMenu.addItem(topLevelItem(title: VLMSnapperStrings.menuFile, submenu: fileMenu()))
        mainMenu.addItem(topLevelItem(title: VLMSnapperStrings.menuEdit, submenu: editMenu()))
        mainMenu.addItem(topLevelItem(title: VLMSnapperStrings.menuWindow, submenu: windowMenu()))
        mainMenu.addItem(topLevelItem(title: VLMSnapperStrings.menuHelp, submenu: helpMenu()))
        return mainMenu
    }

    private static func applicationMenu(_ applicationName: String) -> NSMenu {
        let menu = NSMenu(title: applicationName)
        menu.addItem(item(
            title: String(format: VLMSnapperStrings.menuAboutFormat, applicationName),
            action: "orderFrontStandardAboutPanel:"
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: String(format: VLMSnapperStrings.menuHideFormat, applicationName),
            action: "hide:",
            key: "h"
        ))
        menu.addItem(item(
            title: VLMSnapperStrings.menuHideOthers,
            action: "hideOtherApplications:",
            key: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(item(title: VLMSnapperStrings.menuShowAll, action: "unhideAllApplications:"))
        menu.addItem(.separator())
        menu.addItem(item(
            title: VLMSnapperStrings.menuQuit,
            action: "terminate:",
            key: "q"
        ))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.menuFile)
        menu.addItem(item(title: VLMSnapperStrings.menuCloseWindow, action: "performClose:", key: "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.menuEdit)
        menu.addItem(item(title: VLMSnapperStrings.editUndo, action: "undo:", key: "z"))
        menu.addItem(item(
            title: VLMSnapperStrings.editRedo,
            action: "redo:",
            key: "z",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(item(title: VLMSnapperStrings.editCut, action: "cut:", key: "x"))
        menu.addItem(item(title: VLMSnapperStrings.editCopy, action: "copy:", key: "c"))
        menu.addItem(item(title: VLMSnapperStrings.editPaste, action: "paste:", key: "v"))
        menu.addItem(item(
            title: VLMSnapperStrings.editPasteAndMatchStyle,
            action: "pasteAsPlainText:",
            key: "v",
            modifiers: [.command, .option, .shift]
        ))
        menu.addItem(item(title: VLMSnapperStrings.editDelete, action: "delete:"))
        menu.addItem(item(title: VLMSnapperStrings.editSelectAll, action: "selectAll:", key: "a"))
        menu.addItem(.separator())
        menu.addItem(submenuItem(title: VLMSnapperStrings.editFind, submenu: findMenu()))
        menu.addItem(submenuItem(
            title: VLMSnapperStrings.editSpellingAndGrammar,
            submenu: spellingMenu()
        ))
        menu.addItem(submenuItem(title: VLMSnapperStrings.editSubstitutions, submenu: substitutionsMenu()))
        menu.addItem(submenuItem(title: VLMSnapperStrings.editTransformations, submenu: transformationsMenu()))
        menu.addItem(submenuItem(title: VLMSnapperStrings.editSpeech, submenu: speechMenu()))
        menu.addItem(.separator())
        menu.addItem(item(title: VLMSnapperStrings.editStartDictation, action: "startDictation:"))
        menu.addItem(item(
            title: VLMSnapperStrings.editEmojiAndSymbols,
            action: "orderFrontCharacterPalette:",
            key: " ",
            modifiers: [.command, .control]
        ))
        return menu
    }

    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.editFind)
        menu.addItem(textFinderItem(
            title: VLMSnapperStrings.editFindPanel,
            action: .showFindInterface,
            key: "f"
        ))
        menu.addItem(textFinderItem(
            title: VLMSnapperStrings.editFindNext,
            action: .nextMatch,
            key: "g"
        ))
        menu.addItem(textFinderItem(
            title: VLMSnapperStrings.editFindPrevious,
            action: .previousMatch,
            key: "g",
            modifiers: [.command, .shift]
        ))
        menu.addItem(textFinderItem(
            title: VLMSnapperStrings.editUseSelectionForFind,
            action: .setSearchString,
            key: "e"
        ))
        menu.addItem(item(
            title: VLMSnapperStrings.editJumpToSelection,
            action: "centerSelectionInVisibleArea:",
            key: "j"
        ))
        return menu
    }

    private static func spellingMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.editSpellingAndGrammar)
        menu.addItem(item(
            title: VLMSnapperStrings.editShowSpellingAndGrammar,
            action: "showGuessPanel:",
            key: ":"
        ))
        menu.addItem(item(
            title: VLMSnapperStrings.editCheckDocumentNow,
            action: "checkSpelling:",
            key: ";"
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: VLMSnapperStrings.editCheckSpellingWhileTyping,
            action: "toggleContinuousSpellChecking:"
        ))
        menu.addItem(item(
            title: VLMSnapperStrings.editCheckGrammarWithSpelling,
            action: "toggleGrammarChecking:"
        ))
        menu.addItem(item(
            title: VLMSnapperStrings.editCorrectSpellingAutomatically,
            action: "toggleAutomaticSpellingCorrection:"
        ))
        return menu
    }

    private static func substitutionsMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.editSubstitutions)
        menu.addItem(item(
            title: VLMSnapperStrings.editShowSubstitutions,
            action: "orderFrontSubstitutionsPanel:"
        ))
        menu.addItem(.separator())
        menu.addItem(item(title: VLMSnapperStrings.editSmartCopyPaste, action: "toggleSmartInsertDelete:"))
        menu.addItem(item(title: VLMSnapperStrings.editSmartQuotes, action: "toggleAutomaticQuoteSubstitution:"))
        menu.addItem(item(title: VLMSnapperStrings.editSmartDashes, action: "toggleAutomaticDashSubstitution:"))
        menu.addItem(item(title: VLMSnapperStrings.editSmartLinks, action: "toggleAutomaticLinkDetection:"))
        menu.addItem(item(title: VLMSnapperStrings.editDataDetectors, action: "toggleAutomaticDataDetection:"))
        menu.addItem(item(title: VLMSnapperStrings.editTextReplacement, action: "toggleAutomaticTextReplacement:"))
        return menu
    }

    private static func transformationsMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.editTransformations)
        menu.addItem(item(title: VLMSnapperStrings.editMakeUpperCase, action: "uppercaseWord:"))
        menu.addItem(item(title: VLMSnapperStrings.editMakeLowerCase, action: "lowercaseWord:"))
        menu.addItem(item(title: VLMSnapperStrings.editCapitalize, action: "capitalizeWord:"))
        return menu
    }

    private static func speechMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.editSpeech)
        menu.addItem(item(title: VLMSnapperStrings.editStartSpeaking, action: "startSpeaking:"))
        menu.addItem(item(title: VLMSnapperStrings.editStopSpeaking, action: "stopSpeaking:"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: VLMSnapperStrings.menuWindow)
        menu.addItem(item(title: VLMSnapperStrings.menuMinimize, action: "performMiniaturize:", key: "m"))
        menu.addItem(item(title: VLMSnapperStrings.menuZoom, action: "performZoom:"))
        menu.addItem(.separator())
        menu.addItem(item(title: VLMSnapperStrings.menuBringAllToFront, action: "arrangeInFront:"))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        NSMenu(title: VLMSnapperStrings.menuHelp)
    }

    private static func topLevelItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        topLevelItem(title: title, submenu: submenu)
    }

    private static func item(
        title: String,
        action: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = nil
        return item
    }

    private static func textFinderItem(
        title: String,
        action: NSTextFinder.Action,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = self.item(
            title: title,
            action: "performTextFinderAction:",
            key: key,
            modifiers: modifiers
        )
        item.tag = action.rawValue
        return item
    }
}
