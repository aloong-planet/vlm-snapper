import Foundation

public struct ManagedScreenshot: Equatable, Sendable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256
    }
}

public protocol ScreenshotPersisting: Sendable {
    func save(originalPNG: Data) async throws -> ManagedScreenshot
    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws
}
