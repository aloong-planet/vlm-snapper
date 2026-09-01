import Foundation
import VLMSnapperCore

enum ApplicationDirectories {
    static func applicationSupportRoot(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("VLMSnapper", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func screenshotRoot(
        fileManager: FileManager = .default
    ) throws -> URL {
        let pictures = try fileManager.url(
            for: .picturesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return ManagedScreenshotRoot.directURL(for: pictures)
    }
}
