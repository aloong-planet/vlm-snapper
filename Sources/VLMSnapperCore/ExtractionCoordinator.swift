import Foundation

public struct ProviderSelection: Equatable, Sendable {
    public let providerID: String
    public let modelID: String

    public init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

public struct ManagedScreenshot: Equatable, Sendable {
    public let path: String
    public let sha256: String

    public init(path: String, sha256: String) {
        self.path = path
        self.sha256 = sha256
    }
}

public struct PreparedExtraction: Equatable, Sendable {
    public let operationID: UUID
    public let screenshot: ManagedScreenshot
    public let selection: ProviderSelection

    public init(
        operationID: UUID,
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) {
        self.operationID = operationID
        self.screenshot = screenshot
        self.selection = selection
    }
}

public struct ExtractionResult: Equatable, Sendable {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
    }
}

public protocol ScreenshotPersisting: Sendable {
    func save(originalPNG: Data) async throws -> ManagedScreenshot
    func discardIfOwned(_ screenshot: ManagedScreenshot) async throws
}

public protocol HistoryPersisting: Sendable {
    func prepareExtraction(
        screenshot: ManagedScreenshot,
        selection: ProviderSelection
    ) async throws -> PreparedExtraction
}

public protocol ProviderExtracting: Sendable {
    func extractText(
        from originalPNG: Data,
        preparedExtraction: PreparedExtraction
    ) async throws -> ExtractionResult
}

public enum ExtractionCoordinatorError: Error, Equatable {
    case screenshotPersistenceFailed
    case historyPreparationFailed
    case historyPreparationFailedWithOrphan(path: String)
}

public actor ExtractionCoordinator {
    private let screenshotStore: any ScreenshotPersisting
    private let historyStore: any HistoryPersisting
    private let provider: any ProviderExtracting

    public init(
        screenshotStore: any ScreenshotPersisting,
        historyStore: any HistoryPersisting,
        provider: any ProviderExtracting
    ) {
        self.screenshotStore = screenshotStore
        self.historyStore = historyStore
        self.provider = provider
    }

    public func startExtraction(
        originalPNG: Data,
        selection: ProviderSelection
    ) async throws -> ExtractionResult {
        let screenshot: ManagedScreenshot
        do {
            screenshot = try await screenshotStore.save(originalPNG: originalPNG)
        } catch {
            throw ExtractionCoordinatorError.screenshotPersistenceFailed
        }
        let preparedExtraction: PreparedExtraction
        do {
            preparedExtraction = try await historyStore.prepareExtraction(
                screenshot: screenshot,
                selection: selection
            )
        } catch {
            try await failHistoryPreparation(for: screenshot)
        }
        guard preparedExtraction.screenshot == screenshot,
              preparedExtraction.selection == selection
        else {
            try await failHistoryPreparation(for: screenshot)
        }
        return try await provider.extractText(
            from: originalPNG,
            preparedExtraction: preparedExtraction
        )
    }

    private func failHistoryPreparation(
        for screenshot: ManagedScreenshot
    ) async throws -> Never {
        do {
            try await screenshotStore.discardIfOwned(screenshot)
        } catch {
            throw ExtractionCoordinatorError.historyPreparationFailedWithOrphan(
                path: screenshot.path
            )
        }
        throw ExtractionCoordinatorError.historyPreparationFailed
    }
}
