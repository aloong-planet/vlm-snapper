import Foundation
import Testing
@testable import VLMSnapperCore

@Suite("Update lifecycle")
struct UpdateLifecycleCoordinatorTests {
    @Test("Startup fixes the six hour schedule and disables automatic downloads")
    func startupConfiguration() async throws {
        let driver = UpdateDriverProbe()
        let coordinator = UpdateLifecycleCoordinator(driver: driver)

        try await coordinator.start()

        #expect(
            await driver.configurations == [
                UpdateDriverConfiguration(
                    automaticallyChecks: true,
                    checkIntervalSeconds: 21_600,
                    allowsAutomaticDownloads: false
                ),
            ]
        )
    }

    @Test("Download intent waits for driver events and is consumed once")
    func downloadIntentWaitsForEvents() async throws {
        let driver = UpdateDriverProbe()
        let coordinator = UpdateLifecycleCoordinator(driver: driver)
        let version = AvailableUpdateVersion(version: "101", displayVersion: "1.1.0")
        await coordinator.handle(.available(version))

        #expect(try await coordinator.requestDownload())
        #expect(await coordinator.snapshot() == .available(version))
        #expect(try await coordinator.requestDownload() == false)
        #expect(await driver.downloadRequests == 1)

        await coordinator.handle(.downloadStarted(version))
        #expect(
            await coordinator.snapshot() == .downloading(
                version,
                receivedBytes: 0,
                expectedBytes: nil
            )
        )
        await coordinator.handle(.downloadExpectedBytes(1_000))
        await coordinator.handle(.downloadedBytes(400))
        #expect(
            await coordinator.snapshot() == .downloading(
                version,
                receivedBytes: 400,
                expectedBytes: 1_000
            )
        )
        await coordinator.handle(.readyToInstall(version))
        #expect(await coordinator.snapshot() == .readyToInstall(version))
    }

    @Test("Failed download never reports ready and permits explicit retry")
    func failedDownloadPermitsRetry() async throws {
        let driver = UpdateDriverProbe()
        let coordinator = UpdateLifecycleCoordinator(driver: driver)
        let version = AvailableUpdateVersion(version: "101", displayVersion: "1.1.0")
        await coordinator.handle(.available(version))
        _ = try await coordinator.requestDownload()
        await coordinator.handle(.failed(.download, code: "transport"))

        #expect(await coordinator.snapshot() == .failed(.download, code: "transport"))

        await coordinator.handle(.available(version))
        #expect(try await coordinator.requestDownload())
        #expect(await driver.downloadRequests == 2)
    }

    @Test("Information-only updates never begin a download")
    func informationOnlyUpdateDoesNotDownload() async throws {
        let driver = UpdateDriverProbe()
        let coordinator = UpdateLifecycleCoordinator(driver: driver)
        let version = AvailableUpdateVersion(
            version: "200",
            displayVersion: "2.0",
            informationURL: URL(string: "https://example.com/update")
        )
        await coordinator.handle(.available(version))

        #expect(try await coordinator.requestDownload() == false)
        #expect(await driver.downloadRequests == 0)
    }
}

private actor UpdateDriverProbe: UpdateDriving {
    private(set) var configurations: [UpdateDriverConfiguration] = []
    private(set) var downloadRequests = 0

    func start(configuration: UpdateDriverConfiguration) async throws {
        configurations.append(configuration)
    }

    func setAutomaticallyChecks(_ enabled: Bool) async throws {}
    func checkForUpdates() async throws {}

    func beginDownload() async throws {
        downloadRequests += 1
    }

    func installNow() async throws {}
}
