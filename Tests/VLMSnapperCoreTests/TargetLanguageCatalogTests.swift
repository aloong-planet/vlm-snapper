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

    @Test("traditional Chinese and free-form values are unavailable")
    func excludesTraditionalChineseAndUnknownValues() {
        let catalog = TargetLanguageCatalog.standard

        #expect(catalog.contains("zh-Hans"))
        #expect(!catalog.contains("zh"))
        #expect(!catalog.contains("zh-Hant"))
        #expect(!catalog.contains("custom-language"))
    }
}
