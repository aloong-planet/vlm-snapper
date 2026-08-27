import Foundation
import VLMSnapperCore

public enum VLMSnapperLocalization {
    public static func configure(effectiveLanguage: EffectiveApplicationLanguage) {
        let language = switch effectiveLanguage {
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
        guard let url = Bundle.module.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language
        ), let data = try? Data(contentsOf: url),
        let table = try? PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: String] else { return }
        LocalizationBundleStore.shared.set(table)
    }
}

final class LocalizationBundleStore: @unchecked Sendable {
    static let shared = LocalizationBundleStore()
    private let lock = NSLock()
    private var selectedTable: [String: String]?

    func set(_ table: [String: String]) {
        lock.lock()
        selectedTable = table
        lock.unlock()
    }

    func localized(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return selectedTable?[key]
            ?? Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }
}
