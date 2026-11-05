import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Persisted operation workspace runner")
struct PersistedOperationWorkspaceRunnerTests {
    @Test("aligned translation survives persistence and a fresh workspace restore")
    func alignedTranslationSurvivesRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let history = try SQLiteHistoryStore(databaseURL: url)
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(events: [
                .translationSegments([
                    TranslationSegment(id: "a", block: "p1", kind: .paragraph, source: "Hello. ", translation: "你好。"),
                    TranslationSegment(id: "b", block: "p1", kind: .paragraph, source: "Help?", translation: "需要帮助？"),
                ]),
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)), .completed,
            ])
        )
        _ = try await collect(await runner.run(originalPNG: Data([1]),
            operation: .translate(targetLanguage: "zh-Hans"),
            selection: ProviderSelection(providerID: "gemini", modelID: "vision")))
        let reopened = try SQLiteHistoryStore(databaseURL: url)
        let rows = try await reopened.history(matching: HistoryQuery())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        let restored = OperationWorkspaceSnapshot(restoring: row.operation)
        #expect(restored.translate.committedResult?.sourceMarkdown == "Hello. Help?")
        #expect(restored.translate.committedResult?.segments?.map(\.id) == ["a", "b"])
        #expect(restored.translate.committedResult?.segments?.last?.translation == "需要帮助？")
    }

    @Test("terminal history includes first text total latency and provider usage")
    func terminalHistoryIncludesMetrics() async throws {
        let history = RunnerHistoryProbe()
        let clock = RunnerClock(values: [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 10.25),
            Date(timeIntervalSince1970: 10.9),
        ])
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(events: [
                .sourceDelta("Text"),
                .metadata(ProviderResponseMetadata(
                    requestID: "request",
                    usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 4, totalTokens: 14)
                )),
                .completed,
            ]),
            now: { clock.next() }
        )

        _ = try await extract(on: runner)

        #expect(await history.metrics == [PersistedOperationMetrics(
            firstTextLatencyMilliseconds: 250,
            totalLatencyMilliseconds: 900,
            usage: ProviderTokenUsage(inputTokens: 10, outputTokens: 4, totalTokens: 14)
        )])
    }

    /// Runs on one screenshot, and the records they should leave. Repeating the last operation is a rerun of its record.
    static let runsOnOneScreenshot: [([ProviderOperation], [ProviderOperation])] = [
        ([.extractText, .translate(targetLanguage: "en")], [.extractText, .translate(targetLanguage: "en")]),
        (
            [.translate(targetLanguage: "zh-Hans"), .translate(targetLanguage: "ja"), .translate(targetLanguage: "ja")],
            [.translate(targetLanguage: "zh-Hans"), .translate(targetLanguage: "ja")]
        ),
        (
            [.translate(targetLanguage: "en"), .translate(targetLanguage: "ja"), .translate(targetLanguage: "en")],
            [.translate(targetLanguage: "en"), .translate(targetLanguage: "ja"), .translate(targetLanguage: "en")]
        ),
    ]

    @Test(
        "each run reuses one screenshot and starts one stream, and only a rerun of the same operation keeps its record",
        arguments: runsOnOneScreenshot
    )
    func eachRunReusesTheScreenshot(runs: [ProviderOperation], records: [ProviderOperation]) async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe()
        let runner = makeRunner(screenshotStore: screenshotStore, history: history, provider: provider)
        for operation in runs {
            _ = try await collect(await runner.run(
                originalPNG: Data([1]),
                operation: operation,
                selection: ProviderSelection(providerID: "gemini", modelID: "vision")
            ))
        }

        #expect(await history.operations == records)
        #expect(await history.currentOutcomes.count == records.count)
        #expect(await screenshotStore.saveCount == 1)
        #expect(await provider.streamCount == runs.count)
    }

    @Test("a runner opened on a record never starts another one, whatever language a run asks for")
    func restoredRecordStaysBound() async throws {
        let saved = try await savedRecord(of: .translate(targetLanguage: "zh-Hans"))
        let runner = makeRunner(screenshotStore: saved.screenshotStore, history: saved.history, restoring: saved.stored)

        _ = try await collect(await runner.run(
            originalPNG: Data([1]),
            operation: .translate(targetLanguage: "en"),
            selection: saved.stored.selection
        ))

        #expect(await saved.history.operations == [.translate(targetLanguage: "zh-Hans")])
        #expect(await saved.history.currentOutcomes.keys.first == saved.stored.id)
        #expect(await saved.history.currentOutcomes.count == 1)
    }

    @Test("a screenshot that cannot be saved reports its own reason and prepares no record")
    func screenshotSaveFailureReportsItsReason() async throws {
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe(runs: [.open])
        let runner = makeRunner(screenshotStore: RunnerFailingScreenshotStoreProbe(), history: history, provider: provider)

        await #expect(throws: OperationWorkspaceRunFailure(code: "screenshot_save_failed")) {
            _ = try await extract(on: runner)
        }

        #expect(await history.operations.isEmpty)
        #expect(await history.completions.isEmpty)
        #expect(await history.outcomes.isEmpty)
        #expect(await provider.streamCount == 0)
    }

    @Test("canceling a running request records it as canceled, not as an incomplete response")
    func cancelingRunningRequestRecordsCanceled() async throws {
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe(runs: [.open])
        let runner = makeRunner(history: history, provider: provider)
        let consumer = Task { try await extract(on: runner) }
        for _ in 0..<500 where await provider.streamCount == 0 {
            try await Task.sleep(for: .milliseconds(2))
        }
        try #require(await provider.streamCount == 1)

        consumer.cancel()
        _ = try? await consumer.value
        await runner.waitForRunToFinish()

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty, "no failure is recorded")
    }

    @Test("rerunning one operation replaces its existing history record")
    func rerunReplacesExistingHistoryRecord() async throws {
        let history = RunnerHistoryProbe()
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(runs: [.text("First result"), .text("Replacement result")])
        )

        _ = try await extract(on: runner)
        _ = try await extract(on: runner)

        #expect(await history.operations == [.extractText])
        #expect(await history.currentOutcomes.count == 1)
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(sourceMarkdown: "Replacement result", translationMarkdown: nil)
        )
    }

    @Test("a failed rerun preserves the previous persisted result")
    func failedRerunPreservesPreviousPersistedResult() async throws {
        let history = RunnerHistoryProbe()
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(runs: [.text("Original result"), .failure(ProviderAdapterError.providerUnavailable)])
        )
        _ = try await extract(on: runner)

        await #expect(throws: OperationWorkspaceRunFailure(code: "provider_unavailable")) {
            _ = try await extract(on: runner)
        }

        #expect(await history.operations == [.extractText])
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(sourceMarkdown: "Original result", translationMarkdown: nil)
        )
    }

    @Test("retrying a failed replacement save reuses its history identity")
    func retryingReplacementSaveReusesHistoryIdentity() async throws {
        let history = RunnerHistoryProbe()
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(runs: [.text("Original result"), .text("Replacement result")])
        )
        _ = try await extract(on: runner)
        await history.setFailsSuccessfulFinish(true)

        let rerunEvents = try await extract(on: runner)
        guard case let .resultPersistenceFailed(unsaved, _) = rerunEvents.last else {
            Issue.record("Expected the replacement result to remain unsaved")
            return
        }
        await history.setFailsSuccessfulFinish(false)

        let saved = try await runner.retrySavingResult()

        #expect(saved == unsaved)
        #expect(await history.operations == [.extractText])
        #expect(await history.currentOutcomes.count == 1)
        #expect(
            await history.currentOutcomes.values.first
                == .succeeded(sourceMarkdown: "Replacement result", translationMarkdown: nil)
        )
    }

    @Test("a stream without completion persists failure instead of remaining in flight")
    func incompleteStreamPersistsFailure() async throws {
        let history = RunnerHistoryProbe()
        let runner = makeRunner(history: history, provider: RunnerProviderProbe(events: [.sourceDelta("Partial")]))

        await #expect(throws: OperationWorkspaceRunFailure(code: "incomplete_response")) {
            _ = try await extract(on: runner)
        }

        #expect(await history.outcomes == [.failed(normalizedErrorCode: "incomplete_response")])
    }

    @Test("a provider cancellation persists canceled instead of failed")
    func providerCancellationPersistsCanceled() async throws {
        let history = RunnerHistoryProbe()
        let runner = makeRunner(history: history, provider: RunnerProviderProbe(error: ProviderAdapterError.cancelled))

        await #expect(throws: CancellationError.self) {
            _ = try await extract(on: runner)
        }

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty)
    }

    @Test("a failed or canceled first history preparation rolls back and forgets the screenshot", arguments: [false, true])
    func failedFirstPreparationRollsBackScreenshot(canceled: Bool) async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe(preparationError: canceled ? CancellationError() : RunnerProbeError.failed)
        let provider = RunnerProviderProbe()
        let runner = makeRunner(screenshotStore: screenshotStore, history: history, provider: provider)

        let error = await #expect(throws: (any Error).self) {
            _ = try await extract(on: runner)
        }
        if canceled {
            #expect(error is CancellationError)
        } else {
            #expect(error as? OperationWorkspaceRunFailure == OperationWorkspaceRunFailure(code: "operation_failed"))
        }
        #expect(await screenshotStore.discardCount == 1)
        #expect(await provider.streamCount == 0)

        await history.setPreparationError(nil)
        _ = try await extract(on: runner)

        #expect(await screenshotStore.saveCount == 2)
        #expect(await provider.streamCount == 1)
    }

    @Test("retrying final persistence does not start another provider stream")
    func retryFinalPersistenceDoesNotCallProvider() async throws {
        let history = RunnerHistoryProbe(failsSuccessfulFinish: true)
        let provider = RunnerProviderProbe()
        let runner = makeRunner(history: history, provider: provider)

        let events = try await extract(on: runner)
        guard case let .resultPersistenceFailed(unsaved, _) = events.last else {
            Issue.record("Expected an unsaved completed result")
            return
        }

        await history.setFailsSuccessfulFinish(false)
        let saved = try await runner.retrySavingResult()

        #expect(saved == unsaved)
        #expect(await provider.streamCount == 1)
    }

    @Test("a persisted operation reaches the provider with its image, record and selection")
    func persistedOperationReachesProvider() async throws {
        let provider = RunnerProviderProbe()
        let runner = makeRunner(provider: provider)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")

        _ = try await collect(await runner.run(originalPNG: png, operation: .extractText, selection: selection))

        #expect(await provider.originalPNGs == [png])
        let prepared = try #require(await provider.preparedOperations.first)
        #expect(prepared.selection == selection)
        #expect(prepared.operation == .extractText)
        #expect(prepared.screenshot == ManagedScreenshot(path: "/Pictures/shared.png", sha256: "sha"))
    }

    @Test(
        "a prepared record with another screenshot or selection never reaches the provider and is rolled back",
        arguments: [RunnerHistoryProbe.Mismatch.screenshot, .selection]
    )
    func mismatchedPreparationNeverReachesProvider(mismatch: RunnerHistoryProbe.Mismatch) async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let provider = RunnerProviderProbe()
        let runner = makeRunner(screenshotStore: screenshotStore, history: RunnerHistoryProbe(mismatch: mismatch), provider: provider)

        await #expect(throws: OperationWorkspaceRunFailure(code: "history_inconsistent")) {
            _ = try await extract(on: runner)
        }

        #expect(await provider.streamCount == 0)
        #expect(await screenshotStore.discardCount == 1)
    }
}
