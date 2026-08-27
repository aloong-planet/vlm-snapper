import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Extraction coordinator")
struct ExtractionCoordinatorTests {
    @Test("a persisted extraction reaches the selected provider")
    func persistedExtractionReachesSelectedProvider() async throws {
        let originalPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x01])
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-120000.png",
            sha256: "known-sha256"
        )
        let selection = ProviderSelection(
            providerID: "openai",
            modelID: "gpt-vision"
        )
        let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let expected = ExtractionResult(markdown: "Hello")

        let provider = SuccessfulProvider(
            expectedPNG: originalPNG,
            expectedOperationID: operationID,
            expectedScreenshot: screenshot,
            result: expected
        )
        let coordinator = ExtractionCoordinator(
            screenshotStore: SuccessfulScreenshotStore(
                expectedPNG: originalPNG,
                screenshot: screenshot
            ),
            historyStore: SuccessfulHistoryStore(operationID: operationID),
            provider: provider
        )

        let result = try await coordinator.startExtraction(
            originalPNG: originalPNG,
            selection: selection
        )

        #expect(result == expected)
        #expect(await provider.requestCount == 1)
    }

    @Test("a screenshot persistence failure never reaches the provider")
    func screenshotPersistenceFailureNeverReachesProvider() async {
        let provider = ProviderProbe()
        let coordinator = ExtractionCoordinator(
            screenshotStore: FailingScreenshotStore(),
            historyStore: SuccessfulHistoryStore(operationID: UUID()),
            provider: provider
        )

        do {
            _ = try await coordinator.startExtraction(
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
                selection: ProviderSelection(
                    providerID: "gemini",
                    modelID: "gemini-vision"
                )
            )
            Issue.record("Expected screenshot persistence to fail")
        } catch {
            #expect(error as? ExtractionCoordinatorError == .screenshotPersistenceFailed)
        }

        #expect(await provider.requestCount == 0)
    }

    @Test("a history preparation failure rolls back the screenshot and never reaches the provider")
    func historyPreparationFailureRollsBackScreenshot() async {
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-120001.png",
            sha256: "rollback-sha256"
        )
        let screenshotStore = RollbackScreenshotStore(screenshot: screenshot)
        let provider = ProviderProbe()
        let coordinator = ExtractionCoordinator(
            screenshotStore: screenshotStore,
            historyStore: FailingHistoryStore(),
            provider: provider
        )

        do {
            _ = try await coordinator.startExtraction(
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x02]),
                selection: ProviderSelection(
                    providerID: "deepseek",
                    modelID: "deepseek-v4-flash-vision-exp"
                )
            )
            Issue.record("Expected history preparation to fail")
        } catch {
            #expect(error as? ExtractionCoordinatorError == .historyPreparationFailed)
        }

        #expect(await screenshotStore.discardedScreenshot == screenshot)
        #expect(await provider.requestCount == 0)
    }

    @Test("a failed rollback reports the orphan path and never reaches the provider")
    func failedRollbackReportsOrphanPath() async {
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-120002.png",
            sha256: "orphan-sha256"
        )
        let provider = ProviderProbe()
        let coordinator = ExtractionCoordinator(
            screenshotStore: FailingRollbackScreenshotStore(screenshot: screenshot),
            historyStore: FailingHistoryStore(),
            provider: provider
        )

        do {
            _ = try await coordinator.startExtraction(
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x03]),
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "gpt-vision"
                )
            )
            Issue.record("Expected history preparation to fail")
        } catch {
            #expect(
                error as? ExtractionCoordinatorError
                    == .historyPreparationFailedWithOrphan(path: screenshot.path)
            )
        }

        #expect(await provider.requestCount == 0)
    }

    @Test("a mismatched prepared record is rolled back and never reaches the provider")
    func mismatchedPreparedRecordIsRejected() async {
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-120003.png",
            sha256: "expected-sha256"
        )
        let screenshotStore = RollbackScreenshotStore(screenshot: screenshot)
        let provider = ProviderProbe()
        let coordinator = ExtractionCoordinator(
            screenshotStore: screenshotStore,
            historyStore: MismatchedHistoryStore(),
            provider: provider
        )

        do {
            _ = try await coordinator.startExtraction(
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x04]),
                selection: ProviderSelection(
                    providerID: "gemini",
                    modelID: "gemini-vision"
                )
            )
            Issue.record("Expected the mismatched prepared record to be rejected")
        } catch {
            #expect(error as? ExtractionCoordinatorError == .historyPreparationFailed)
        }

        #expect(await screenshotStore.discardedScreenshot == screenshot)
        #expect(await provider.requestCount == 0)
    }

    @Test("a prepared record with a different model selection never reaches the provider")
    func mismatchedPreparedSelectionIsRejected() async {
        let screenshot = ManagedScreenshot(
            path: "/Pictures/VLMSnapper/2026-08/vlmsnapper-20260826-120004.png",
            sha256: "selection-sha256"
        )
        let screenshotStore = RollbackScreenshotStore(screenshot: screenshot)
        let provider = ProviderProbe()
        let coordinator = ExtractionCoordinator(
            screenshotStore: screenshotStore,
            historyStore: MismatchedSelectionHistoryStore(),
            provider: provider
        )

        do {
            _ = try await coordinator.startExtraction(
                originalPNG: Data([0x89, 0x50, 0x4E, 0x47, 0x05]),
                selection: ProviderSelection(
                    providerID: "openai",
                    modelID: "gpt-vision"
                )
            )
            Issue.record("Expected the mismatched model selection to be rejected")
        } catch {
            #expect(error as? ExtractionCoordinatorError == .historyPreparationFailed)
        }

        #expect(await screenshotStore.discardedScreenshot == screenshot)
        #expect(await provider.requestCount == 0)
    }
}

private enum BoundaryFailure: Error {
    case screenshotWrite
    case historyWrite
}

private struct FailingScreenshotStore: ScreenshotPersisting {
    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        throw BoundaryFailure.screenshotWrite
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {}
}

private struct SuccessfulScreenshotStore: ScreenshotPersisting {
    let expectedPNG: Data
    let screenshot: ManagedScreenshot

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        #expect(originalPNG == expectedPNG)
        return screenshot
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {}
}

private actor RollbackScreenshotStore: ScreenshotPersisting {
    let screenshot: ManagedScreenshot
    private(set) var discardedScreenshot: ManagedScreenshot?

    init(screenshot: ManagedScreenshot) {
        self.screenshot = screenshot
    }

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        screenshot
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        discardedScreenshot = screenshot
    }
}

private struct FailingRollbackScreenshotStore: ScreenshotPersisting {
    let screenshot: ManagedScreenshot

    func save(originalPNG: Data) async throws -> ManagedScreenshot {
        screenshot
    }

    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        throw BoundaryFailure.screenshotWrite
    }
}

private struct FailingHistoryStore: HistoryPersisting {
    func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction {
        throw BoundaryFailure.historyWrite
    }
}

private struct MismatchedHistoryStore: HistoryPersisting {
    func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction {
        PreparedExtraction(
            operationID: UUID(),
            screenshot: ManagedScreenshot(
                path: screenshot.path,
                sha256: "different-sha256"
            ),
            selection: selection
        )
    }
}

private struct MismatchedSelectionHistoryStore: HistoryPersisting {
    func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction {
        PreparedExtraction(
            operationID: UUID(),
            screenshot: screenshot,
            selection: ProviderSelection(
                providerID: selection.providerID,
                modelID: "different-model"
            )
        )
    }
}

private struct SuccessfulHistoryStore: HistoryPersisting {
    let operationID: UUID

    func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction {
        PreparedExtraction(
            operationID: operationID,
            screenshot: screenshot,
            selection: selection
        )
    }
}

private actor SuccessfulProvider: ProviderExtracting {
    let expectedPNG: Data
    let expectedOperationID: UUID
    let expectedScreenshot: ManagedScreenshot
    let result: ExtractionResult
    private(set) var requestCount = 0

    init(
        expectedPNG: Data,
        expectedOperationID: UUID,
        expectedScreenshot: ManagedScreenshot,
        result: ExtractionResult
    ) {
        self.expectedPNG = expectedPNG
        self.expectedOperationID = expectedOperationID
        self.expectedScreenshot = expectedScreenshot
        self.result = result
    }

    func extractText(
        from originalPNG: Data,
        preparedExtraction: PreparedExtraction
    ) async throws -> ExtractionResult {
        requestCount += 1
        #expect(originalPNG == expectedPNG)
        #expect(preparedExtraction.operationID == expectedOperationID)
        #expect(preparedExtraction.screenshot == expectedScreenshot)
        #expect(preparedExtraction.selection.providerID == "openai")
        #expect(preparedExtraction.selection.modelID == "gpt-vision")
        return result
    }
}

private actor ProviderProbe: ProviderExtracting {
    private(set) var requestCount = 0

    func extractText(
        from originalPNG: Data,
        preparedExtraction: PreparedExtraction
    ) async throws -> ExtractionResult {
        requestCount += 1
        return ExtractionResult(markdown: "unexpected")
    }
}
