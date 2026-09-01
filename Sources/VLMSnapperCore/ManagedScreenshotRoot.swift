import Foundation

public enum ManagedScreenshotRoot {
    public static func directURL(for systemPicturesDirectory: URL) -> URL {
        systemPicturesDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .appendingPathComponent("VLMSnapper", isDirectory: true)
    }
}
