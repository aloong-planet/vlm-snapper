import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import XCTest
import Vision
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Waits and native input the application tests share.

@MainActor
func eventually(file: String = #fileID, line: Int = #line, _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(try await condition()) {
        guard ContinuousClock.now < deadline else { throw FixtureError.deadline(file, line) }
        try Task.checkCancellation()
        await Task.yield()
    }
}

enum FixtureError: Error {
    case deadline(String, Int), unexpectedOperation, state(String)
    case cleanup(operation: any Error, release: any Error)
}

func requireFixture<T>(_ value: T?) throws -> T {
    guard let value else { throw FixtureError.state("Required fixture value is missing") }
    return value
}

@MainActor
func renderedText(in window: NSWindow) throws -> String {
    pumpNativeEvents(window)
    let view = try XCTUnwrap(window.contentView)
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

@MainActor
func withNativeApplicationEnvironment(_ operation: () async throws -> Void) async throws {
    let application = NSApplication.shared
    let previousDelegate = application.delegate
    let previousPolicy = application.activationPolicy()
    application.delegate = nil
    defer {
        application.delegate = previousDelegate
        _ = application.setActivationPolicy(previousPolicy)
    }
    guard application.setActivationPolicy(.accessory) else { throw FixtureError.state("Accessory activation policy was rejected") }
    try await operation()
}

@MainActor
func pumpWindowActivationEvents() {
    if let event = NSApp.nextEvent(matching: .appKitDefined, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
        NSApp.sendEvent(event)
    }
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
}

@MainActor
func openProviderFromOnboarding(_ window: NSWindow) async throws {
    try await eventually {
        pumpNativeEvents(window)
        return window.contentView?.bounds.width ?? 0 > 0
    }
    let content = try requireFixture(window.contentView)
    let bitmap = try requireFixture(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: bitmap)
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(cgImage: requireFixture(bitmap.cgImage), options: [:]).perform([request])
    // Locate the visible button, not an old coordinate or the routing callback.
    let label = try requireFixture(request.results?.first {
        $0.topCandidates(1).first?.string == "Provider Settings"
    })
    let rectangle = label.boundingBox
    let local = NSPoint(x: rectangle.midX * content.bounds.width,
                        y: (content.isFlipped ? 1 - rectangle.midY : rectangle.midY) * content.bounds.height)
    try click(window, at: content.convert(local, to: nil))
    try await eventually { !window.isVisible }
}

@MainActor
func editableSecureField(in window: NSWindow) async throws -> NSSecureTextField {
    try await eventually {
        pumpNativeEvents(window)
        return window.contentView.map {
            descendants($0).compactMap { $0 as? NSSecureTextField }.contains { $0.isEditable }
        } == true
    }
    let content = try requireFixture(window.contentView)
    return try requireFixture(descendants(content).compactMap { $0 as? NSSecureTextField }.first { $0.isEditable })
}

@MainActor
func clickValidate(below field: NSTextField, in window: NSWindow) throws {
    pumpNativeEvents(window)
    let frame = field.convert(field.bounds, to: nil)
    try click(window, at: NSPoint(x: frame.maxX, y: frame.minY - 30))
}

@MainActor
func click(_ window: NSWindow, at point: NSPoint) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        window.sendEvent(try requireFixture(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
    }
}

@MainActor
func drag(_ window: NSWindow, from start: NSPoint, to end: NSPoint, trace: NativeWaitTrace? = nil) throws {
    for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end), (.leftMouseUp, end)] {
        trace?.record("before-mouse-\(type.rawValue)", window: window)
        window.sendEvent(try requireFixture(NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1
        )))
        pumpNativeEvents(window)
        trace?.record("after-mouse-\(type.rawValue)", window: window)
    }
}

// Test-only, bounded state transitions. Never read titles, editor values,
// pasteboard contents, captured pixels or external application names.
@MainActor
final class NativeWaitTrace {
    private let name: String
    private let start = ProcessInfo.processInfo.systemUptime
    private var previous = ""
    private var entries: [String] = []

    init(name: String) { self.name = name }

    func record(_ stage: String, window: NSWindow? = nil) {
        let windows = NSApp.windows.sorted { $0.windowNumber < $1.windowNumber }.map {
            "id=\($0.windowNumber),visible=\($0.isVisible),key=\($0.isKeyWindow),canKey=\($0.canBecomeKey),level=\($0.level.rawValue),size=\($0.contentView?.bounds.size ?? .zero)"
        }.joined(separator: ";")
        let state = "stage=\(stage) target=\(window?.windowNumber ?? -1) active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) key=\(NSApp.keyWindow?.windowNumber ?? -1) main=\(NSApp.mainWindow?.windowNumber ?? -1) frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1) windows=[\(windows)]"
        guard state != previous else { return }
        previous = state
        if entries.count == 64 { entries.removeFirst() }
        entries.append("t=\(ProcessInfo.processInfo.systemUptime - start) \(state)")
    }

    func emit() {
        let header = "[NATIVE-DIAG] \(name) pid=\(ProcessInfo.processInfo.processIdentifier) elapsed=\(ProcessInfo.processInfo.systemUptime - start)"
        let output = ([header] + entries).joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(output.utf8))
    }
}

@MainActor
func resultBox() -> NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<CaptureResultBoxView> }
}

@MainActor
func resultBoxPresentation() -> CaptureResultBoxPresentation? {
    (resultBox()?.contentView as? NSHostingView<CaptureResultBoxView>)?.rootView.presentation
}

@MainActor
func resultBoxText() -> String? {
    guard let content = resultBox()?.contentView else { return nil }
    return descendants(content).compactMap { $0 as? NSTextView }.first?.string
}

/// Presses a header button of the box: 0 is Close, 1 Retry, 2 Copy. These SwiftUI buttons are not
/// NSButtons, so this exercises actual mouse delivery.
@MainActor
func clickResultBoxButton(_ window: NSWindow, fromEnd index: Int) throws {
    let bounds = try requireFixture(window.contentView).bounds
    let step = VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap
    try click(window, at: NSPoint(
        x: bounds.maxX - 6 - VLMSnapperUIConstants.toolbarControlHeight / 2 - CGFloat(index) * step,
        y: bounds.maxY - CaptureResultBoxMetrics.headerHeight / 2
    ))
    pumpNativeEvents(window)
}

/// Presses Extract, the toolbar's first control.
@MainActor
func clickExtract(_ toolbar: NSWindow) async throws {
    pumpNativeEvents(toolbar)
    try click(toolbar, at: NSPoint(x: 40, y: try requireFixture(toolbar.contentView).bounds.midY))
    await settleToolbarAction(toolbar)
}

/// A toolbar press does its work in a main-actor task, which runs at this test's next suspension, not during
/// a pump (measured 2026-11-03). A read straight after a press would run before that work.
@MainActor
func settleToolbarAction(_ toolbar: NSWindow) async {
    for _ in 0..<3 {
        await Task.yield()
        pumpNativeEvents(toolbar)
    }
}

/// How far the darkest and lightest pixels of the Translate label are apart, for how strong it renders.
@MainActor
func translateLabelInk(_ toolbar: NSWindow) throws -> CGFloat {
    pumpNativeEvents(toolbar)
    let view = try requireFixture(toolbar.contentView)
    let size = VLMSnapperUIConstants.toolbarControlHeight
    let gap = VLMSnapperUIConstants.toolbarControlGap
    let right = view.bounds.maxX - VLMSnapperUIConstants.toolbarPadding - 3 * size - 3 * gap - 1 - gap
    let bitmap = try requireFixture(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    var levels: [CGFloat] = []
    for row in Int((view.bounds.midY - 6) * scale)..<Int((view.bounds.midY + 6) * scale) {
        for column in Int((right - 80) * scale)..<Int((right - 40) * scale) {
            guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
            levels.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
        }
    }
    return try requireFixture(levels.max()) - (try requireFixture(levels.min()))
}

/// Opens the language list and presses a language's row where it renders.
@MainActor
func chooseLanguage(_ code: String, in toolbar: NSWindow) async throws {
    pumpNativeEvents(toolbar)
    let bounds = try requireFixture(toolbar.contentView).bounds
    let size = VLMSnapperUIConstants.toolbarControlHeight
    let gap = VLMSnapperUIConstants.toolbarControlGap
    let right = bounds.maxX - VLMSnapperUIConstants.toolbarPadding - 3 * size - 3 * gap - 1 - gap
    try click(toolbar, at: NSPoint(x: right - 8, y: bounds.midY))
    var popover: NSWindow?
    try await eventually {
        pumpNativeEvents(toolbar)
        popover = NSApp.windows.first { $0.className.contains("Popover") && $0.isVisible }
        return popover != nil
    }
    let window = try requireFixture(popover)
    let content = try requireFixture(window.contentView)
    let row = try requireFixture(TargetLanguageCatalog.standard.codes.firstIndex(of: code))
    var table: NSTableView?
    try await eventually {
        pumpNativeEvents(window)
        table = descendants(content).compactMap { $0 as? NSTableView }.first
        return (table?.numberOfRows ?? 0) > row
    }
    let list = try requireFixture(table)
    list.scrollRowToVisible(row)
    pumpNativeEvents(window)
    let place = list.rect(ofRow: row)
    try click(window, at: list.convert(NSPoint(x: place.minX + 60, y: place.midY), to: nil))
    try await eventually {
        pumpNativeEvents(toolbar)
        return !window.isVisible
    }
}

/// Presses the left part of the combined button. Its right edge is counted from the toolbar's end:
/// padding, three icon boxes and their gaps, then the divider and its gaps.
@MainActor
func clickTranslate(_ toolbar: NSWindow) async throws {
    pumpNativeEvents(toolbar)
    let bounds = try requireFixture(toolbar.contentView).bounds
    let size = VLMSnapperUIConstants.toolbarControlHeight
    let gap = VLMSnapperUIConstants.toolbarControlGap
    let right = bounds.maxX - VLMSnapperUIConstants.toolbarPadding - 3 * size - 3 * gap - 1 - gap
    try click(toolbar, at: NSPoint(x: right - 70, y: bounds.midY))
    await settleToolbarAction(toolbar)
}

/// The request has fully ended, including its bookkeeping after the text stops changing.
@MainActor
func waitForResultIdle(_ model: VLMSnapperApplicationModel) async throws {
    try await eventually { !model.isRunningResultRequest }
    // The controls take their enabled state on the next pass of the run loop.
    for window in NSApp.windows where window.isVisible {
        pumpNativeEvents(window)
    }
}

/// Answers a confirmation left on an overlay when a test fails midway, so teardown can finish.
@MainActor
func answerLeftoverOverlaySheets() -> Task<Void, Never> {
    Task { @MainActor in
        while !Task.isCancelled {
            for window in NSApp.windows where window.level == .screenSaver {
                if let sheet = window.attachedSheet {
                    window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// Makes the next successful save fail, as a real database write error does.
@MainActor
func failSuccessfulSaves(_ fixture: ApplicationFixture) throws -> OpaquePointer? {
    var database: OpaquePointer?
    try requireFixture(sqlite3_open(fixture.root.appendingPathComponent("history.sqlite").path, &database) == SQLITE_OK ? true : nil)
    try requireFixture(sqlite3_exec(database, "CREATE TRIGGER box_save_failure BEFORE UPDATE ON operations WHEN NEW.status = 'succeeded' BEGIN SELECT RAISE(ABORT, 'fixture'); END", nil, nil, nil) == SQLITE_OK ? true : nil)
    return database
}

/// Ends a sheet on the overlay as pressing one of its buttons does.
@MainActor
func answerSheet(on overlay: NSWindow, with response: NSApplication.ModalResponse) async throws {
    try await eventually { overlay.attachedSheet != nil }
    overlay.endSheet(try requireFixture(overlay.attachedSheet), returnCode: response)
    pumpNativeEvents(overlay)
}

@MainActor
enum DisplayChange: CaseIterable {
    case sleep, disconnect, scale, rotate, move
}

func changedGeometry(
    _ value: CaptureDisplayGeometry,
    id: UInt32? = nil,
    scale: Bool = false,
    rotate: Bool = false,
    move: Bool = false
) -> CaptureDisplayGeometry {
    CaptureDisplayGeometry(
        displayID: id ?? value.displayID,
        logicalX: value.logicalX + (move ? 100 : 0), logicalY: value.logicalY,
        logicalWidth: value.logicalWidth, logicalHeight: value.logicalHeight,
        pixelWidth: value.pixelWidth + (scale ? 100 : 0), pixelHeight: value.pixelHeight,
        rotationDegrees: value.rotationDegrees + (rotate ? 90 : 0)
    )
}

@MainActor
func makeCaptureReady(_ model: VLMSnapperApplicationModel, key: String) async throws {
    model.credentialEditor.edit(key)
    #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
        operation: model.providerSettingsConfiguration().onValidate))
    try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
    model.providerSettingsConfiguration().onSelectModel("fixture-vision")
    try await eventually {
        model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
    }
}

/// A key and a day-old model list for each Provider, as an earlier run of the app left them.
func saveStaleProviders(in fixture: ApplicationFixture, _ providers: [ProviderID]) async throws {
    var configurations: [ProviderID: ProviderConfiguration] = [:]
    for provider in providers {
        await fixture.credentials.replaceCredential(
            ProviderCredential(generation: UUID(), apiKey: "fixture-\(provider.rawValue)-key"), for: provider
        )
        configurations[provider] = ProviderConfiguration(
            models: [ProviderModelState(id: "fixture-vision")],
            fetchedAt: Date(timeIntervalSinceNow: -25 * 60 * 60),
            selectedModelID: "fixture-vision"
        )
    }
    try await FileProviderMetadataStore(fileURL: fixture.root.appendingPathComponent("providers.json")).save(
        ProviderMetadataState(configurations: configurations, currentProvider: providers.first)
    )
}

/// A successful extraction already in the history, with its screenshot.
func savedExtractionRecord(in fixture: ApplicationFixture) async throws -> UUID {
    let screenshots = FileSystemScreenshotStore(rootDirectory: fixture.root.appendingPathComponent("Pictures"))
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let screenshot = try await screenshots.save(originalPNG: png)
    let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
    let prepared = try await store.prepareOperation(screenshot: screenshot,
        selection: ProviderSelection(providerID: "deepseek", modelID: "old-model"), operation: .extractText)
    try await store.finish(operationID: prepared.operationID,
        with: .succeeded(sourceMarkdown: "Archived original", translationMarkdown: nil))
    return prepared.operationID
}

/// The selection overlay on the screen that `syntheticDisplay()` freezes.
@MainActor
func mainScreenOverlay() throws -> NSWindow? {
    let screen = try requireFixture(NSScreen.main)
    return NSApp.windows.first {
        $0.isVisible && $0.level == .screenSaver && $0.frame == screen.frame
    }
}

@MainActor
func captureOverlayIsVisible() -> Bool {
    NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver }
}

@MainActor
func captureToolbar() -> NSWindow? {
    NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar> }
}

@MainActor
func pressEscape(_ window: NSWindow) throws {
    window.sendEvent(try requireFixture(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
}

/// Sends Esc the way a key press arrives: to whichever window the application has made key.
@MainActor
func pressEscapeThroughApplication() throws {
    let window = try requireFixture(NSApp.keyWindow)
    NSApp.sendEvent(try requireFixture(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
}

@MainActor
func sendMouse(_ type: NSEvent.EventType, at point: NSPoint, to window: NSWindow) throws {
    window.sendEvent(try requireFixture(NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1
    )))
    pumpNativeEvents(window)
}

/// Runs a capture-ready model that may make image requests, on the synthetic display.
@MainActor
func withResultFixture(
    _ body: @MainActor (ApplicationFixture, VLMSnapperApplicationModel) async throws -> Void
) async throws {
    try await withFixture { fixture in
        fixture.permissionGranted = true
        let display = try syntheticDisplay()
        await fixture.capture.provide(display)
        fixture.displayGeometries = [display.geometry]
        await fixture.http.allowImageRequests()
        try await fixture.withModel { model in
            try await makeCaptureReady(model, key: "fixture-result-box-key")
            try await body(fixture, model)
        }
    }
}

/// Runs a capture-ready model whose window list holds one window at local (200, 150, 300, 200)
/// of the main screen, given to the list in global top-left coordinates.
@MainActor
func withSnapFixture(
    windowList: Bool = true,
    _ body: @MainActor (ApplicationFixture, NSScreen, VLMSnapperApplicationModel) async throws -> Void
) async throws {
    try await withFixture { fixture in
        fixture.permissionGranted = true
        let display = try syntheticDisplay()
        await fixture.capture.provide(display)
        fixture.displayGeometries = [display.geometry]
        let screen = try #require(NSScreen.main)
        let flipHeight = try #require(NSScreen.screens.first).frame.height
        if windowList {
            let window = CaptureWindowSnapshotEntry(
                ownerProcessID: 4242, layer: 0, alpha: 1, isOnScreen: true,
                bounds: CGRect(
                    x: screen.frame.minX + 200,
                    y: flipHeight - (screen.frame.minY + 350),
                    width: 300,
                    height: 200
                )
            )
            await fixture.windows.provide(CaptureWindowSnapshot(windows: [window], dockProcessID: nil))
        }
        try await fixture.withModel { model in
            try await makeCaptureReady(model, key: "fixture-snap-key")
            try await body(fixture, screen, model)
        }
    }
}

/// Captures, clicks the fixture window and returns the toolbar shown for it.
@MainActor
func selectWindow(_ fixture: ApplicationFixture) async throws -> NSWindow {
    try fixture.shortcuts.fire()
    let overlay = try await frozenMainOverlay()
    try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 250), to: overlay)
    try sendMouse(.leftMouseUp, at: NSPoint(x: 300, y: 250), to: overlay)
    try await eventually { captureToolbar() != nil }
    let toolbar = try requireFixture(captureToolbar())
    pumpNativeEvents(toolbar)
    return toolbar
}

/// Centre of the toolbar's icon button `fromEnd` places before its last one (0 is Close, 1 Save, 2 Copy).
@MainActor
func toolbarIconCenter(_ toolbar: NSWindow, fromEnd index: Int) throws -> NSPoint {
    let bounds = try requireFixture(toolbar.contentView).bounds
    let lastCenter = bounds.maxX - VLMSnapperUIConstants.toolbarPadding - VLMSnapperUIConstants.toolbarControlHeight / 2
    let step = VLMSnapperUIConstants.toolbarControlHeight + VLMSnapperUIConstants.toolbarControlGap
    return NSPoint(x: lastCenter - CGFloat(index) * step, y: bounds.midY)
}

func pngPixelSize(_ data: Data) throws -> [Int] {
    let source = try requireFixture(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try requireFixture(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return [image.width, image.height]
}

@MainActor
func pixelSize(width: CGFloat, height: CGFloat, on screen: NSScreen) -> [Int] {
    [Int((width * screen.backingScaleFactor).rounded()), Int((height * screen.backingScaleFactor).rounded())]
}

@MainActor
func frozenMainOverlay() async throws -> NSWindow {
    try await eventually { try mainScreenOverlay() != nil }
    let overlay = try requireFixture(try mainScreenOverlay())
    try await eventually { try overlayShowsFrozenFrame(overlay) }
    pumpNativeEvents(overlay)
    return overlay
}

/// Captures with frames available immediately and drags a selection until the toolbar shows.
@MainActor
func completeSelection(
    _ fixture: ApplicationFixture
) async throws -> (overlay: NSWindow, toolbar: NSWindow) {
    try fixture.shortcuts.fire()
    try await eventually { try mainScreenOverlay() != nil }
    let overlay = try requireFixture(try mainScreenOverlay())
    try await eventually { try overlayShowsFrozenFrame(overlay) }
    pumpNativeEvents(overlay)
    try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300))
    try await eventually { captureToolbar() != nil }
    return (overlay, try requireFixture(captureToolbar()))
}

/// Reads what the overlay shows at its centre: a pending overlay dims the live
/// screen (translucent), a frozen overlay shows the opaque frozen frame.
@MainActor
func overlayShowsFrozenFrame(_ window: NSWindow) throws -> Bool {
    let layer = try requireFixture(window.contentView?.layer)
    let context = try requireFixture(CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: requireFixture(CGColorSpace(name: CGColorSpace.sRGB)),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: -layer.bounds.midX, y: -layer.bounds.midY)
    layer.render(in: context)
    let alpha = try requireFixture(context.data).load(fromByteOffset: 3, as: UInt8.self)
    return alpha == 255
}

func syntheticDisplay() throws -> FrozenCaptureDisplay {
    let screen = try #require(NSScreen.main)
    let number = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
    let geometry = try #require(currentCaptureDisplayGeometry(
        for: number.uint32Value, pointPixelScale: Float(screen.backingScaleFactor)
    ))
    let context = try #require(CGContext(data: nil, width: geometry.pixelWidth, height: geometry.pixelHeight,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: geometry.pixelWidth, height: geometry.pixelHeight))
    let image = try #require(context.makeImage())
    return FrozenCaptureDisplay(geometry: geometry, frame: FrozenDisplayFrame(image: image))
}

@MainActor
func pumpNativeEvents(_ window: NSWindow) {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    window.layoutIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
}

@MainActor
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
