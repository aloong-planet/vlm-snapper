import Foundation
import Testing
@testable import VLMSnapperCore

// What a request's outcome tells the model's records: its vision compatibility and the model list.
extension PersistedOperationWorkspaceRunnerTests {
    /// Each failure, the code that reaches the caller, and what the recorder should get.
    static let failuresForTheRecorder: [(ProviderAdapterError, String, [RunnerVisionRecorderProbe.Call])] = [
        (.imageInputUnsupported, "image_input_unsupported", [.failure(.deepSeek, "vision", .imageInputUnsupported)]),
        (.invalidRequest, "invalid_request", []),
        (.imageTooLarge, "image_too_large", []),
        (.modelUnavailable, "model_unavailable", []),
    ]

    @Test("only a model that rejects images is recorded, and the failure still reaches the caller", arguments: failuresForTheRecorder)
    func onlyARejectedImageIsRecorded(
        error: ProviderAdapterError,
        code: String,
        calls: [RunnerVisionRecorderProbe.Call]
    ) async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = makeRunner(provider: RunnerProviderProbe(error: error), visionCompatibility: recorder)

        await #expect(throws: OperationWorkspaceRunFailure(code: code)) {
            _ = try await extract(on: runner)
        }

        #expect(await recorder.calls == calls)
    }

    @Test("a successful result records the model as verified, once, and refreshes nothing")
    func successIsRecordedAndRefreshesNothing() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let refresh = RunnerModelListProbe()
        let runner = makeRunner(visionCompatibility: recorder, modelListRefresh: refresh)

        _ = try await extract(on: runner, providerID: "gemini")

        #expect(await recorder.calls == [.success(.gemini, "vision")])
        #expect(await refresh.providers.isEmpty)
    }

    @Test("a stream that completes without text does not verify the model")
    func emptyCompletionIsNotRecorded() async throws {
        let recorder = RunnerVisionRecorderProbe()
        let runner = makeRunner(
            provider: RunnerProviderProbe(events: [
                .metadata(ProviderResponseMetadata(requestID: nil, usage: nil)),
                .completed,
            ]),
            visionCompatibility: recorder
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "incomplete_response")) {
            _ = try await extract(on: runner, providerID: "gemini")
        }

        #expect(await recorder.calls.isEmpty)
    }

    @Test("failing to record changes neither a failure nor a success")
    func recorderFailureChangesNoOutcome() async throws {
        let recorder = RunnerVisionRecorderProbe(fails: true)
        let failing = makeRunner(provider: RunnerProviderProbe(error: ProviderAdapterError.imageInputUnsupported), visionCompatibility: recorder)
        await #expect(throws: OperationWorkspaceRunFailure(code: "image_input_unsupported")) {
            _ = try await extract(on: failing, providerID: "gemini")
        }

        let succeeding = makeRunner(visionCompatibility: recorder)
        let events = try await extract(on: succeeding, providerID: "gemini")

        #expect(events.contains { if case .succeeded = $0 { true } else { false } })
        #expect(await recorder.calls == [
            .failure(.gemini, "vision", .imageInputUnsupported),
            .success(.gemini, "vision"),
        ])
    }

    @Test(
        "a model-unavailable error refreshes the list once, and the failure reaches the caller whether or not the refresh works",
        arguments: [false, true]
    )
    func modelUnavailableRefreshesOnce(refreshFails: Bool) async throws {
        let refresh = RunnerModelListProbe(fails: refreshFails)
        let history = RunnerHistoryProbe()
        let provider = RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable)
        let runner = makeRunner(history: history, provider: provider, modelListRefresh: refresh)

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await extract(on: runner)
        }

        #expect(await refresh.providers == [.deepSeek])
        #expect(await provider.streamCount == 1)
        #expect(await history.outcomes == [.failed(normalizedErrorCode: "model_unavailable")])
    }

    /// Each failure, the Provider it came from, and the code that reaches the caller.
    static let failuresWithoutARefresh: [(ProviderAdapterError, String, String)] = [
        (.invalidRequest, "deepseek", "invalid_request"),
        (.imageInputUnsupported, "deepseek", "image_input_unsupported"),
        (.rateLimited(retryAfterSeconds: 60), "deepseek", "rate_limited"),
        (.modelUnavailable, "retired-provider", "model_unavailable"),
    ]

    @Test("another failure, or a Provider the app does not know, refreshes nothing", arguments: failuresWithoutARefresh)
    func otherFailureDoesNotRefresh(error: ProviderAdapterError, providerID: String, code: String) async throws {
        let refresh = RunnerModelListProbe()
        let runner = makeRunner(provider: RunnerProviderProbe(error: error), modelListRefresh: refresh)

        await #expect(throws: OperationWorkspaceRunFailure(code: code)) {
            _ = try await extract(on: runner, providerID: providerID)
        }

        #expect(await refresh.providers.isEmpty)
    }

    /// A press right after the failure must already find no model (v1-core failure mode 56).
    @Test("a request is not over until its refresh ends")
    func requestWaitsForRefresh() async throws {
        let refresh = RunnerModelListProbe(suspends: true)
        let history = RunnerHistoryProbe()
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh
        )
        let ended = RunnerEndFlag()
        let consumer = Task {
            do { _ = try await extract(on: runner) } catch {
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

    @Test("canceling during the refresh records a cancel, not the failure")
    func cancelingDuringRefreshRecordsCanceled() async throws {
        let refresh = RunnerModelListProbe(suspends: true)
        let history = RunnerHistoryProbe()
        let runner = makeRunner(
            history: history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh
        )
        let consumer = Task { try await extract(on: runner) }
        await refresh.waitUntilCalled()

        consumer.cancel()
        _ = try? await consumer.value
        await runner.waitForRunToFinish()

        #expect(await history.completions == [.canceled])
        #expect(await history.outcomes.isEmpty)
    }

    @Test("a retry of a saved record refreshes the list and leaves the record")
    func restoredRecordRefreshesAndKeepsItsResult() async throws {
        let saved = try await savedRecord(of: .extractText)
        let refresh = RunnerModelListProbe()
        let runner = makeRunner(
            screenshotStore: saved.screenshotStore,
            history: saved.history,
            provider: RunnerProviderProbe(error: ProviderAdapterError.modelUnavailable),
            modelListRefresh: refresh,
            restoring: saved.stored
        )

        await #expect(throws: OperationWorkspaceRunFailure(code: "model_unavailable")) {
            _ = try await extract(on: runner, providerID: "gemini")
        }

        #expect(await refresh.providers == [.gemini])
        #expect(await saved.history.outcomes.isEmpty)
        #expect(await saved.history.currentOutcomes.isEmpty)
    }
}
