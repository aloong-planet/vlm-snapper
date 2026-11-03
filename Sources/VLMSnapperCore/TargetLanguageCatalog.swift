import Foundation

public struct TargetLanguageCatalog: Equatable, Sendable {
    public static let priorityCodes = [
        "zh-Hans", "en", "ja", "ko", "es", "fr",
        "de", "pt", "it", "ru", "ar",
    ]

    public static let standard = TargetLanguageCatalog(
        codes: standardLanguageCodes()
    )

    public let codes: [String]

    public init(codes: [String]) {
        self.codes = codes
    }

    public func contains(_ code: String) -> Bool {
        codes.contains(code)
    }

    /// What the capture toolbar shows for a language: its primary language code in upper case, such as
    /// `ZH` for `zh-Hans` (v1-core::REQ-013/AC-03). Codes stay the runtime and stored values.
    public static func abbreviation(for code: String) -> String {
        String(code.prefix { $0 != "-" }).uppercased()
    }

    private static func standardLanguageCodes() -> [String] {
        var seen = Set<String>()
        let remaining = Locale.LanguageCode.isoLanguageCodes
            .map(\.identifier)
            .map { $0 == "zh" ? "zh-Hans" : $0 }
            .filter { !$0.hasPrefix("zh-Hant") }
            .filter { seen.insert($0).inserted }
            .filter { !priorityCodes.contains($0) }
            .sorted()
        return priorityCodes + remaining
    }
}
