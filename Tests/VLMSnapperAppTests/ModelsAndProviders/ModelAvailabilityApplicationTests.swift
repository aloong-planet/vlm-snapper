import AppKit
import Foundation
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

// Model-list refresh (v1-core section 7, failure mode 11): the Providers' replies are published text, and no live Provider
// was asked. A press on a card's header reaches the same state as the focus request the UI suite drives. A list
// request that never answers is not run: the box's limit is that request's timeout, which a test reads, so a real
// hang needs a server that stalls.
extension ProviderApplicationTests {
    /// v1-core failure modes 10, 56 and 1, with DeepSeek's reply for a model that takes only text.
    @Test
    func aModelThatRejectsImagesIsClearedAndNothingMoreIsSent() async throws {
        try await withResultFixture { fixture, model in
            var onboardingRequests = 0
            model.onShowOnboarding = { onboardingRequests += 1 }
            await fixture.http.rejectImages(status: 400, body: deepSeekTextOnlyModelError)
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually {
                resultBoxPresentation()?.body == .failure("The current model does not support image input.")
            }
            try await waitForResultIdle(model)

            #expect(model.providerReadiness == .pendingModel(.deepSeek))
            #expect(model.providerSnapshot.selectedModelID == nil)
            let configuration = try #require(model.providerConfigurations[.deepSeek])
            #expect(configuration.selectedModelID == nil)
            #expect(configuration.models.first { $0.id == "fixture-vision" }?.visionCompatibility == .incompatible)

            // Pressed right after the failure, Retry already finds no model.
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            try await eventually { resultBoxPresentation()?.body == modelUnavailableInBox }
            #expect(await fixture.http.imageRequests.count == 1)

            let extractTitle = resultBoxPresentation()?.title
            try await clickTranslate(toolbar)
            try await eventually { resultBoxPresentation()?.title != extractTitle }
            #expect(resultBoxPresentation()?.body == modelUnavailableInBox)
            #expect(await fixture.http.imageRequests.count == 1)

            try pressEscape(overlay)
            try await eventually { !captureOverlayIsVisible() }
            try await eventually { model.providerSnapshot.activity == nil }
            try fixture.shortcuts.fire()
            try await eventually { onboardingRequests == 1 }
            #expect(!captureOverlayIsVisible())
            #expect(await fixture.http.imageRequests.count == 1)

            // Choosing it again does not blame the key, and does not select it. The capture's activity ends just
            // after onboarding is requested, and a selection during it is ignored, so this one repeats.
            try await eventually {
                model.providerSettingsConfiguration().onSelectModel("fixture-vision")
                await Task.yield()
                return model.providerSnapshot.failure == .incompatibleModel
            }
            #expect(model.providerReadiness == .pendingModel(.deepSeek))
            let settings = ManagementCenterWindowController(
                records: [], providerSettings: model.providerSettingsConfiguration()
            )
            settings.show(destination: .providerSettings)
            let settingsWindow = try #require(settings.window)
            defer { settingsWindow.orderOut(nil) }
            try await eventually {
                try renderedText(in: settingsWindow).lowercased().contains("does not support image input")
            }
            #expect(!(try renderedText(in: settingsWindow).lowercased().contains("invalid or expired")))
        }
    }

    /// v1-core failure modes 11, 56, 1: a model that has left the list.
    @Test
    func aModelGoneFromTheListIsClearedAndNothingMoreIsSent() async throws {
        try await withResultFixture { fixture, model in
            var onboardingRequests = 0
            model.onShowOnboarding = { onboardingRequests += 1 }
            await fixture.http.rejectImages(status: 400, body: deepSeekMissingModelError)
            await fixture.http.listModels(["fixture-other"])
            let listRequests = await fixture.http.requests.count
            await fixture.http.pause()
            let (overlay, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.requests.count == listRequests + 1 }
            // The box follows the session every 50 ms, so a failure sent too early needs this long to show.
            try await Task.sleep(for: .milliseconds(200))
            pumpNativeEvents(toolbar)

            // The refresh is part of the request, so the box still shows the request.
            let duringRefresh = try #require(resultBoxPresentation())
            #expect(duringRefresh.showsProgress)
            #expect(duringRefresh.body != modelUnavailableInBox)
            #expect(model.isRunningResultRequest)

            await fixture.http.release()
            try await eventually { resultBoxPresentation()?.body == modelUnavailableInBox }
            try await waitForResultIdle(model)

            #expect(await fixture.http.requests.count == listRequests + 1)
            #expect(model.providerReadiness == .pendingModel(.deepSeek))
            #expect(model.providerSnapshot.selectedModelID == nil)
            #expect(model.providerSnapshot.availableModelIDs == ["fixture-other"])

            // Pressed right after the failure, Retry already finds no model.
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            await settleToolbarAction(toolbar)
            #expect(resultBoxPresentation()?.body == modelUnavailableInBox)
            #expect(await fixture.http.imageRequests.count == 1)

            let extractTitle = resultBoxPresentation()?.title
            try await clickTranslate(toolbar)
            try await eventually { resultBoxPresentation()?.title != extractTitle }
            #expect(resultBoxPresentation()?.body == modelUnavailableInBox)
            #expect(await fixture.http.imageRequests.count == 1)
            #expect(await fixture.http.requests.count == listRequests + 1)

            try pressEscape(overlay)
            try await eventually { !captureOverlayIsVisible() }
            try await eventually { model.providerSnapshot.activity == nil }
            try fixture.shortcuts.fire()
            try await eventually { onboardingRequests == 1 }
            #expect(!captureOverlayIsVisible())
            #expect(await fixture.http.imageRequests.count == 1)
        }
    }

    /// v1-core failure mode 11: a refresh that fails keeps the cache, and this attempt still fails.
    @Test
    func aFailedRefreshLeavesTheModelSelected() async throws {
        try await withResultFixture { fixture, model in
            await fixture.http.rejectImages(status: 400, body: deepSeekMissingModelError)
            await fixture.http.respond(with: 503)
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { resultBoxPresentation()?.body == modelUnavailableInBox }
            try await waitForResultIdle(model)

            #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])

            await settleToolbarAction(toolbar)
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 2 }
        }
    }

    /// v1-core section 7: one refresh for each attempt, and a model still listed stays selected.
    @Test
    func aModelStillListedStaysSelectedAndEachAttemptRefreshesOnce() async throws {
        try await withResultFixture { fixture, model in
            await fixture.http.rejectImages(status: 400, body: deepSeekMissingModelError)
            let listRequests = await fixture.http.requests.count
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { resultBoxPresentation()?.body == modelUnavailableInBox }
            try await waitForResultIdle(model)
            #expect(await fixture.http.requests.count == listRequests + 1)
            #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))

            await settleToolbarAction(toolbar)
            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 2 }
            try await waitForResultIdle(model)
            #expect(await fixture.http.requests.count == listRequests + 2)
        }
    }

    /// v1-core section 7: a capture does not refresh a stale cache, and opening the Provider page does, once.
    @Test
    func aStaleCacheRefreshesOnlyWhenTheProviderPageOpens() async throws {
        try await withFixture { fixture in
            fixture.permissionGranted = true
            let display = try syntheticDisplay()
            await fixture.capture.provide(display)
            fixture.displayGeometries = [display.geometry]
            try await saveStaleProviders(in: fixture, [.deepSeek])
            try await fixture.withModel { model in
                let (overlay, _) = try await completeSelection(fixture)
                #expect(await fixture.http.requests.isEmpty)
                try pressEscape(overlay)
                try await eventually { !captureOverlayIsVisible() }
                try await eventually { model.providerSnapshot.activity == nil }

                // Showing History loads the session's card too, which must not count as opening it.
                model.credentialEditor.close()
                let settings = ManagementCenterWindowController(
                    records: [], providerSettings: model.providerSettingsConfiguration()
                )
                settings.show(destination: .history)
                let window = try #require(settings.window)
                defer { window.orderOut(nil) }
                try await eventually { !model.credentialEditor.isLoading && model.credentialEditor.isOpen }
                try await Task.sleep(for: .milliseconds(200))
                pumpNativeEvents(window)
                #expect(await fixture.http.requests.isEmpty)

                settings.show(destination: .providerSettings)
                try await eventually { await fixture.http.requests.count == 1 }
                try await eventually { model.providerSnapshot.refreshingProvider == nil }
                settings.show(destination: .providerSettings)
                try await Task.sleep(for: .milliseconds(200))
                pumpNativeEvents(window)
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }

    /// v1-core failure modes 11, 56, from a history record. Windowless.
    @Test
    func aHistoryRetryWhoseModelIsGoneClearsIt() async throws {
        try await withFixture { fixture in
            let recordID = try await savedExtractionRecord(in: fixture)
            await fixture.http.allowImageRequests()
            await fixture.http.rejectImages(status: 400, body: deepSeekMissingModelError)
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-history-key")
                try await eventually { model.historyRetry.allowsStart }
                await fixture.http.listModels(["fixture-other"])
                let listRequests = await fixture.http.requests.count

                model.managementCallbacks().onRetryRecord(recordID)
                try await eventually {
                    await fixture.http.imageRequests.count == 1 && !model.historyRetry.isRunning
                }

                #expect(model.historyRetry.slot.attempt == .failed(code: "model_unavailable"))
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(model.providerSnapshot.selectedModelID == nil)
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-other"])
                #expect(await fixture.http.requests.count == listRequests + 1)
                // The box shows the request until the refresh ends, at the latest this timeout.
                #expect(await fixture.http.requests.last?.timeoutInterval == 60)
                #expect(!model.historyRetry.allowsStart)
                let saved = try await SQLiteHistoryStore(
                    databaseURL: fixture.root.appendingPathComponent("history.sqlite")
                ).historyRecord(id: recordID)
                #expect(saved?.operation.sourceMarkdown == "Archived original")
            }
        }
    }

    /// v1-core failure mode 11, from a history record. Windowless.
    @Test
    func aHistoryRetryWhoseRefreshFailsKeepsTheModel() async throws {
        try await withFixture { fixture in
            let recordID = try await savedExtractionRecord(in: fixture)
            await fixture.http.allowImageRequests()
            await fixture.http.rejectImages(status: 400, body: deepSeekMissingModelError)
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-history-key")
                try await eventually { model.historyRetry.allowsStart }
                await fixture.http.respond(with: 503)

                model.managementCallbacks().onRetryRecord(recordID)
                try await eventually {
                    await fixture.http.imageRequests.count == 1 && !model.historyRetry.isRunning
                }

                #expect(model.historyRetry.slot.attempt == .failed(code: "model_unavailable"))
                #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
                #expect(model.providerSnapshot.availableModelIDs == ["fixture-vision"])
                #expect(model.historyRetry.allowsStart)
            }
        }
    }

    /// v1-core section 7: not at startup; once on opening; a draft stays. Windowless.
    @Test
    func aStaleCacheIsNotRefreshedAtStartupAndIsOnceOnOpening() async throws {
        try await withFixture { fixture in
            try await saveStaleProviders(in: fixture, [.deepSeek])
            try await fixture.withModel { model in
                #expect(await fixture.http.requests.isEmpty)
                let controls = model.providerSettingsConfiguration()
                try await eventually { !model.credentialEditor.isLoading }
                model.credentialEditor.edit("fixture-draft")

                controls.onOpenProviderCard(.deepSeek)
                try await eventually { await fixture.http.requests.count == 1 }
                try await eventually { model.providerSnapshot.refreshingProvider == nil }
                #expect(model.credentialEditor.value == "fixture-draft")
                #expect(model.providerSnapshot.failure == nil)

                // The cache is new now.
                controls.onOpenProviderCard(.deepSeek)
                try await Task.sleep(for: .milliseconds(200))
                #expect(await fixture.http.requests.count == 1)
            }
        }
    }

    /// v1-core section 7: a load is not an opening, and an opening with its card's load gives one refresh. Windowless.
    @Test
    func aCardsLoadRefreshesOnlyWithAnOpening() async throws {
        try await withFixture { fixture in
            try await saveStaleProviders(in: fixture, [.deepSeek, .openAI])
            try await fixture.withModel { model in
                let controls = model.providerSettingsConfiguration()
                controls.onSelectProvider(.openAI)
                try await eventually {
                    model.providerSnapshot.selectedProvider == .openAI && !model.credentialEditor.isLoading
                }
                try await Task.sleep(for: .milliseconds(200))
                #expect(await fixture.http.requests.isEmpty)

                controls.onSelectProvider(.deepSeek)
                controls.onOpenProviderCard(.deepSeek)
                try await eventually { await fixture.http.requests.count >= 1 }
                try await eventually {
                    model.providerSnapshot.selectedProvider == .deepSeek
                        && model.providerSnapshot.refreshingProvider == nil
                        && !model.credentialEditor.isLoading
                }
                try await Task.sleep(for: .milliseconds(200))
                #expect(await fixture.http.requests.count == 1)
                #expect(await fixture.http.requests.last?.value(forHTTPHeaderField: "Authorization")
                    == "Bearer fixture-deepseek-key")
            }
        }
    }

    /// v1-core failure mode 10, from Translate: the session reloads for that operation's result too.
    @Test
    func aTranslationTheModelRejectsClearsIt() async throws {
        try await withResultFixture { fixture, model in
            await fixture.http.rejectImages(status: 400, body: deepSeekTextOnlyModelError)
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickTranslate(toolbar)
            try await eventually {
                resultBoxPresentation()?.body == .failure("The current model does not support image input.")
            }
            try await waitForResultIdle(model)

            #expect(model.providerSnapshot.selectedModelID == nil)
            #expect(model.providerReadiness == .pendingModel(.deepSeek))
        }
    }

    /// v1-core failure mode 10: an error about the image rather than the model changes nothing.
    @Test
    func anUnsupportedImageFormatLeavesTheModelSelected() async throws {
        try await withResultFixture { fixture, model in
            await fixture.http.rejectImages(status: 400, body: openAIUnsupportedImageError)
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually {
                resultBoxPresentation()?.body == .failure("The request failed. Review the error details and retry manually.")
            }
            try await waitForResultIdle(model)

            #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
            let configuration = try #require(model.providerConfigurations[.deepSeek])
            #expect(configuration.selectedModelID == "fixture-vision")
            #expect(configuration.models.first { $0.id == "fixture-vision" }?.visionCompatibility == .unknown)

            try clickResultBoxButton(try #require(resultBox()), fromEnd: 1)
            try await eventually { await fixture.http.imageRequests.count == 2 }
        }
    }

    /// v1-core: the first real image operation verifies the model.
    @Test
    func theFirstSuccessfulRequestVerifiesTheModel() async throws {
        try await withResultFixture { fixture, model in
            let (_, toolbar) = try await completeSelection(fixture)
            try await clickExtract(toolbar)
            try await eventually { await fixture.http.imageRequests.count == 1 }
            try await fixture.http.finishImage(source: "Source")
            try await waitForResultIdle(model)
            try await eventually {
                model.providerConfigurations[.deepSeek]?.models.first { $0.id == "fixture-vision" }?
                    .visionCompatibility == .verified
            }
            #expect(model.providerReadiness == .ready(provider: .deepSeek, modelID: "fixture-vision"))
        }
    }

    /// v1-core failure mode 10, from a history record rather than a capture.
    @Test
    func aHistoryRetryTheModelRejectsClearsIt() async throws {
        try await withFixture { fixture in
            let record = try await savedExtractionRecord(in: fixture)
            await fixture.http.allowImageRequests()
            await fixture.http.rejectImages(status: 400, body: deepSeekTextOnlyModelError)
            try await fixture.withModel { model in
                try await makeCaptureReady(model, key: "fixture-history-key")
                try await eventually { model.historyRetry.allowsStart }

                model.managementCallbacks().onRetryRecord(record)
                try await eventually {
                    await fixture.http.imageRequests.count == 1 && !model.historyRetry.isRunning
                }

                #expect(model.historyRetry.slot.attempt == .failed(code: "image_input_unsupported"))
                #expect(model.providerReadiness == .pendingModel(.deepSeek))
                #expect(model.providerSnapshot.selectedModelID == nil)
                #expect(model.providerConfigurations[.deepSeek]?.models.first { $0.id == "fixture-vision" }?
                    .visionCompatibility == .incompatible)
                #expect(!model.historyRetry.allowsStart)
            }
        }
    }
}
