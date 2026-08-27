import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Application language")
struct ApplicationLanguageTests {
    @Test("System strategy scans the full preference list")
    func systemStrategyScansFullPreferenceList() {
        let resolver = ApplicationLanguageResolver()

        #expect(
            resolver.resolve(
                preference: .system,
                preferredLanguages: ["fr-FR", "en-GB", "zh-Hans-CN"]
            ) == .english
        )
        #expect(
            resolver.resolve(
                preference: .system,
                preferredLanguages: ["zh-Hant-TW", "zh-Hans-CN", "en-US"]
            ) == .simplifiedChinese
        )
    }

    @Test("Manual strategy remains independent from region and system order")
    func manualStrategyWins() {
        let resolver = ApplicationLanguageResolver()

        #expect(
            resolver.resolve(
                preference: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == .english
        )
        #expect(
            resolver.resolve(
                preference: .simplifiedChinese,
                preferredLanguages: ["en-US"]
            ) == .simplifiedChinese
        )
    }

    @Test("Preference store preserves the system strategy")
    func preferenceStorePreservesSystemStrategy() async throws {
        let suiteName = "VLMSnapper.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsApplicationLanguageStore(defaults: defaults)

        #expect(await store.load() == .system)
        await store.save(.english)
        #expect(await store.load() == .english)
        await store.save(.system)
        #expect(await store.load() == .system)
    }
}
