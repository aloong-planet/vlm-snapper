import Foundation
import Sparkle
import VLMSnapperCore

public enum SparkleUpdateDriverError: Error, Equatable {
    case failedToStart
    case noDownloadAvailable
    case noInstallAvailable
    case informationOnlyUpdate
}

@MainActor
public final class SparkleUpdateDriver: UpdateDriving, @unchecked Sendable {
    public typealias EventHandler = @Sendable (UpdateLifecycleEvent) async -> Void

    private let updater: SPUUpdater
    private let userDriver: SparkleProductUserDriver

    public init(
        hostBundle: Bundle = .main,
        applicationBundle: Bundle = .main,
        eventHandler: @escaping EventHandler
    ) {
        let userDriver = SparkleProductUserDriver(eventHandler: eventHandler)
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: applicationBundle,
            userDriver: userDriver,
            delegate: nil
        )
    }

    public func start(configuration: UpdateDriverConfiguration) async throws {
        userDriver.automaticallyChecks = configuration.automaticallyChecks
        updater.automaticallyChecksForUpdates = configuration.automaticallyChecks
        updater.updateCheckInterval = configuration.checkIntervalSeconds
        updater.automaticallyDownloadsUpdates = configuration.allowsAutomaticDownloads
        try updater.start()
    }

    public func setAutomaticallyChecks(_ enabled: Bool) async throws {
        userDriver.automaticallyChecks = enabled
        updater.automaticallyChecksForUpdates = enabled
    }

    public func checkForUpdates() async throws {
        updater.checkForUpdates()
    }

    public func beginDownload() async throws {
        try userDriver.beginDownload()
    }

    public func installNow() async throws {
        try userDriver.installNow()
    }
}

@MainActor
final class SparkleProductUserDriver: NSObject, SPUUserDriver {
    private let eventHandler: SparkleUpdateDriver.EventHandler
    var automaticallyChecks = true
    private var availableVersion: AvailableUpdateVersion?
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var informationURL: URL?
    private var currentOperation: UpdateFailureOperation = .check
    private var eventDeliveryTask: Task<Void, Never>?

    init(eventHandler: @escaping SparkleUpdateDriver.EventHandler) {
        self.eventHandler = eventHandler
    }

    func beginDownload() throws {
        guard informationURL == nil else {
            throw SparkleUpdateDriverError.informationOnlyUpdate
        }
        guard let reply = foundReply else {
            throw SparkleUpdateDriverError.noDownloadAvailable
        }
        foundReply = nil
        currentOperation = .download
        reply(.install)
    }

    func installNow() throws {
        guard let reply = installReply else {
            throw SparkleUpdateDriverError.noInstallAvailable
        }
        installReply = nil
        currentOperation = .install
        reply(.install)
    }

    func registerFoundUpdate(
        version: AvailableUpdateVersion,
        informationURL: URL?,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let publishedVersion = AvailableUpdateVersion(
            version: version.version,
            displayVersion: version.displayVersion,
            informationURL: informationURL
        )
        availableVersion = publishedVersion
        currentOperation = .check
        self.informationURL = informationURL
        foundReply = informationURL == nil ? reply : nil
        publish(.available(publishedVersion))
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: automaticallyChecks,
                automaticUpdateDownloading: false,
                sendSystemProfile: false
            )
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        currentOperation = .check
        publish(.checking)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let version = AvailableUpdateVersion(
            version: appcastItem.versionString,
            displayVersion: appcastItem.displayVersionString,
            informationURL: appcastItem.isInformationOnlyUpdate ? appcastItem.infoURL : nil
        )
        registerFoundUpdate(
            version: version,
            informationURL: version.informationURL,
            reply: reply
        )
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        publish(.current(lastCheckedAt: Date()))
        acknowledgement()
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        publish(.failed(currentOperation, code: "updater_failed"))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        if let availableVersion { publish(.downloadStarted(availableVersion)) }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        publish(.downloadExpectedBytes(expectedContentLength))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        publish(.downloadedBytes(length))
    }

    func showDownloadDidStartExtractingUpdate() {}

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(
        toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        installReply = reply
        if let availableVersion { publish(.readyToInstall(availableVersion)) }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        foundReply = nil
        installReply = nil
        informationURL = nil
        availableVersion = nil
    }

    private func publish(_ event: UpdateLifecycleEvent) {
        let previous = eventDeliveryTask
        eventDeliveryTask = Task {
            await previous?.value
            await eventHandler(event)
        }
    }

    func waitForPendingEvents() async {
        await eventDeliveryTask?.value
    }
}
