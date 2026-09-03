import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Historical workspace snapshot")
struct HistoricalWorkspaceSnapshotTests {
    @Test("a saved translation restores the selected slot and committed text")
    func restoresSavedTranslation() {
        let operation = storedOperation(
            status: .succeeded,
            source: "Original",
            translation: "Translation",
            kind: .translate
        )

        let snapshot = OperationWorkspaceSnapshot(restoring: operation)

        #expect(snapshot.selectedOperation == .translate)
        #expect(snapshot.extract.attempt == .neverStarted)
        #expect(snapshot.translate.attempt == .succeeded)
        #expect(snapshot.translate.committedResult == WorkspaceCommittedResult(
            sourceMarkdown: "Original",
            translationMarkdown: "Translation"
        ))
    }

    @Test("a failed extraction restores its normalized failure")
    func restoresFailedExtraction() {
        let operation = storedOperation(
            status: .failed,
            source: nil,
            translation: nil,
            kind: .extract,
            failure: "rate_limited"
        )

        let snapshot = OperationWorkspaceSnapshot(restoring: operation)

        #expect(snapshot.selectedOperation == .extract)
        #expect(snapshot.extract.attempt == .failed(code: "rate_limited"))
        #expect(snapshot.translate.attempt == .neverStarted)
    }

    @Test("reserving a history replacement closes the start race")
    func reservesHistoryReplacementOnce() async {
        let session = OperationWorkspaceSession(
            originalPNG: Data(),
            runner: HistoricalWorkspaceRunnerProbe(),
            activeGate: ActiveOperationGate()
        )

        #expect(await session.reserveReplacementWithSavedHistory())
        #expect(await !session.reserveReplacementWithSavedHistory())
    }

    private func storedOperation(
        status: OperationStatus,
        source: String?,
        translation: String?,
        kind: PersistedOperationKind,
        failure: String? = nil
    ) -> StoredOperation {
        StoredOperation(
            id: UUID(),
            screenshot: ManagedScreenshot(path: "/Pictures/history.png", sha256: "sha"),
            selection: ProviderSelection(providerID: "deepseek", modelID: "vision"),
            status: status,
            sourceMarkdown: source,
            translationMarkdown: translation,
            normalizedErrorCode: failure,
            kind: kind,
            targetLanguage: kind == .translate ? "en" : nil
        )
    }
}

private actor HistoricalWorkspaceRunnerProbe: OperationWorkspaceRunning {
    func run(
        originalPNG: Data,
        operation: ProviderOperation,
        selection: ProviderSelection
    ) -> AsyncThrowingStream<OperationWorkspaceRunEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
