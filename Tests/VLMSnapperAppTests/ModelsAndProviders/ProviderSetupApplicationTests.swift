import AppKit
import Foundation
import SwiftUI
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

extension ProviderApplicationTests {
    @Test
    func modelRefreshPublishesProgressAndFailureWithoutChangingCredentialState() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                let controls = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-refresh-key")
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: controls.onValidate
                ))
                try await eventually { model.providerSnapshot.phase == .selectingModel }
                controls.onSelectModel("fixture-vision")
                try await eventually { model.providerSnapshot.phase == .ready }
                await fixture.http.pause()
                await fixture.http.respond(with: 503)
                controls.onRefresh()
                try await eventually { model.providerSnapshot.refreshingProvider == .deepSeek }
                #expect(model.providerSnapshot.phase == .ready)
                #expect(model.providerSnapshot.blocksConfigurationChanges)
                #expect(!model.credentialEditor.isSubmitting)
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])
                try await eventually { await fixture.http.requests.count == 2 }
                await fixture.http.release()
                try await eventually {
                    model.providerSnapshot.refreshingProvider == nil
                        && model.providerSnapshot.modelRefreshFailure == .unavailable
                }
                #expect(model.providerSnapshot.failure == nil)
                #expect(model.providerSnapshot.phase == .ready)
                #expect(model.providerSnapshot.blocksConfigurationChanges == false)
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-refresh-key")
                #expect(await fixture.http.requests.count == 2)
                await fixture.http.respond(with: 200)
                controls.onRefresh()
                try await eventually {
                    let requestCount = await fixture.http.requests.count
                    return model.providerSnapshot.refreshingProvider == nil
                        && model.providerSnapshot.modelRefreshFailure == nil
                        && requestCount == 3
                }
                #expect(model.providerSnapshot.selectedModelID == "fixture-vision")
            }
        }
    }

    @Test
    func nativeValidateSurvivesCloseAndReopenWhileResponseIsPending() async throws {
        try await withFixture { fixture in
            await fixture.http.pause()
            try await fixture.withApplication { _ in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                try await openProviderFromOnboarding(onboarding)
                let management = try #require(NSApp.windows.first { $0.isVisible && $0.title == "VLMSnapper" && $0 !== onboarding })
                let field = try await editableSecureField(in: management)
                #expect(management.makeFirstResponder(field))
                let editor = try #require(field.currentEditor() as? NSTextView)
                editor.insertText("fixture-window-key", replacementRange: editor.selectedRange())
                try await eventually {
                    pumpNativeEvents(management)
                    return field.stringValue == "fixture-window-key"
                }
                #expect(editor.selectedRange() == NSRange(location: 18, length: 0))
                // Locate the native field, then click the action immediately
                // beneath its trailing edge in the confirmed Provider layout.
                try clickValidate(below: field, in: management)
                try await eventually { await fixture.http.requests.count == 1 }
                #expect(await fixture.http.requests.first?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer fixture-window-key")
                management.performClose(nil)
                try await eventually { onboarding.isVisible && !management.isVisible }
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)
                try await openProviderFromOnboarding(onboarding)
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map {
                        descendants($0).compactMap { $0 as? NSSecureTextField }.contains {
                            $0.stringValue == "fixture-window-key" && !$0.isEditable
                        }
                    } == true
                }
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)
                await fixture.http.release()
                let reopenedField = try await editableSecureField(in: management)
                #expect(reopenedField.stringValue == "fixture-window-key")
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map {
                        descendants($0).compactMap { $0 as? NSPopUpButton }.contains { $0.itemTitles.contains("fixture-vision") }
                    } == true
                }
                #expect(await fixture.http.requests.count == 1)
                #expect(!onboarding.isVisible)
                #expect(management.isVisible)
            }
            try await fixture.withModel { model in
                #expect(model.credentialEditor.value == "fixture-window-key")
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }

    @Test
    func nativeCaptureAndRerunPreserveHistoryWhileProviderValidationIsExclusive() async throws {
        let trace = NativeWaitTrace(name: "capture")
        defer { trace.emit() }
        try await withFixture { fixture in
            fixture.permissionGranted = true
            await fixture.capture.provide(try syntheticDisplay())
            await fixture.http.allowImageRequests()
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-image-key")
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
                pumpNativeEvents(overlay)
                trace.record("overlay-ready", window: overlay)
                try drag(overlay, from: NSPoint(x: 100, y: 200), to: NSPoint(x: 300, y: 300), trace: trace)
                try await eventually {
                    trace.record("toolbar-wait", window: overlay)
                    return NSApp.windows.contains { $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar> }
                }
                trace.record("toolbar-ready")
                let toolbar = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentView is NSHostingView<CaptureOperationToolbar>
                })
                // While the selection can still be adjusted, displays stay monitored (v1-core::REQ-007/AC-07);
                // an unchanged geometry leaves the selection and its toolbar alone.
                let selectingReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await eventually { fixture.displayReads > selectingReads }
                #expect(toolbar.isVisible)
                try await eventually { model.providerSnapshot.activity == .capture }
                model.credentialEditor.edit("fixture-during-selection")
                let selectionBlocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: selectionBlocked.snapshot.blocksConfigurationChanges,
                    operation: selectionBlocked.onValidate))
                #expect(await fixture.http.requests.count == 1)
                pumpNativeEvents(toolbar)
                // Center of the first operation button in the production toolbar.
                let toolbarContent = try #require(toolbar.contentView)
                try click(toolbar, at: NSPoint(x: 40, y: toolbarContent.bounds.midY))
                try await eventually { await fixture.http.imageRequests.count == 1 }
                // Displays stay monitored until the capture ends (v1-core::REQ-001/AC-07).
                let operationReads = fixture.displayReads
                fixture.displayNotifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
                try await eventually { fixture.displayReads > operationReads }
                #expect(toolbar.isVisible)
                try await eventually { model.providerSnapshot.activity == .modelRequest }
                model.credentialEditor.edit("fixture-during-image")
                let blocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: blocked.snapshot.blocksConfigurationChanges, operation: blocked.onValidate))
                #expect(await fixture.http.requests.count == 1)
                #expect(model.credentialEditor.value == "fixture-during-image")
                try await fixture.http.finishImage(source: "First result")
                try await eventually { model.historyRecords.count == 1 }
                let originalID = try #require(model.historyRecords.first?.id)
                #expect(model.historyRecords.first?.operation.sourceMarkdown == "First result")
                let originalHistory = model.historyRecords
                // The open capture keeps Provider configuration read-only (failure mode 44).
                try await eventually { model.providerSnapshot.activity == .capture }
                #expect(model.providerSnapshot.blocksConfigurationChanges)
                let result = try #require(resultBox())
                let stillBlocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: stillBlocked.snapshot.blocksConfigurationChanges, operation: stillBlocked.onValidate))
                #expect(await fixture.http.requests.count == 1)
                pumpNativeEvents(result)
                try clickResultBoxButton(result, fromEnd: 1)
                try await eventually { await fixture.http.imageRequests.count == 2 }
                #expect(model.historyRecords == originalHistory)

                // External credential truth after an interrupted publication:
                // a saved key with no metadata. Opening that card must wait
                // for this in-flight rerun, and for the capture that made it, before starting recovery HTTP.
                await fixture.credentials.replaceCredential(
                    ProviderCredential(generation: UUID(), apiKey: "fixture-recovery-key"), for: .openAI
                )
                await fixture.http.pause()
                model.providerSettingsConfiguration().onSelectProvider(.openAI)
                try await eventually {
                    model.providerSnapshot.selectedProvider == .openAI && model.credentialEditor.isLoading
                }
                #expect(model.providerSnapshot.activity == .modelRequest)
                #expect(await fixture.http.requests.count == 1)
                #expect(model.historyRecords == originalHistory)
                try await fixture.http.finishImage(source: "Replacement result")
                try await eventually { model.historyRecords.first?.operation.sourceMarkdown == "Replacement result" }
                #expect(model.historyRecords.count == 1)
                #expect(model.historyRecords.first?.id == originalID)
                try await eventually { model.providerSnapshot.activity == .capture }
                #expect(await fixture.http.requests.count == 1)
                try pressEscape(overlay)
                try await eventually {
                    await fixture.http.requests.count == 2 && model.providerSnapshot.phase == .recovering
                }
                #expect(await fixture.http.requests.last?.url?.host == "api.openai.com")
                let recoveredHistory = model.historyRecords
                var recoveryNavigations = 0
                model.onNavigate = { if $0 == .providerSettings { recoveryNavigations += 1 } }
                try fixture.shortcuts.fire()
                try await eventually { recoveryNavigations == 1 }
                #expect(await fixture.capture.requests == 1)
                await fixture.http.release()
                try await eventually {
                    !model.credentialEditor.isLoading && model.providerSnapshot.activity == nil
                        && model.providerSnapshot.availableModelIDs == ["fixture-vision"]
                }
                #expect(model.credentialEditor.value == "fixture-recovery-key")
                #expect(await fixture.http.imageRequests.count == 2)
                #expect(model.historyRecords == recoveredHistory)
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            }
        }
    }

    @Test
    func credentialValidationAndFreezingExcludeEachOtherThroughApplicationWiring() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            try await fixture.withModel { model in
                model.credentialEditor.edit("fixture-initial-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { model.providerReadiness == .pendingModel(.deepSeek) }
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                try await eventually {
                    model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }

                await fixture.http.pause()
                model.credentialEditor.edit("fixture-replacement-key")
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { await fixture.http.requests.count == 2 }
                var providerNavigations = 0
                model.onNavigate = { if $0 == .providerSettings { providerNavigations += 1 } }
                try fixture.shortcuts.fire()
                try await eventually { providerNavigations == 1 }
                #expect(await fixture.capture.requests == 0)
                #expect(await fixture.http.requests.count == 2)
                #expect(model.historyRecords.isEmpty)
                await fixture.http.release()
                try await eventually {
                    !model.credentialEditor.isSubmitting && model.providerReadiness
                        == .ready(provider: .deepSeek, modelID: "fixture-vision")
                }

                await fixture.capture.allowSuspendedCapture()
                try fixture.shortcuts.fire()
                try await eventually { await fixture.capture.requests == 1 }
                try await eventually { model.providerSnapshot.blocksConfigurationChanges }
                model.credentialEditor.edit("fixture-after-capture-key")
                let blocked = model.providerSettingsConfiguration()
                #expect(!model.credentialEditor.submit(for: .deepSeek,
                    isReadOnly: blocked.snapshot.blocksConfigurationChanges, operation: blocked.onValidate))
                #expect(model.credentialEditor.value == "fixture-after-capture-key")
                #expect(await fixture.http.requests.count == 2)
                #expect(model.historyRecords.isEmpty)

                var permissionPrompts = 0
                model.onShowOnboarding = { permissionPrompts += 1 }
                await fixture.capture.release()
                try await eventually {
                    permissionPrompts == 1 && !model.providerSnapshot.blocksConfigurationChanges
                }
                #expect(model.credentialEditor.submit(for: .deepSeek, isReadOnly: false,
                    operation: model.providerSettingsConfiguration().onValidate))
                try await eventually { await fixture.http.requests.count == 3 }
                try await eventually { !model.credentialEditor.isSubmitting }
                #expect(model.historyRecords.isEmpty)
            }
        }
    }

    @Test
    func nativeOnboardingValidatesSelectsAndReturns() async throws {
        try await withFixture { fixture in
            try await fixture.withApplication { _ in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                try await eventually {
                    pumpNativeEvents(onboarding)
                    return onboarding.contentView?.bounds.width ?? 0 > 0
                }
                let onboardingContent = try #require(onboarding.contentView)
                onboardingContent.layoutSubtreeIfNeeded()
                // Point in the Provider row's trailing action in the fixed
                // production onboarding render; success requires actual routing.
                try await openProviderFromOnboarding(onboarding)
                try await eventually { !onboarding.isVisible }
                let management = try #require(NSApp.windows.first {
                    $0.isVisible && $0 !== onboarding && $0.title == "VLMSnapper"
                })
                try await eventually {
                    pumpNativeEvents(management)
                    return management.contentView.map { descendants($0).contains { $0 is NSSecureTextField } } == true
                }
                let content = try #require(management.contentView)
                let field = try #require(descendants(content)
                    .compactMap { $0 as? NSSecureTextField }.first)
                #expect(management.makeFirstResponder(field))
                let editor = try #require(field.currentEditor() as? NSTextView)
                editor.insertText("fixture-native-key", replacementRange: editor.selectedRange())
                pumpNativeEvents(management)
                editor.interpretKeyEvents([try #require(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: management.windowNumber, context: nil, characters: "\r",
                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
                ))])
                try await eventually { await fixture.http.requests.count == 1 }
                try await eventually { await fixture.credentials.credential(for: .deepSeek) != nil }
                #expect(management.isVisible)
                #expect(!onboarding.isVisible)
                try await eventually {
                    pumpNativeEvents(management)
                    return descendants(content).compactMap { $0 as? NSPopUpButton }
                        .contains { $0.itemTitles.contains("fixture-vision") }
                }
                // Closing before choosing a model returns to onboarding, then
                // reopening uses persisted credentials rather than the old draft.
                management.performClose(nil)
                try await eventually { onboarding.isVisible && !management.isVisible }
                pumpNativeEvents(onboarding)
                try await openProviderFromOnboarding(onboarding)
                try await eventually {
                    pumpNativeEvents(management)
                    return management.isVisible && !onboarding.isVisible
                        && descendants(content).compactMap { $0 as? NSPopUpButton }
                            .contains { $0.isEnabled && $0.itemTitles.contains("fixture-vision") }
                }
                let picker = try #require(descendants(content).compactMap { $0 as? NSPopUpButton }
                    .first { $0.itemTitles.contains("fixture-vision") })
                #expect(management.isVisible)
                #expect(!onboarding.isVisible)
                let menu = try #require(picker.menu)
                let index = menu.indexOfItem(withTitle: "fixture-vision")
                #expect(index >= 0)
                let item = try #require(menu.item(at: index))
                _ = try #require(item.action)
                menu.performActionForItem(at: index)
                try await eventually { onboarding.isVisible && !management.isVisible }
                #expect(await fixture.http.requests.count == 1)
            }
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-native-key")
            }
        }
    }

    @Test(arguments: [401, 500])
    func failedValidationKeepsCandidateAndAllowsManualRetry(status: Int) async throws {
        try await withFixture { fixture in
            await fixture.http.respond(with: status)
            try await fixture.withModel { model in
                let configuration = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-rejected-key")
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting && model.providerSnapshot.phase == .failed
                }
                #expect(model.providerReadiness == .missing)
                #expect(model.credentialEditor.value == "fixture-rejected-key")
                #expect(model.credentialEditor.isDirty)
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.credentials.credential(for: .deepSeek) == nil)

                await fixture.http.respond(with: 200)
                #expect(model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting
                        && model.providerReadiness == .pendingModel(.deepSeek)
                }
                #expect(await fixture.http.requests.count == 2)
            }
        }
    }

    @Test
    func validatesSelectsAndRestoresProviderThroughApplicationCallbacks() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .missing)
                let configuration = model.providerSettingsConfiguration()
                model.credentialEditor.edit("fixture-not-a-real-key")
                let accepted = model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                )
                #expect(accepted)
                #expect(!model.credentialEditor.submit(
                    for: .deepSeek, isReadOnly: false, operation: configuration.onValidate
                ))
                try await eventually {
                    !model.credentialEditor.isSubmitting
                        && model.providerSnapshot.availableModelIDs == ["fixture-vision"]
                        && model.providerReadiness == .pendingModel(.deepSeek)
                }
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.http.requests.first?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer fixture-not-a-real-key")

                var completions = 0
                model.onProviderConfigurationCompleted = { completions += 1 }
                configuration.onSelectModel("fixture-vision")
                try await eventually { completions == 1 }
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            }
            // Construct a fresh application model/session/coordinator over the same
            // isolated credential adapter and real metadata files.
            try await fixture.withModel { model in
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.credentialEditor.value == "fixture-not-a-real-key")
                #expect(model.historyRecords.isEmpty)
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }
}
