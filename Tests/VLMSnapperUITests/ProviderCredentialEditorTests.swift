import Testing
import VLMSnapperCore
import VLMSnapperUI

@Suite("Provider credential editor session")
@MainActor
struct ProviderCredentialEditorTests {
    @Test("editing or removing a failed credential discards its retained candidate", arguments: [false, true])
    func failedCandidateCanBeDiscarded(remove: Bool) throws {
        let editor = ProviderCredentialEditor()
        editor.edit("failed-key")
        var submitted: ProviderCredentialSubmission?
        editor.submit(for: .deepSeek, isReadOnly: false) { submitted = $0 }
        editor.complete(try #require(submitted), succeeded: false)
        if remove {
            let other = editor.beginLoading(for: .openAI)
            editor.completeLoad(other, value: "other-key")
            editor.configurationWasRemoved(for: .deepSeek)
        } else {
            editor.edit("replacement-draft")
        }
        editor.close()
        let reopened = editor.beginLoading(for: .deepSeek)
        #expect(editor.value.isEmpty)
        #expect(editor.isLoading)
        editor.completeLoad(reopened, value: "")
        #expect(!editor.isDirty)
    }

    @Test("a validation that fails while closed restores its candidate when reopened")
    func closedFailureRetainsCandidate() throws {
        let editor = ProviderCredentialEditor(loadedValue: "old-key")
        editor.edit("failed-candidate")
        var submitted: ProviderCredentialSubmission?
        editor.submit(for: .deepSeek, isReadOnly: false) { submitted = $0 }
        editor.close()
        editor.complete(try #require(submitted), succeeded: false)
        let reopened = editor.beginLoading(for: .deepSeek)
        #expect(editor.value == "failed-candidate")
        #expect(!editor.isLoading)
        #expect(!editor.isSubmitting)
        #expect(editor.isDirty)
        editor.completeLoad(reopened, value: "obsolete-key")
        #expect(editor.value == "failed-candidate")
    }

    @Test("closing discards a draft and invalidates pending reads")
    func closeInvalidatesReads() {
        let editor = ProviderCredentialEditor(loadedValue: "old-key")
        editor.edit("unsaved-key")
        editor.close()
        #expect(editor.value.isEmpty)
        #expect(!editor.isDirty)
        let oldRead = editor.beginLoading(for: .deepSeek)
        editor.close()
        let newRead = editor.beginLoading(for: .deepSeek)
        editor.completeLoad(oldRead, value: "stale-key")
        #expect(editor.value.isEmpty)
        #expect(editor.isLoading)
        editor.edit("too-early")
        #expect(editor.value.isEmpty)
        editor.completeLoad(newRead, value: "current-key")
        #expect(editor.value == "current-key")
        #expect(!editor.isLoading)
        #expect(!editor.isDirty)
    }

    @Test("closing does not cancel submission or resurrect a closed draft", arguments: [false, true])
    func closingSubmittedDraft(reopenBeforeCompletion: Bool) throws {
        let editor = ProviderCredentialEditor(loadedValue: "old-key")
        editor.edit("candidate-key")
        var submitted: ProviderCredentialSubmission?
        editor.submit(for: .deepSeek, isReadOnly: false) { submitted = $0 }
        let request = try #require(submitted)
        editor.close()
        #expect(editor.value.isEmpty)
        #expect(!editor.isOpen)
        if reopenBeforeCompletion {
            let read = editor.beginLoading(for: .deepSeek)
            editor.completeLoad(read, value: "obsolete-storage-value")
            #expect(editor.value == "candidate-key")
            #expect(editor.isSubmitting)
            #expect(!editor.submit(for: .deepSeek, isReadOnly: false) { _ in
                Issue.record("Reopening dispatched the same pending request twice")
            })
        }
        editor.complete(request, succeeded: true)
        #expect(editor.value == (reopenBeforeCompletion ? "candidate-key" : ""))
        #expect(!editor.isSubmitting)
        #expect(!editor.isDirty)
    }

    @Test("a submitted key belongs to its Provider after switching cards")
    func submittedKeySurvivesCardSwitch() throws {
        let editor = ProviderCredentialEditor(loadedValue: "old-key")
        editor.edit("candidate-a")
        var requests: [ProviderCredentialSubmission] = []
        editor.submit(for: .deepSeek, isReadOnly: false) { requests.append($0) }
        let submitted = try #require(requests.first)
        let other = editor.beginLoading(for: .openAI)
        editor.completeLoad(other, value: "key-b")
        editor.edit("draft-b")
        #expect(editor.value == "draft-b")
        editor.complete(submitted, succeeded: true)
        #expect(editor.value == "draft-b")
        #expect(editor.isDirty)
        editor.edit("key-b")
        #expect(!editor.isDirty)
    }

    @Test("an older read cannot populate a new visit to the same Provider")
    func lateReadCannotPopulateNewVisit() {
        let editor = ProviderCredentialEditor()
        let first = editor.beginLoading(for: .deepSeek)
        let other = editor.beginLoading(for: .openAI)
        let latest = editor.beginLoading(for: .deepSeek)
        editor.completeLoad(latest, value: "latest-key")
        editor.edit("current-draft")
        editor.completeLoad(other, value: "other-key")
        editor.completeLoad(first, value: "stale-key")
        #expect(editor.value == "current-draft")
        #expect(editor.isDirty)
    }

    @Test("submission is claimed synchronously, with exact immutable input", arguments: [false, true])
    func submissionIdentityAndCompletion(succeeded: Bool) throws {
        let editor = ProviderCredentialEditor(loadedValue: "old-key")
        editor.edit(" candidate\t")
        var requests: [ProviderCredentialSubmission] = []
        #expect(editor.submit(for: .deepSeek, isReadOnly: false, operation: { requests.append($0) }))
        editor.edit("late-edit")
        #expect(!editor.submit(for: .deepSeek, isReadOnly: false, operation: { requests.append($0) }))
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.provider == .deepSeek)
        #expect(request.value == " candidate\t")
        #expect(editor.value == " candidate\t")
        editor.complete(request, succeeded: succeeded)
        #expect(!editor.isSubmitting)
        #expect(editor.isDirty == !succeeded)
        #expect(editor.submit(for: .deepSeek, isReadOnly: false, operation: { requests.append($0) }) == !succeeded)
    }

    @Test("credential baselines compare exact bytes, not Unicode equivalence")
    func baselineUsesExactBytes() {
        let editor = ProviderCredentialEditor(loadedValue: "\u{00e9}")
        #expect(!editor.isDirty)
        editor.edit("e\u{0301}")
        #expect(editor.isDirty)
        editor.edit("\u{00e9}")
        #expect(!editor.isDirty)
        editor.edit(" \u{00e9}\t")
        #expect(editor.isDirty)
    }
}
