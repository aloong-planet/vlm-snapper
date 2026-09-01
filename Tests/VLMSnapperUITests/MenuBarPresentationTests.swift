import Foundation
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 13 menu bar presentation", .serialized)
struct MenuBarPresentationTests {
    @Test("recent records map to real operation, time, status, and screenshot data")
    func recordPresentation() {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        defer {
            VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        }
        let now = Date(timeIntervalSince1970: 10_000)
        let succeeded = record(
            status: .succeeded,
            kind: .translate,
            createdAt: now.addingTimeInterval(-120),
            source: "# Designing Calm Software\nSecond line"
        )
        let failed = record(
            status: .failed,
            kind: .extract,
            createdAt: now.addingTimeInterval(-3_600),
            source: nil
        )

        let succeededItem = MenuRecentItem(record: succeeded, now: now)
        #expect(succeededItem.title == "Designing Calm Software")
        #expect(succeededItem.detail == "Translate · 2 min ago")
        #expect(succeededItem.status == .succeeded)
        #expect(succeededItem.screenshotURL.path == "/tmp/capture.png")

        let failedItem = MenuRecentItem(record: failed, now: now)
        #expect(failedItem.title == "Provider request failed")
        #expect(failedItem.detail == "Extract Text · 1 hr ago")
        #expect(failedItem.status == .failed)
    }

    @Test("provider badge never claims availability before a selected model exists")
    func providerBadgePresentation() {
        #expect(MenuProviderPresentation(readiness: .missing).isAvailable == false)
        #expect(
            MenuProviderPresentation(readiness: .pendingModel(.gemini)).isAvailable == false
        )
        let ready = MenuProviderPresentation(
            readiness: .ready(provider: .deepSeek, modelID: "vision-model")
        )
        #expect(ready.isAvailable)
        #expect(ready.providerName == "DeepSeek")
    }

    @Test("confirmed menu panel geometry remains independent from toolbar geometry")
    func confirmedGeometry() {
        #expect(MenuBarPanelMetrics.width == 370)
        #expect(MenuBarPanelMetrics.outerCornerRadius == 13)
        #expect(MenuBarPanelMetrics.captureButtonHeight == 36)
        #expect(MenuBarPanelMetrics.recentThumbnailSize == CGSize(width: 58, height: 42))
    }

    private func record(
        status: OperationStatus,
        kind: PersistedOperationKind,
        createdAt: Date,
        source: String?
    ) -> HistoryRecord {
        HistoryRecord(
            operation: StoredOperation(
                id: UUID(),
                screenshot: ManagedScreenshot(path: "/tmp/capture.png", sha256: "sha"),
                selection: ProviderSelection(providerID: "deepseek", modelID: "vision-model"),
                status: status,
                sourceMarkdown: source,
                normalizedErrorCode: status == .failed ? "provider_unavailable" : nil,
                kind: kind,
                targetLanguage: kind == .translate ? "zh-Hans" : nil
            ),
            createdAt: createdAt,
            isPinned: false
        )
    }
}
