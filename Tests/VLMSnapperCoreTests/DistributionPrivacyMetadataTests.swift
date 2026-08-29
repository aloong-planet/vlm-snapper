import Foundation
import Testing

@Suite("Distribution privacy metadata")
struct DistributionPrivacyMetadataTests {
    @Test("Screen capture purpose is exact in the fallback and supported localizations")
    func screenCapturePurposeIsLocalized() throws {
        let distribution = repositoryRoot.appendingPathComponent("Distribution")
        let fallback = try dictionary(
            at: distribution.appendingPathComponent("Info.plist")
        )
        let english = try? dictionary(
            at: distribution.appendingPathComponent("en.lproj/InfoPlist.strings")
        )
        let simplifiedChinese = try? dictionary(
            at: distribution.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings")
        )

        #expect(
            fallback["NSScreenCaptureUsageDescription"] as? String
                == "VLMSnapper needs access to screen content so you can capture a selected area for text extraction or translation."
        )
        #expect(
            english?["NSScreenCaptureUsageDescription"] as? String
                == "VLMSnapper needs access to screen content so you can capture a selected area for text extraction or translation."
        )
        #expect(
            simplifiedChinese?["NSScreenCaptureUsageDescription"] as? String
                == "VLMSnapper 需要访问屏幕内容，以便截取你选择的区域并进行文字提取或翻译。"
        )
    }

    private func dictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
