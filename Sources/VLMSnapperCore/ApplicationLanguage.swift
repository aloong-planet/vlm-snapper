import Foundation

public enum ApplicationLanguagePreference: String, CaseIterable, Codable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

public enum EffectiveApplicationLanguage: String, CaseIterable, Codable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

public struct ApplicationLanguageResolver: Sendable {
    public init() {}

    public func resolve(
        preference: ApplicationLanguagePreference,
        preferredLanguages: [String]
    ) -> EffectiveApplicationLanguage {
        switch preference {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            return preferredLanguages.lazy.compactMap(resolveSystemLanguage).first
                ?? .simplifiedChinese
        }
    }

    private func resolveSystemLanguage(_ identifier: String) -> EffectiveApplicationLanguage? {
        let members = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-")
            .map(String.init)
        guard let language = members.first else { return nil }
        if language == "en" { return .english }
        guard language == "zh" else { return nil }
        if members.contains("hant") || !Set(members).isDisjoint(with: ["tw", "hk", "mo"]) {
            return nil
        }
        if members.count == 1 || members.contains("hans")
            || !Set(members).isDisjoint(with: ["cn", "sg"])
        {
            return .simplifiedChinese
        }
        return nil
    }
}

public protocol ApplicationLanguagePreferenceStoring: Sendable {
    func load() async -> ApplicationLanguagePreference
    func save(_ preference: ApplicationLanguagePreference) async throws
}

public final class UserDefaultsApplicationLanguageStore: ApplicationLanguagePreferenceStoring, @unchecked Sendable {
    private static let key = "applicationLanguagePreference"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() async -> ApplicationLanguagePreference {
        guard let rawValue = defaults.string(forKey: Self.key) else { return .system }
        return ApplicationLanguagePreference(rawValue: rawValue) ?? .system
    }

    public func save(_ preference: ApplicationLanguagePreference) async {
        defaults.set(preference.rawValue, forKey: Self.key)
    }
}
