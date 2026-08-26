import Foundation

public enum FileProviderMetadataStoreError: Error, Equatable {
    case unsafePath
    case invalidData
}

public actor FileProviderMetadataStore: ProviderMetadataStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL.standardizedFileURL
    }

    public func load() async throws -> ProviderMetadataState {
        try rejectResolvedSymbolicLinks(at: fileURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ProviderMetadataState()
        }
        try rejectSymbolicLink(at: fileURL)
        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder().decode(ProviderMetadataState.self, from: data)
        } catch is DecodingError {
            throw FileProviderMetadataStoreError.invalidData
        }
    }

    public func save(_ state: ProviderMetadataState) async throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try rejectResolvedSymbolicLinks(at: directoryURL)
        try rejectResolvedSymbolicLinks(at: directoryURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try rejectSymbolicLink(at: directoryURL)
        } else {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try rejectSymbolicLink(at: fileURL)
        }
        let data = try encoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func rejectSymbolicLink(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw FileProviderMetadataStoreError.unsafePath
        }
    }

    private func rejectResolvedSymbolicLinks(at url: URL) throws {
        guard url.standardizedFileURL.path
                == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw FileProviderMetadataStoreError.unsafePath
        }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
