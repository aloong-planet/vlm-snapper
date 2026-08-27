import Darwin
import Foundation
import VLMSnapperProcessShim

public enum PrimaryInstanceRole: Equatable, Sendable {
    case primary
    case secondary
}

public protocol PrimaryInstanceLease: AnyObject, Sendable {}

public protocol PrimaryInstanceLocking: Sendable {
    func acquire() async throws -> (any PrimaryInstanceLease)?
}

public protocol PrimaryInstanceMessaging: Sendable {
    func beginObserving(
        _ handler: @escaping @Sendable () async -> Void
    ) async
    func requestActivation() async
}

public actor PrimaryInstanceCoordinator {
    private let lock: any PrimaryInstanceLocking
    private let messaging: any PrimaryInstanceMessaging
    private var lease: (any PrimaryInstanceLease)?
    private var role: PrimaryInstanceRole?

    public init(
        lock: any PrimaryInstanceLocking,
        messaging: any PrimaryInstanceMessaging
    ) {
        self.lock = lock
        self.messaging = messaging
    }

    public func start(
        onActivation: @escaping @Sendable () async -> Void,
        initializePrimary: @escaping @Sendable () async throws -> Void
    ) async throws -> PrimaryInstanceRole {
        if let role { return role }
        guard let acquiredLease = try await lock.acquire() else {
            await messaging.requestActivation()
            role = .secondary
            return .secondary
        }

        lease = acquiredLease
        await messaging.beginObserving(onActivation)
        do {
            try await initializePrimary()
            role = .primary
            return .primary
        } catch {
            lease = nil
            throw error
        }
    }
}

public enum POSIXPrimaryInstanceLockError: Error, Equatable {
    case createDirectory
    case open(Int32)
    case lock(Int32)
}

public struct POSIXPrimaryInstanceLock: PrimaryInstanceLocking {
    private let lockFileURL: URL

    public init(lockFileURL: URL) {
        self.lockFileURL = lockFileURL
    }

    public func acquire() throws -> (any PrimaryInstanceLease)? {
        do {
            try FileManager.default.createDirectory(
                at: lockFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw POSIXPrimaryInstanceLockError.createDirectory
        }
        let descriptor = Darwin.open(
            lockFileURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw POSIXPrimaryInstanceLockError.open(errno)
        }
        var lockError: Int32 = 0
        guard VLMSnapperTryLockFileDescriptor(descriptor, &lockError) else {
            Darwin.close(descriptor)
            if lockError == EWOULDBLOCK { return nil }
            throw POSIXPrimaryInstanceLockError.lock(lockError)
        }
        return POSIXPrimaryInstanceFileLease(descriptor: descriptor)
    }
}

private final class POSIXPrimaryInstanceFileLease: PrimaryInstanceLease, @unchecked Sendable {
    private let descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        VLMSnapperUnlockFileDescriptor(descriptor)
        Darwin.close(descriptor)
    }
}
