import CryptoKit
import Foundation

public enum ScreenshotStoreError: Error, Equatable {
    case invalidTimestamp
    case unsafePath
    case ownershipMismatch
    case missingFile
}

public protocol ManagedScreenshotLoading: Sendable {
    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data
}

public actor FileSystemScreenshotStore: ScreenshotPersisting, ManagedScreenshotLoading {
    private let rootDirectory: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        rootDirectory: URL,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.rootDirectory = URL(fileURLWithPath: rootDirectory.standardizedFileURL.path, isDirectory: true)
        self.calendar = calendar
        self.now = now
    }

    public func save(originalPNG: Data) async throws -> ManagedScreenshot {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now()
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let hour = components.hour,
              let minute = components.minute,
              let second = components.second
        else {
            throw ScreenshotStoreError.invalidTimestamp
        }

        try ensureSafeDirectory(at: rootDirectory)
        let monthDirectory = rootDirectory.appendingPathComponent(
            String(format: "%04d-%02d", year, month),
            isDirectory: true
        )
        try ensureSafeDirectory(at: monthDirectory)
        let baseName = String(
            format: "vlmsnapper-%04d%02d%02d-%02d%02d%02d",
            year,
            month,
            day,
            hour,
            minute,
            second
        )
        let temporary = monthDirectory.appendingPathComponent(
            ".vlmsnapper-\(UUID().uuidString).tmp"
        )
        let destination: URL
        do {
            try originalPNG.write(to: temporary, options: .atomic)
            var suffix = 1
            while true {
                let fileName = suffix == 1
                    ? "\(baseName).png"
                    : "\(baseName)-\(suffix).png"
                let candidate = monthDirectory.appendingPathComponent(fileName)
                do {
                    try FileManager.default.moveItem(at: temporary, to: candidate)
                    destination = candidate
                    break
                } catch let error as NSError
                    where error.domain == NSCocoaErrorDomain
                        && error.code == NSFileWriteFileExistsError
                {
                    suffix += 1
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }

        let digest = SHA256.hash(data: originalPNG)
            .map { String(format: "%02x", $0) }
            .joined()
        return ManagedScreenshot(path: destination.path, sha256: digest)
    }

    public func discardIfOwned(_ screenshot: ManagedScreenshot) async throws {
        let file = URL(fileURLWithPath: screenshot.path).standardizedFileURL
        let monthDirectory = file.deletingLastPathComponent()
        guard monthDirectory.deletingLastPathComponent().standardizedFileURL
                == rootDirectory,
              pathContainsNoResolvedSymbolicLink(rootDirectory),
              pathContainsNoResolvedSymbolicLink(monthDirectory),
              pathContainsNoResolvedSymbolicLink(file),
              monthDirectory.lastPathComponent.range(
                of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#,
                options: .regularExpression
              ) != nil,
              file.lastPathComponent.range(
                of: #"^vlmsnapper-[0-9]{8}-[0-9]{6}(-([2-9]|[1-9][0-9]+))?\.png$"#,
                options: .regularExpression
              ) != nil
        else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ScreenshotStoreError.missingFile
        }
        let rootValues = try rootDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let monthValues = try monthDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let fileValues = try file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              monthValues.isDirectory == true,
              monthValues.isSymbolicLink != true,
              fileValues.isRegularFile == true,
              fileValues.isSymbolicLink != true
        else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        let currentData = try Data(contentsOf: file)
        let currentDigest = SHA256.hash(data: currentData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard currentDigest == screenshot.sha256 else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        try FileManager.default.removeItem(at: file)
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: monthDirectory,
            includingPropertiesForKeys: nil
        ), contents.isEmpty {
            try? FileManager.default.removeItem(at: monthDirectory)
        }
    }

    public func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data {
        let file = URL(fileURLWithPath: screenshot.path).standardizedFileURL
        let monthDirectory = file.deletingLastPathComponent()
        guard monthDirectory.deletingLastPathComponent().standardizedFileURL
                == rootDirectory,
              pathContainsNoResolvedSymbolicLink(rootDirectory),
              pathContainsNoResolvedSymbolicLink(monthDirectory),
              pathContainsNoResolvedSymbolicLink(file),
              monthDirectory.lastPathComponent.range(
                of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#,
                options: .regularExpression
              ) != nil,
              file.lastPathComponent.range(
                of: #"^vlmsnapper-[0-9]{8}-[0-9]{6}(-([2-9]|[1-9][0-9]+))?\.png$"#,
                options: .regularExpression
              ) != nil
        else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ScreenshotStoreError.missingFile
        }
        let rootValues = try rootDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let monthValues = try monthDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let fileValues = try file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              monthValues.isDirectory == true,
              monthValues.isSymbolicLink != true,
              fileValues.isRegularFile == true,
              fileValues.isSymbolicLink != true
        else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == screenshot.sha256 else {
            throw ScreenshotStoreError.ownershipMismatch
        }
        return data
    }

    private func ensureSafeDirectory(at directory: URL) throws {
        guard pathContainsNoResolvedSymbolicLink(directory),
              pathContainsNoResolvedSymbolicLink(directory.deletingLastPathComponent())
        else {
            throw ScreenshotStoreError.unsafePath
        }
        do {
            let values = try directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ScreenshotStoreError.unsafePath
            }
        } catch let error as ScreenshotStoreError {
            throw error
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            let values = try directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  pathContainsNoResolvedSymbolicLink(directory)
            else {
                throw ScreenshotStoreError.unsafePath
            }
        }
    }

    private func pathContainsNoResolvedSymbolicLink(_ url: URL) -> Bool {
        url.standardizedFileURL.path
            == url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
