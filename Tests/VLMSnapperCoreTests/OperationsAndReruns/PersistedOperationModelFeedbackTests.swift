import Foundation
import Testing
@testable import VLMSnapperCore

// What a request's outcome tells the model's records: its vision compatibility and the model list.
extension PersistedOperationWorkspaceRunnerTests {
    @Test("a model that rejects images is recorded, and the failure still reaches the caller")
    func rejectedImageIsRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: ProviderAdapterError.imageInputUnsupported),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "image_input_unsupported")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls == [.failure(.deepSeek, "vision", .imageInputUnsupported)])
    }

    @Test(
        "another failure says nothing about the model's image input",
        arguments: [
            ProviderAdapterError.invalidRequest,
            ProviderAdapterError.imageTooLarge,
            ProviderAdapterError.modelUnavailable,
        ]
    )
    func otherFailureIsNotRecorded(error: ProviderAdapterError) async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: error),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: error.normalizedCode)) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls.isEmpty)
    }

    @Test("a successful result records the model as verified, once")
    func successIsRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(),
            visionCompatibility: recorder
        )

        _ = try await collect(
            await runner.run(
                originalPNG: Data([1]),
                operation: .extractText,
                selection: ProviderSelection(providerID: "gemini", modelID: "vision")
            )
        )

        #expect(await recorder.calls == [.success(.gemini, "vision")])
    }

    @Test("a stream that completes without text does not verify the model")
    func emptyCompletionIsNotRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(events: [
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)),
                .completed,
            ]),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "incomplete_response")) {
            _ = try await collect(
                await runner.run(
                    originalPNG: Data([1]),
                    operation: .extractText,
                    selection: ProviderSelection(providerID: "gemini", modelID: "vision")
                )
            )
        }

        #expect(await recorder.calls.isEmpty)
    }

    @Test("failing to record changes neither a failure nor a success")
    func recorderFailureChangesNoOutcome() async throws {
        let recorder = RunnerVisionRecorderProbe(fails: true)
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        let failing = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: ProviderAdapterError.imageInputUnsupported),
            visionCompatibility: recorder
        )
        await #expect(throws: OperationWorkspaceRunFailure(code: "image_input_unsupported")) {
            _ = try await collect(await failing.run(originalPNG: Data([1]), operation: .extractText, selection: selection))
        }

        let succeeding = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(),
            visionCompatibility: recorder
        )
        let events = try await collect(
            await succeeding.run(originalPNG: Data([1]), operation: .extractText, selection: selection)
        )

        #expect(events.contains { if case .succeeded = $0 { true } else { false } })
        #expect(await recorder.calls == [
            .failure(.gemini, "vision", .imageInputUnsupported),
            .success(.gemini, "vision"),
        ])
    }

    @Test("a model-unavailable error refreshes the list once, and the failure reaches the caller")
    func modelUnavailableRefreshesOnce() async throws {
        let refresh = RunnerModelListProbe()
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable)
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: provider,
            modelListRefresh: refresh
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await collect(await runner.run(
                originalPNG: Data([1]), operation: .extractText,
                selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
            ))
        }

        #expect(await refresh.providers == [.deepSeek])
        #expect(await provider.streamCount == 1)
        #expect(await history.outcomes == [.failed(normalizedErrorCode: "model_unavailable")])
    }

    @Test(
        "another failure refreshes nothing",
        arguments: [
            ProviderAdapterError.invalidRequest,
            ProviderAdapterError.imageInputUnsupported,
            ProviderAdapterError.rateLimited(retryAfterSeconds: 60),
        ]
    )
    func otherFailureDoesNotRefresh(error: ProviderAdapterError) async throws {
        let refresh = RunnerModelListProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: error),
            modelListRefresh: refresh
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: error.normalizedCode)) {
            _ = try await collect(await runner.run(
                originalPNG: Data([1]), operation: .extractText,
                selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
            ))
        }

        #expect(await refresh.providers.isEmpty)
    }

    @Test("a successful result refreshes nothing")
    func successDoesNotRefresh() async throws {
        let refresh = RunnerModelListProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(),
            modelListRefresh: refresh
        )

        _ = try await collect(await runner.run(
            originalPNG: Data([1]), operation: .extractText,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
        ))

        #expect(await refresh.providers.isEmpty)
    }

    /// A press right after the failure must already find no model (v1-core failure mode 56).
    @Test("a request is not over until its refresh ends")
    func requestWaitsForRefresh() async throws {
        let refresh = RunnerModelListProbe(suspends: true)
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh
        )
        let events = await runner.run(
            originalPNG: Data([1]), operation: .extractText,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
        )
        let ended = RunnerEndFlag()
        let consumer = Task {
            do { for try await _ in events {} } catch {
                await ended.mark()
                throw error
            }
            await ended.mark()
        }

        await refresh.waitUntilCalled()
        // A failure sent before the refresh would reach the consumer in this time.
        try await Task.sleep(for: .milliseconds(50))
        #expect(await !ended.value)
        #expect(await history.outcomes.isEmpty)

        await refresh.finish()
        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) { try await consumer.value }
        #expect(await history.outcomes == [.failed(normalizedErrorCode: "model_unavailable")])
    }

    @Test("a failed refresh changes no outcome")
    func failedRefreshChangesNoOutcome() async throws {
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: RunnerModelListProbe(fails: true)
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await collect(await runner.run(
                originalPNG: Data([1]), operation: .extractText,
                selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
            ))
        }

        #expect(await history.outcomes == [.failed(normalizedErrorCode: "model_unavailable")])
    }

    @Test("canceling during the refresh records a cancel, not the failure")
    func cancelingDuringRefreshRecordsCanceled() async throws {
        let refresh = RunnerModelListProbe(suspends: true)
        let history = RunnerHistoryProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh
        )
        let events = await runner.run(
            originalPNG: Data([1]), operation: .extractText,
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision")
        )
        let consumer = Task { for try await _ in events {} }
        await refresh.waitUntilCalled()

        consumer.cancel()
        _ = try? await consumer.value
        await runner.waitForRunToFinish()

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty)
    }

    @Test("a retry of a saved record refreshes the list and leaves the record")
    func restoredRecordRefreshesAndKeepsItsResult() async throws {
        let screenshotStore = RunnerScreenshotStoreProbe()
        let history = RunnerHistoryProbe()
        let png = Data([7])
        let screenshot = try await screenshotStore.save(originalPNG: png)
        let selection = ProviderSelection(providerID: "gemini", modelID: "vision")
        let prepared = try await history.prepareOperation(
            screenshot: screenshot, selection: selection, operation: .extractText
        )
        let stored = try #require(try await history.operation(id: prepared.operationID))
        let refresh = RunnerModelListProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: screenshotStore,
            historyStore: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh,
            restoring: stored
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await collect(await runner.run(originalPNG: png, operation: .extractText, selection: selection))
        }

        #expect(await refresh.providers == [.gemini])
        #expect(await history.outcomes.isEmpty)
        #expect(await history.currentOutcomes.isEmpty)
    }

    @Test("a Provider the app does not know refreshes nothing")
    func unknownProviderDoesNotRefresh() async throws {
        let refresh = RunnerModelListProbe()
        let runner = PersistedOperationWorkspaceRunner(
            screenshotStore: RunnerScreenshotStoreProbe(),
            historyStore: RunnerHistoryProbe(),
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await collect(await runner.run(
                originalPNG: Data([1]), operation: .extractText,
                selection: ProviderSelection(providerID: "retired-provider", modelID: "vision")
            ))
        }

        #expect(await refresh.providers.isEmpty)
    }
}
