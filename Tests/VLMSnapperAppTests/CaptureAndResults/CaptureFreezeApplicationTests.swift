import AppKit
import Foundation
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Display tests inject OS notifications and geometry snapshots; physical
// hot-plug, display sleep and multi-monitor focus require hardware acceptance.
// Pending-overlay tests hold the injected capturer, so they cannot show that the
// compositor leaves the pending overlay out of real frames (signed-app check), a
// second display whose freeze fails while another commits (two displays needed),
// a display connected while frames are pending (hot-plug during the freeze), the
// absence of a desktop flash between overlays (one main-thread call; check by
// screen recording), or every display invalidated before commit (modal failure
// alert blocks the run).
// Window-server hit testing is also out of reach: `sendEvent` skips it, so a click
// inside a clear pending selection reaching another app needs posted HID events
// with Accessibility trust (verified outside the suite, see the construction notes).
// The window-open animation of the overlay changes only composited frames, not the
// window frame, window-server bounds or layers: the overlay controller tests assert the
// window's animation behavior, and full first-frame coverage was checked by screen recording.
extension ProviderApplicationTests {
    @Test(arguments: DisplayChange.allCases)
    func displayChangesCancelSelectionBeforeMouseUp(change: DisplayChange) async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                // The selection and its display subscription begin with the frozen frame.
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                let reads = fixture.displayReads
                try await eventually { model.providerSnapshot.activity == .capture }
                fixture.displayGeometries = [display.geometry, changedGeometry(display.geometry, id: UInt32.max)]
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == reads + 1)
                #expect(overlay.isVisible)
                #expect(NSApp.windows.filter { $0.isVisible && $0.level == .screenSaver }.count == 1)
                if change == .sleep {
                    fixture.workspaceNotifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
                } else {
                    fixture.displayGeometries = change == .disconnect ? [] : [changedGeometry(
                        display.geometry, scale: change == .scale, rotate: change == .rotate, move: change == .move
                    )]
                    fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                }
                // Invalidation removes the native hit target synchronously,
                // without waiting for a mouse-up or an actor completion.
                #expect(!overlay.isVisible)
                try await eventually { !overlay.isVisible && model.providerSnapshot.activity == nil }
                #expect(overlay.contentView == nil)
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
                let stoppedReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == stoppedReads)
            }
        }
    }

    @Test
    func replacementAndEscapeRetireDisplaySubscriptions() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-lifecycle-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                var previous: NSWindow?
                for _ in 0..<2 {
                    try fixture.shortcuts.fire()
                    try await eventually {
                        model.providerSnapshot.activity == .capture && NSApp.windows.contains {
                            $0.isVisible && $0.level == .screenSaver && $0 !== previous
                        }
                    }
                    let overlay = try #require(try mainScreenOverlay())
                    // Retirement and display subscriptions follow the frozen frame.
                    try await eventually { try overlayShowsFrozenFrame(overlay) }
                    if let previous {
                        #expect(!previous.isVisible)
                        #expect(previous.contentView == nil)
                    }
                    let reads = fixture.displayReads
                    fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                    #expect(fixture.displayReads == reads + 1)
                    #expect(overlay.isVisible)
                    previous = overlay
                }
                let overlay = try #require(previous)
                pumpNativeEvents(overlay)
                overlay.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: overlay.windowNumber, context: nil, characters: "\u{1b}",
                    charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)))
                try await eventually { !overlay.isVisible && model.providerSnapshot.activity == nil }
                #expect(overlay.contentView == nil)
                let reads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == reads)
                try fixture.shortcuts.fire()
                try await eventually {
                    model.providerSnapshot.activity == .capture && NSApp.windows.contains {
                        $0.isVisible && $0.level == .screenSaver
                    }
                }
                #expect(await model.prepareForTermination())
                let terminatedReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                #expect(fixture.displayReads == terminatedReads)
                #expect(!NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func overlayCoversDisplaysBeforeFreezeCompletes() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-overlay-key")
                var retiredSources = 0
                model.onRetireCaptureSources = { retiredSources += 1 }
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                // The capturer is still suspended, so no frozen frame exists yet.
                try await eventually {
                    try await fixture.capture.requests == 1 && mainScreenOverlay() != nil
                }
                let overlay = try #require(try mainScreenOverlay())
                let everyScreenCovered = NSScreen.screens.allSatisfy { screen in
                    NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver && $0.frame == screen.frame }
                }
                #expect(everyScreenCovered)
                #expect(try !overlayShowsFrozenFrame(overlay))
                // Menu, management center and onboarding stay until the frame is shown.
                #expect(retiredSources == 0)
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                #expect(overlay.isVisible)
                #expect(try mainScreenOverlay() === overlay)
                #expect(retiredSources == 1)
            }
        }
    }

    @Test
    func selectionDraggedWhileFreezingCompletesWithFrozenFrames() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-selection-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300))
                #expect(try !overlayShowsFrozenFrame(overlay))
                #expect(captureToolbar() == nil)
                await fixture.capture.release()
                try await eventually { captureToolbar() != nil }
                #expect(try overlayShowsFrozenFrame(overlay))
            }
        }
    }

    @Test
    func escapeWhileFreezingExitsCapture() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-escape-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                // The keyboard belongs to the pending overlay, so the application routes Esc to it.
                #expect(overlay.isKeyWindow)
                try pressEscapeThroughApplication()
                try await eventually { !captureOverlayIsVisible() }
                // The freeze finishes after the user left; its frames must not reopen the selection.
                await fixture.capture.release()
                try await eventually { model.providerSnapshot.activity == nil }
                #expect(!captureOverlayIsVisible())
                #expect(captureToolbar() == nil)
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
            }
        }
    }

    @Test
    func terminationWhileFreezingWithdrawsOverlay() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-termination-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                // Frames are still held, so preparation must not wait for the freeze.
                #expect(await model.prepareForTermination())
                #expect(!captureOverlayIsVisible())
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func failedFreezeRestoresPreviousSelection() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-failure-key")
                var retiredSources = 0
                model.onRetireCaptureSources = { retiredSources += 1 }
                let (previous, toolbar) = try await completeSelection(fixture)
                #expect(retiredSources == 1)

                await fixture.capture.provide(nil)
                await fixture.capture.allowSuspendedCapture()
                var onboardingRequests = 0
                model.onShowOnboarding = { onboardingRequests += 1 }
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay() != nil
                }
                let pending = try #require(try mainScreenOverlay())
                #expect(pending !== previous)
                #expect(!previous.isVisible)
                #expect(!toolbar.isVisible)
                await fixture.capture.release()
                try await eventually { onboardingRequests == 1 }
                #expect(!pending.isVisible)
                #expect(previous.isVisible)
                #expect(try overlayShowsFrozenFrame(previous))
                #expect(toolbar.isVisible)
                #expect(model.providerSnapshot.activity == .capture)
                // A failed capture retires no source interface.
                #expect(retiredSources == 1)
            }
        }
    }

    @Test
    func escapeWhileReplacingSelectionReleasesActivity() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-replacement-key")
                let (previous, toolbar) = try await completeSelection(fixture)

                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay() != nil
                }
                let pending = try #require(try mainScreenOverlay())
                #expect(pending !== previous)
                pumpNativeEvents(pending)
                try pressEscape(pending)
                try await eventually { !captureOverlayIsVisible() }
                #expect(!toolbar.isVisible)
                await fixture.capture.release()
                // One capture activity is shared by both selections; leaving must release it.
                try await eventually { model.providerSnapshot.activity == nil }
                #expect(!captureOverlayIsVisible())
                #expect(!toolbar.isVisible)
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func selectionStartedBeforeFramesFinishesAfterThem() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-drag-key")
                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let overlay = try #require(try mainScreenOverlay())
                pumpNativeEvents(overlay)
                try sendMouse(.leftMouseDown, at: NSPoint(x: 300, y: 300), to: overlay)
                try sendMouse(.leftMouseDragged, at: NSPoint(x: 400, y: 400), to: overlay)
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(overlay) }
                #expect(captureToolbar() == nil)
                // Still dragging after the frame arrived: the rectangle's left edge moves to 150.
                try sendMouse(.leftMouseDragged, at: NSPoint(x: 150, y: 400), to: overlay)
                try sendMouse(.leftMouseUp, at: NSPoint(x: 150, y: 400), to: overlay)
                try await eventually { captureToolbar() != nil }
                let toolbar = try #require(captureToolbar())
                // The toolbar is left-aligned with the selection that mouse-up completed.
                #expect(abs(toolbar.frame.minX - (overlay.frame.minX + 150)) <= 1)
            }
        }
    }

    @Test
    func displayChangeAfterSelectionEndsCapture() async throws {
        try await withSnapFixture { fixture, _, model in
            let historyCount = model.historyRecords.count
            _ = try await selectWindow(fixture)
            let current = try #require(fixture.displayGeometries?.first)
            fixture.displayGeometries = [changedGeometry(current, scale: true)]
            fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            try await eventually { try mainScreenOverlay() == nil && captureToolbar() == nil }
            #expect(model.historyRecords.count == historyCount)
        }
    }

    @Test
    func displayChangeWhileReplacingAbandonsPendingCapture() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-pending-invalidated-key")
                try fixture.shortcuts.fire()
                try await eventually { try mainScreenOverlay() != nil }
                let previous = try #require(try mainScreenOverlay())
                try await eventually { try overlayShowsFrozenFrame(previous) }

                await fixture.capture.holdFrames()
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 2 && mainScreenOverlay().map { $0 !== previous } == true
                }
                // Ending the first selection releases the activity the pending capture shares.
                fixture.displayGeometries = [changedGeometry(display.geometry, move: true)]
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await eventually { !captureOverlayIsVisible() && model.providerSnapshot.activity == nil }
                fixture.displayGeometries = [display.geometry]
                // The second freeze has not returned; a shortcut now must still show its overlay.
                try fixture.shortcuts.fire()
                try await eventually {
                    try await fixture.capture.requests == 3 && mainScreenOverlay() != nil
                }
                let replacement = try #require(try mainScreenOverlay())
                await fixture.capture.release()
                try await eventually { try overlayShowsFrozenFrame(replacement) }
                #expect(replacement.isVisible)
                #expect(try mainScreenOverlay() === replacement)
            }
        }
    }

    @Test
    func displayChangeBetweenFreezeValidationAndObserverRegistrationIsNotLost() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.queuedDisplayGeometries = [[display.geometry], []]
            fixture.displayGeometries = []
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-display-race-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }
                try fixture.shortcuts.fire()
                try await eventually { fixture.displayReads >= 2 && model.providerSnapshot.activity == nil }
                #expect(!NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver })
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.imageRequests.isEmpty)
            }
        }
    }
}
