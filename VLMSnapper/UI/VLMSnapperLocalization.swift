import Foundation
import VLMSnapperCore

public enum VLMSnapperLocalization {
    public static func configure(effectiveLanguage: EffectiveApplicationLanguage) {
        let language = switch effectiveLanguage {
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
        guard let url = LocalizationResourceBundle.bundle.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language
        ), let data = try? Data(contentsOf: url),
        let table = try? PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: String] else { return }
        LocalizationBundleStore.shared.set(table, languageIdentifier: language)
    }

    public static func localizedString(forKey key: String) -> String {
        LocalizationBundleStore.shared.localized(key)
    }

    public static func localizedLanguageName(for code: String) -> String {
        LocalizationBundleStore.shared.localizedLanguageName(for: code)
    }
}

final class LocalizationBundleStore: @unchecked Sendable {
    static let shared = LocalizationBundleStore()
    private let lock = NSLock()
    private var selectedTable: [String: String]?
    private var languageIdentifier = "zh-Hans"

    func set(_ table: [String: String], languageIdentifier: String) {
        lock.lock()
        selectedTable = table
        self.languageIdentifier = languageIdentifier
        lock.unlock()
    }

    func localized(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return selectedTable?[key]
            ?? LocalizationResourceBundle.bundle.localizedString(
                forKey: key,
                value: nil,
                table: nil
            )
    }

    func localizedLanguageName(for code: String) -> String {
        lock.lock()
        let locale = Locale(identifier: languageIdentifier)
        lock.unlock()
        return locale.localizedString(forIdentifier: code) ?? code
    }
}

private enum LocalizationResourceBundle {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(
            forResource: "VLMSnapper_VLMSnapperUI",
            withExtension: "bundle"
        ), let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
