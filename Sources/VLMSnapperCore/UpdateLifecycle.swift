import Foundation

public struct AvailableUpdateVersion: Equatable, Sendable {
    public let version: String
    public let displayVersion: String
    public let informationURL: URL?

    public init(
        version: String,
        displayVersion: String,
        informationURL: URL? = nil
    ) {
        self.version = version
        self.displayVersion = displayVersion
        self.informationURL = informationURL
    }
}

public enum UpdateFailureOperation: String, Equatable, Sendable {
    case startup
    case check
    case download
    case install
}

public enum UpdateLifecycleState: Equatable, Sendable {
    case idle
    case checking
    case current(lastCheckedAt: Date?)
    case available(AvailableUpdateVersion)
    case downloading(
        AvailableUpdateVersion,
        receivedBytes: UInt64,
        expectedBytes: UInt64?
    )
    case readyToInstall(AvailableUpdateVersion)
    case failed(UpdateFailureOperation, code: String)
}

public extension UpdateLifecycleState {
    var showsAttentionIndicator: Bool {
        switch self {
        case .available, .downloading, .readyToInstall: true
        default: false
        }
    }
}

public enum UpdateLifecycleEvent: Equatable, Sendable {
    case checking
    case current(lastCheckedAt: Date?)
    case available(AvailableUpdateVersion)
    case downloadStarted(AvailableUpdateVersion)
    case downloadExpectedBytes(UInt64)
    case downloadedBytes(UInt64)
    case readyToInstall(AvailableUpdateVersion)
    case failed(UpdateFailureOperation, code: String)
}

public struct UpdateDriverConfiguration: Equatable, Sendable {
    public let automaticallyChecks: Bool
    public let checkIntervalSeconds: TimeInterval
    public let allowsAutomaticDownloads: Bool

    public init(
        automaticallyChecks: Bool,
        checkIntervalSeconds: TimeInterval,
        allowsAutomaticDownloads: Bool
    ) {
        self.automaticallyChecks = automaticallyChecks
        self.checkIntervalSeconds = checkIntervalSeconds
        self.allowsAutomaticDownloads = allowsAutomaticDownloads
    }
}

public protocol UpdateDriving: Sendable {
    func start(configuration: UpdateDriverConfiguration) async throws
    func setAutomaticallyChecks(_ enabled: Bool) async throws
    func checkForUpdates() async throws
    func beginDownload() async throws
    func installNow() async throws
}

public actor UpdateLifecycleCoordinator {
    public static let checkIntervalSeconds: TimeInterval = 21_600

    private let driver: any UpdateDriving
    private var state: UpdateLifecycleState = .idle
    private var downloadRequestInFlight = false

    public init(driver: any UpdateDriving) {
        self.driver = driver
    }

    public func start(automaticallyChecks: Bool = true) async throws {
        do {
            try await driver.start(
                configuration: UpdateDriverConfiguration(
                    automaticallyChecks: automaticallyChecks,
                    checkIntervalSeconds: Self.checkIntervalSeconds,
                    allowsAutomaticDownloads: false
                )
            )
        } catch {
            state = .failed(.startup, code: "updater_start_failed")
            throw error
        }
    }

    public func snapshot() -> UpdateLifecycleState {
        state
    }

    public func setAutomaticallyChecks(_ enabled: Bool) async throws {
        try await driver.setAutomaticallyChecks(enabled)
    }

    public func checkForUpdates() async throws {
        try await driver.checkForUpdates()
    }

    @discardableResult
    public func requestDownload() async throws -> Bool {
        guard case let .available(version) = state,
              version.informationURL == nil,
              !downloadRequestInFlight else { return false }
        downloadRequestInFlight = true
        do {
            try await driver.beginDownload()
            return true
        } catch {
            downloadRequestInFlight = false
            state = .failed(.download, code: "download_start_failed")
            throw error
        }
    }

    @discardableResult
    public func requestImmediateInstall() async throws -> Bool {
        guard case .readyToInstall = state else { return false }
        do {
            try await driver.installNow()
            return true
        } catch {
            state = .failed(.install, code: "install_start_failed")
            throw error
        }
    }

    public func handle(_ event: UpdateLifecycleEvent) {
        switch event {
        case .checking:
            state = .checking
        case let .current(lastCheckedAt):
            downloadRequestInFlight = false
            state = .current(lastCheckedAt: lastCheckedAt)
        case let .available(version):
            downloadRequestInFlight = false
            state = .available(version)
        case let .downloadStarted(version):
            state = .downloading(version, receivedBytes: 0, expectedBytes: nil)
        case let .downloadExpectedBytes(expectedBytes):
            guard case let .downloading(version, receivedBytes, _) = state else { return }
            state = .downloading(
                version,
                receivedBytes: receivedBytes,
                expectedBytes: expectedBytes
            )
        case let .downloadedBytes(length):
            guard case let .downloading(version, receivedBytes, expectedBytes) = state else {
                return
            }
            state = .downloading(
                version,
                receivedBytes: receivedBytes.addingReportingOverflow(length).overflow
                    ? UInt64.max
                    : receivedBytes + length,
                expectedBytes: expectedBytes
            )
        case let .readyToInstall(version):
            downloadRequestInFlight = false
            state = .readyToInstall(version)
        case let .failed(operation, code):
            downloadRequestInFlight = false
            state = .failed(operation, code: code)
        }
    }
}
