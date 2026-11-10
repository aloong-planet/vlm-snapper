import AppKit
import Foundation
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// The fixture the application tests run the real application in, and the doubles for its external boundaries.

@MainActor
func withFixture(_ operation: (ApplicationFixture) async throws -> Void) async throws {
    let fixture = try ApplicationFixture()
    defer { fixture.removeTemporaryState() }
    do {
        try await operation(fixture)
    } catch {
        let operationError = error
        do {
            try await fixture.waitForShortcutRelease()
        } catch {
            throw FixtureError.cleanup(operation: operationError, release: error)
        }
        throw error
    }
    try await fixture.waitForShortcutRelease()
}

@MainActor
final class FixtureShortcutLease: GlobalShortcutRegistrationBackend {
    let backend: FixtureShortcuts
    init(backend: FixtureShortcuts) { self.backend = backend }
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor @Sendable () -> Void) throws -> any GlobalShortcutRegistration {
        try backend.register(shortcut, handler: handler)
    }
}

@MainActor
final class WeakShortcutLease {
    weak var value: FixtureShortcutLease?
    init(_ value: FixtureShortcutLease) { self.value = value }
}

@MainActor
func stopFixture(excluding existingWindows: [NSWindow], stop: () -> Void) {
    precondition(withUnsafeCurrentTask { $0 != nil }, "Fixture cleanup requires a Swift Task")
    autoreleasepool {
        // Keep this fixture's windows alive across stop(), which closes them.
        let windows = NSApp.windows.filter { window in !existingWindows.contains { $0 === window } }
        stop()
        for window in windows {
            window.makeFirstResponder(nil)
            window.contentViewController = nil
            window.contentView = NSView()
            window.orderOut(nil)
        }
    }
}

actor ControlledHistoryImages: ManagedScreenshotLoading {
    let store: FileSystemScreenshotStore
    private var paused = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var finishedCount = 0
    var pendingCount: Int { pending.count }
    init(store: FileSystemScreenshotStore) { self.store = store }
    func pause() { paused = true }
    func release(at index: Int) { pending.remove(at: index).resume() }
    func releaseAll() {
        paused = false
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
    func loadIfOwned(_ screenshot: ManagedScreenshot) async throws -> Data {
        defer { finishedCount += 1 }
        if paused { await withCheckedContinuation { pending.append($0) } }
        return try await store.loadIfOwned(screenshot)
    }
}

@MainActor
final class ApplicationFixture {
    let root: URL
    let suite = "VLMSnapperAppTests.\(UUID().uuidString)"
    let credentials = FixtureCredentials()
    let http = FixtureHTTP()
    let shortcuts = FixtureShortcuts()
    let capture = FixtureCapture()
    let windows = FixtureWindowListing()
    let clipboard = FixtureClipboard()
    let imageSaver = FixtureImageSaver()
    let resultLossNotifier = FixtureResultLossNotifier()
    let displayNotifications = NotificationCenter()
    let workspaceNotifications = NotificationCenter()
    var displayGeometries: [CaptureDisplayGeometry]?
    var queuedDisplayGeometries: [[CaptureDisplayGeometry]] = []
    var displayReads = 0
    let pasteboard = NSPasteboard.withUniqueName()
    var permissionGranted = false
    var updates: FixtureUpdates?
    private(set) var dependencyConstructions = 0
    private var shortcutLeases: [WeakShortcutLease] = []

    func waitForShortcutRelease() async throws {
        // Cleanup must finish even when the operation's task was cancelled.
        try await Task { @MainActor in
            try await eventually {
                return autoreleasepool { self.shortcutLeases.allSatisfy { $0.value == nil } }
            }
        }.value
    }

    init() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func withModel(historyImageLoader: ControlledHistoryImages? = nil,
                   _ operation: (VLMSnapperApplicationModel) async throws -> Void) async throws {
        // Strong references: a freed window's address can be reused by a window this
        // fixture creates, so identifiers alone would skip that window at cleanup.
        let existingWindows = NSApp.windows
        let defaults = try requireFixture(UserDefaults(suiteName: suite))
        await UserDefaultsApplicationLanguageStore(defaults: defaults).save(.english)
        let model = try VLMSnapperApplicationModel(
            applicationSupportRoot: root,
            languageStore: UserDefaultsApplicationLanguageStore(defaults: defaults),
            defaults: defaults,
            dependencies: dependencies(),
            historyImageLoader: historyImageLoader
        )
        do {
            try await model.start()
            try await operation(model)
        } catch {
            await historyImageLoader?.releaseAll()
            await http.release()
            await capture.release()
            let answering = answerLeftoverOverlaySheets()
            _ = await model.prepareForTermination()
            answering.cancel()
            stopFixture(excluding: existingWindows) { model.stop() }
            throw error
        }
        await historyImageLoader?.releaseAll()
        await http.release()
        await capture.release()
        let canTerminate = await model.prepareForTermination()
        stopFixture(excluding: existingWindows) { model.stop() }
        guard canTerminate else { throw FixtureError.state("Model termination preparation was rejected") }
    }

    func application() -> VLMSnapperApplicationDelegate {
        VLMSnapperApplicationDelegate {
            let defaults = try requireFixture(UserDefaults(suiteName: self.suite))
            return ApplicationStartupDependencies(
                root: self.root, defaults: defaults, pasteboard: self.pasteboard, messaging: FixtureMessaging(),
                makeModelDependencies: { try self.dependencies() }
            )
        }
    }

    func withApplication(_ operation: (VLMSnapperApplicationDelegate) async throws -> Void) async throws {
        // Strong references: a freed window's address can be reused by a window this
        // fixture creates, so identifiers alone would skip that window at cleanup.
        let existingWindows = NSApp.windows
        let defaults = try requireFixture(UserDefaults(suiteName: suite))
        await UserDefaultsApplicationLanguageStore(defaults: defaults).save(.english)
        let application = application()
        let previousMenu = NSApp.mainMenu
        defer {
            NSApp.mainMenu = previousMenu
        }
        do {
            guard try await application.start() == .primary else { throw FixtureError.state("Expected primary application") }
            try await operation(application)
        } catch {
            await http.release()
            await capture.release()
            _ = await application.prepareForTermination()
            stopFixture(excluding: existingWindows) { application.stop() }
            throw error
        }
        await http.release()
        await capture.release()
        let canTerminate = await application.prepareForTermination()
        stopFixture(excluding: existingWindows) { application.stop() }
        guard canTerminate else { throw FixtureError.state("Application termination preparation was rejected") }
    }

    private func dependencies() throws -> ApplicationModelDependencies {
        dependencyConstructions += 1
        let preferences = try isolatedPreferences(suite: suite)
        return ApplicationModelDependencies(
                credentialStore: credentials,
                modelHTTP: http,
                operationHTTP: http,
                screenshotRoot: root.appendingPathComponent("Pictures"),
                permissionAuthorizer: FixturePermissions(granted: permissionGranted),
                permissionHistory: preferences.permission,
                retentionPreferences: preferences.retention,
                permissionChecker: FixturePermissions(granted: permissionGranted),
                frozenDisplayCapturer: capture,
                windowListing: windows,
                captureClipboard: clipboard,
                captureImageSaver: imageSaver,
                captureResultLossNotifier: resultLossNotifier,
                displayMonitor: CaptureDisplayMonitor(
                    notifications: displayNotifications,
                    workspaceNotifications: workspaceNotifications,
                    readGeometries: {
                        self.displayReads += 1
                        if !self.queuedDisplayGeometries.isEmpty {
                            return self.queuedDisplayGeometries.removeFirst()
                        }
                        return self.displayGeometries ?? CaptureDisplayMonitor.liveGeometries()
                    }
                ),
                loginService: FixtureLogin(),
                makeUpdateDriver: { handler in
                    let driver = FixtureUpdates(eventHandler: handler)
                    self.updates = driver
                    return driver
                },
                makeShortcutBackend: {
                    // The real coordinator owns this external-adapter lease;
                    // the fixture observes its release without retaining it.
                    let lease = FixtureShortcutLease(backend: self.shortcuts)
                    self.shortcutLeases.append(WeakShortcutLease(lease))
                    return lease
                }
        )
    }

    func removeTemporaryState() {
        pasteboard.releaseGlobally()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

func isolatedPreferences(suite: String) throws -> (
    permission: UserDefaultsPermissionRequestHistoryStore,
    retention: UserDefaultsRetentionPreferenceStore
) {
    guard let permissionDefaults = UserDefaults(suiteName: suite),
          let retentionDefaults = UserDefaults(suiteName: suite) else {
        throw FixtureError.unexpectedOperation
    }
    return (
        UserDefaultsPermissionRequestHistoryStore(defaults: permissionDefaults),
        UserDefaultsRetentionPreferenceStore(defaults: retentionDefaults)
    )
}

actor FixtureMessaging: PrimaryInstanceMessaging {
    func beginObserving(_ handler: @escaping @Sendable () async -> Void) {}
    func requestActivation() {}
}

actor FixtureCredentials: ProviderCredentialStoring {
    private var values: [ProviderID: ProviderCredential] = [:]
    func credential(for provider: ProviderID) -> ProviderCredential? { values[provider] }
    func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) {
        values[provider] = credential
    }
    func deleteCredential(for provider: ProviderID) { values[provider] = nil }
}

// DeepSeek's message: github.com/Zoo-Code-Org/Zoo-Code/issues/1106. The JSON around it is OpenAI-compatible.
let deepSeekTextOnlyModelError = #"{"error":{"message":"Failed to deserialize the JSON body into the target type: messages[1]: unknown variant `image_url`, expected `text` at line 1 column 666600","type":"invalid_request_error"}}"#
// community.openai.com/t/580195.
let openAIUnsupportedImageError = #"{"error":{"message":"You uploaded an unsupported image. Please make sure your image is below 20 MB in size and is of one the following formats: ['png', 'jpeg', 'gif', 'webp'].","type":"invalid_request_error","param":null,"code":"invalid_image_format"}}"#

// github.com/RooCodeInc/Roo-Code/issues/439 and 2468. The JSON around it is OpenAI-compatible.
let deepSeekMissingModelError = #"{"error":{"message":"Model Not Exist","type":"invalid_request_error","param":null,"code":"invalid_request_error"}}"#
let modelUnavailableInBox = CaptureResultBoxPresentation.Body.failure(
    "The current model is unavailable. Refresh the model list and choose again."
)

actor FixtureHTTP: ProviderHTTPDataLoading, ProviderHTTPStreaming {
    private(set) var requests: [URLRequest] = []
    private var status = 200
    private var listedModels = ["fixture-vision"]
    func listModels(_ models: [String]) { listedModels = models }
    private var isPaused = false
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() { isPaused = true }
    func release() {
        isPaused = false
        waiter?.resume()
        waiter = nil
        imageContinuation?.finish()
        imageContinuation = nil
    }
    func respond(with status: Int) { self.status = status }
    func data(for request: URLRequest) async -> ProviderHTTPResponse {
        requests.append(request)
        if isPaused { await withCheckedContinuation { waiter = $0 } }
        // Shape from https://api-docs.deepseek.com/api/list-models/ (2026-09-07).
        // The identifier is deliberately synthetic; no live credential is used.
        let models = listedModels.map { #"{"id":"\#($0)","object":"model","owned_by":"deepseek"}"# }
        return ProviderHTTPResponse(
            data: Data(#"{"object":"list","data":[\#(models.joined(separator: ","))]}"#.utf8),
            statusCode: status
        )
    }
    private var imagesAllowed = false
    private(set) var imageRequests: [URLRequest] = []
    private var imageContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var imageRejection: (status: Int, body: String)?
    func allowImageRequests() { imagesAllowed = true }
    /// Every image request from now on gets this reply, as a Provider's error response.
    func rejectImages(status: Int, body: String) { imageRejection = (status, body) }
    private func imageRequestWasCanceled() { imageContinuation = nil }
    func stream(for request: URLRequest) throws -> ProviderHTTPStreamResponse {
        guard imagesAllowed else {
            Issue.record("Provider setup must not make an image request")
            throw FixtureError.unexpectedOperation
        }
        guard imageContinuation == nil else {
            Issue.record("An image request is already active")
            throw FixtureError.unexpectedOperation
        }
        imageRequests.append(request)
        let pair = AsyncThrowingStream<Data, Error>.makeStream()
        if let imageRejection {
            pair.continuation.yield(Data(imageRejection.body.utf8))
            pair.continuation.finish()
            return ProviderHTTPStreamResponse(statusCode: imageRejection.status, headers: [:], body: pair.stream)
        }
        imageContinuation = pair.continuation
        // A canceled request ends its stream, as closing the connection does.
        pair.continuation.onTermination = { [weak self] reason in
            guard case .cancelled = reason else { return }
            Task { await self?.imageRequestWasCanceled() }
        }
        return ProviderHTTPStreamResponse(statusCode: 200, headers: [:], body: pair.stream)
    }
    var hasActiveImageRequest: Bool { imageContinuation != nil }
    /// Sends part of the model's JSON output, as a real stream does.
    func streamImage(content: String, finishReason: String? = nil) throws {
        var delta: [String: Any] = ["index": 0, "delta": ["content": content]]
        if let finishReason { delta["finish_reason"] = finishReason }
        var body: [String: Any] = ["id": "fixture-image", "choices": [delta]]
        if finishReason != nil {
            body["usage"] = ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]
        }
        let chunk = try JSONSerialization.data(withJSONObject: body)
        imageContinuation?.yield(Data("data: ".utf8) + chunk + Data("\n\n".utf8))
        if finishReason != nil {
            imageContinuation?.yield(Data("data: [DONE]\n\n".utf8))
            imageContinuation?.finish()
            imageContinuation = nil
        }
    }
    func failImage() {
        imageContinuation?.finish(throwing: URLError(.networkConnectionLost))
        imageContinuation = nil
    }
    func finishImage(segments: [[String: String]]) throws {
        try finishImage(result: ["segments": segments])
    }
    func finishImage(source: String, translation: String? = nil) throws {
        if let translation {
            try finishImage(segments: [["id": "s1", "block": "p1", "kind": "paragraph",
                                        "source": source, "translation": translation]])
        } else {
            try finishImage(result: ["source": source])
        }
    }
    private func finishImage(result: [String: Any]) throws {
        // DeepSeek chat SSE shape used by ProviderAdapterRecordedContractTests;
        // use the real JSON decoder/stream contract, not normalized fake events.
        let content = String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self)
        let chunk = try JSONSerialization.data(withJSONObject: [
            "id": "fixture-image", "choices": [["index": 0, "delta": ["content": content], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]
        ])
        imageContinuation?.yield(Data("data: ".utf8) + chunk + Data("\n\ndata: [DONE]\n\n".utf8))
        imageContinuation?.finish()
        imageContinuation = nil
    }
}

struct FixturePermissions: ScreenCapturePermissionAuthorizing, ScreenCapturePermissionChecking {
    let granted: Bool
    func preflightScreenCaptureAccess() async -> Bool { granted }
    func requestScreenCaptureAuthorization() async -> Bool { granted }
    func hasScreenCaptureAccess() -> Bool { granted }
}

actor FixtureCapture: FrozenDisplayCapturing {
    private var display: FrozenCaptureDisplay?
    func provide(_ display: FrozenCaptureDisplay?) { self.display = display }
    private(set) var requests = 0
    private var allowed = false
    private var released = false
    private var framesHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func allowSuspendedCapture() {
        allowed = true
        released = false
    }
    /// Suspends captures until `release()`, then returns the provided display.
    func holdFrames() {
        framesHeld = true
        released = false
    }
    func release() {
        released = true
        framesHeld = false
        let suspended = waiters
        waiters.removeAll()
        suspended.forEach { $0.resume() }
    }
    func captureFrozenDisplays() async throws(CaptureDiscoveryError) -> FrozenDisplayBatch {
        requests += 1
        if framesHeld, !released { await withCheckedContinuation { waiters.append($0) } }
        if let display { return FrozenDisplayBatch(displays: [display]) }
        guard allowed else {
            Issue.record("Provider setup must not capture the screen")
            throw .permissionDenied
        }
        if !released { await withCheckedContinuation { waiters.append($0) } }
        throw .permissionDenied
    }
}

/// Clipboard double: records the PNG written by Copy.
@MainActor
final class FixtureClipboard: CaptureImageClipboard {
    private(set) var written: [Data] = []
    private(set) var writtenTexts: [String] = []
    func write(png: Data) -> Bool {
        written.append(png)
        return true
    }
    func write(text: String) {
        writtenTexts.append(text)
    }
}

@MainActor
final class FixtureResultLossNotifier: CaptureResultLossNotifying {
    private(set) var count = 0
    func unsavedResultDiscarded() async {
        count += 1
    }
}

/// Save double: answers like the save panel would and, when saving, writes the file as the live adapter does.
@MainActor
final class FixtureImageSaver: CaptureImageSaving {
    /// `hold` keeps the panel open until `release(_:)`.
    enum Answer { case saveTo(URL), cancel, hold }
    var answer = Answer.cancel
    private(set) var requests: [(png: Data, suggestedName: String)] = []
    private var held: CheckedContinuation<CaptureImageSaveOutcome, Never>?
    func release(_ outcome: CaptureImageSaveOutcome) {
        held?.resume(returning: outcome)
        held = nil
    }
    func save(png: Data, suggestedName: String) async -> CaptureImageSaveOutcome {
        requests.append((png, suggestedName))
        switch answer {
        case .hold:
            return await withCheckedContinuation { held = $0 }
        case .cancel:
            return .cancelled
        case .saveTo(let url):
            do {
                try png.write(to: url, options: .atomic)
                return .saved(url)
            } catch {
                return .failed
            }
        }
    }
}

/// Window list for snap regions; by default there is none, so clicks keep their old meaning.
actor FixtureWindowListing: CaptureWindowListing {
    private var snapshot: CaptureWindowSnapshot?
    /// Per-call lists, used in order before falling back to `snapshot`.
    private var queued: [CaptureWindowSnapshot?] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func provide(_ snapshot: CaptureWindowSnapshot?) { self.snapshot = snapshot }
    func provide(perCall snapshots: [CaptureWindowSnapshot?]) { queued = snapshots }
    func hold() { held = true }
    /// Resumes held calls, newest first when `newestFirst` is set.
    func release(newestFirst: Bool = false) {
        held = false
        let suspended = newestFirst ? waiters.reversed() : waiters
        waiters.removeAll()
        suspended.forEach { $0.resume() }
    }
    private(set) var returned = 0
    private(set) var calls = 0
    func captureWindowSnapshot() async -> CaptureWindowSnapshot? {
        calls += 1
        let result = queued.isEmpty ? snapshot : queued.removeFirst()
        if held { await withCheckedContinuation { waiters.append($0) } }
        returned += 1
        return result
    }
}

struct FixtureLogin: LoginItemServicing {
    func status() async -> LoginItemState { .unavailable }
    func register() async throws { throw FixtureError.unexpectedOperation }
    func unregister() async throws { throw FixtureError.unexpectedOperation }
    func openSystemSettings() async { Issue.record("Unexpected login settings request") }
}

actor FixtureUpdates: UpdateDriving {
    private let eventHandler: @Sendable (UpdateLifecycleEvent) async -> Void
    private(set) var configuration: UpdateDriverConfiguration?
    init(eventHandler: @escaping @Sendable (UpdateLifecycleEvent) async -> Void) {
        self.eventHandler = eventHandler
    }
    func send(_ event: UpdateLifecycleEvent) async { await eventHandler(event) }
    func start(configuration: UpdateDriverConfiguration) { self.configuration = configuration }
    func setAutomaticallyChecks(_ enabled: Bool) {}
    func checkForUpdates() throws { throw FixtureError.unexpectedOperation }
    func beginDownload() throws { throw FixtureError.unexpectedOperation }
    func installNow() throws { throw FixtureError.unexpectedOperation }
}

@MainActor
final class FixtureShortcuts: GlobalShortcutRegistrationBackend {
    private(set) var activeRegistrations = 0
    private var handler: (@MainActor @Sendable () -> Void)?
    func fire() throws {
        let registeredHandler = try #require(handler)
        registeredHandler()
    }
    func register(
        _ shortcut: GlobalShortcut,
        handler: @escaping @MainActor @Sendable () -> Void
    ) throws -> any GlobalShortcutRegistration {
        activeRegistrations += 1
        self.handler = handler
        return FixtureRegistration { [weak self] in
            self?.activeRegistrations -= 1
            self?.handler = nil
        }
    }
}

@MainActor
final class FixtureRegistration: GlobalShortcutRegistration {
    private var release: (() -> Void)?
    init(release: @escaping () -> Void) { self.release = release }
    func unregister() {
        release?()
        release = nil
    }
}
