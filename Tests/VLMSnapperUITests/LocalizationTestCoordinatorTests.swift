import Dispatch
import Testing
@testable import VLMSnapperUI

@Suite("Localization test coordination")
struct LocalizationTestCoordinatorTests {
    @Test("localization test sections cannot overlap")
    func localizationTestSectionsCannotOverlap() throws {
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            LocalizationTestCoordinator.withExclusiveAccess {
                firstEntered.signal()
                releaseFirst.wait()
            }
            firstFinished.signal()
        }
        defer { releaseFirst.signal() }
        try #require(firstEntered.wait(timeout: .now() + 15) == .success)

        DispatchQueue.global().async {
            _ = LocalizationTestCoordinator.withExclusiveAccess {
                secondEntered.signal()
            }
            secondFinished.signal()
        }

        let secondEntryBeforeRelease = secondEntered.wait(timeout: .now() + 0.1)
        #expect(secondEntryBeforeRelease == .timedOut)
        releaseFirst.signal()
        try #require(firstFinished.wait(timeout: .now() + 5) == .success)
        if secondEntryBeforeRelease == .timedOut {
            try #require(secondEntered.wait(timeout: .now() + 5) == .success)
        }
        try #require(secondFinished.wait(timeout: .now() + 5) == .success)
        #expect(VLMSnapperStrings.updateAutomaticChecks == "自动检查更新")
    }
}
