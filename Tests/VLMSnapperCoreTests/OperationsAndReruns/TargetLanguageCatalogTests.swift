import Testing
@testable import VLMSnapperCore

@Suite("Target language catalog")
struct TargetLanguageCatalogTests {
    @Test("priority languages lead the complete standard catalog")
    func priorityLanguagesLeadCatalog() {
        let catalog = TargetLanguageCatalog.standard

        #expect(
            Array(catalog.codes.prefix(11)) == [
                "zh-Hans", "en", "ja", "ko", "es", "fr",
                "de", "pt", "it", "ru", "ar",
            ]
        )
        #expect(catalog.codes.count > 100)
        #expect(Set(catalog.codes).count == catalog.codes.count)
    }

    @Test("an abbreviation is the upper-case primary language code")
    func abbreviationUsesPrimaryCode() {
        #expect(TargetLanguageCatalog.abbreviation(for: "zh-Hans") == "ZH")
        #expect(TargetLanguageCatalog.abbreviation(for: "en") == "EN")
        #expect(TargetLanguageCatalog.abbreviation(for: "aeb") == "AEB")
    }

    @Test("every language in the catalog has its own short abbreviation")
    func catalogAbbreviationsAreUniqueAndShort() {
        let codes = TargetLanguageCatalog.standard.codes
        let abbreviations = codes.map(TargetLanguageCatalog.abbreviation(for:))

        #expect(Set(abbreviations).count == codes.count)
        #expect(abbreviations.allSatisfy { (2...3).contains($0.count) && $0 == $0.uppercased() })
    }

    @Test("traditional Chinese and free-form values are unavailable")
    func excludesTraditionalChineseAndUnknownValues() {
        let catalog = TargetLanguageCatalog.standard

        #expect(catalog.contains("zh-Hans"))
        #expect(!catalog.contains("zh"))
        #expect(!catalog.contains("zh-Hant"))
        #expect(!catalog.contains("custom-language"))
    }
}
