import AppKit
import Foundation
import SwiftUI
import Testing
import VLMSnapperCore
import VLMSnapperUI
@testable import VLMSnapperApp

extension ProviderApplicationTests {
    @Test(arguments: [0, 2, 5, 6])
    func recentMenuShowsAtMostFiveSavedRecords(count: Int) async throws {
        try await withFixture { fixture in
            let store = try SQLiteHistoryStore(databaseURL: fixture.root.appendingPathComponent("history.sqlite"))
            let titles = ["Oldest entry", "Meeting notes", "Release notes", "Travel plans", "Project summary", "Latest entry"]
            for title in titles.prefix(count) {
                let prepared = try await store.prepareOperation(
                    screenshot: ManagedScreenshot(path: fixture.root.appendingPathComponent("missing.png").path, sha256: "fixture"),
                    selection: ProviderSelection(providerID: "deepseek", modelID: "fixture-model"),
                    operation: .extractText)
                try await store.finish(operationID: prepared.operationID,
                    with: .succeeded(sourceMarkdown: title, translationMarkdown: nil))
            }
            try await fixture.withModel { model in
                let hosting = NSHostingView(rootView: model.menuView())
                hosting.appearance = NSAppearance(named: .aqua)
                hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 600)
                let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                defer { window.contentView = nil; window.close() }
                window.setContentSize(hosting.fittingSize)
                let text = try renderedText(in: window)
                let visibleTitles: [String]
                switch count {
                case 0: visibleTitles = []
                case 2: visibleTitles = ["Meeting notes", "Oldest entry"]
                case 5: visibleTitles = ["Project summary", "Travel plans", "Release notes", "Meeting notes", "Oldest entry"]
                default: visibleTitles = ["Latest entry", "Project summary", "Travel plans", "Release notes", "Meeting notes"]
                }
                for title in titles {
                    #expect(text.contains(title) == visibleTitles.contains(title), "Unexpected menu visibility for \(title): \(text)")
                }
                #expect(text.contains("Provider") && text.contains("Settings"), "Footer must remain visible")
                #expect(model.historyRecords.count == count, "The menu limit must not truncate stored history")
            }
        }
    }

    @Test
    func applicationStartupOwnsRealWindowsAndReleasesPrimaryLock() async throws {
        try await withFixture { fixture in
            try await fixture.withApplication { application in
                let onboarding = try #require(NSApp.windows.first {
                    $0.isVisible && $0.contentViewController is NSHostingController<OnboardingContainerView>
                })
                #expect(onboarding.isVisible)
                let secondary = fixture.application()
                defer { secondary.stop() }
                #expect(try await secondary.start() == .secondary)
                #expect(fixture.shortcuts.activeRegistrations == 1)
                #expect(fixture.dependencyConstructions == 1)
                #expect(await application.prepareForTermination())
            }
            try await fixture.withApplication { _ in
                #expect(fixture.shortcuts.activeRegistrations == 1)
            }
        }
    }

    @Test
    func injectedUpdateEventsReachTheApplicationPresentation() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                let updates = try #require(fixture.updates)
                #expect(await updates.configuration?.allowsAutomaticDownloads == false)
                let version = AvailableUpdateVersion(version: "2", displayVersion: "2.0")
                await updates.send(.available(version))
                #expect(model.updateState == .available(version))
                #expect(model.settings.updateState == .available(version))
            }
        }
    }

    @Test
    func permissionAndRetentionUseOnlyTheIsolatedPreferences() async throws {
        try await withFixture { fixture in
            let defaults = try #require(UserDefaults(suiteName: fixture.suite))
            defaults.set(true, forKey: "screenCapturePermissionRequested")
            defaults.set(7, forKey: "historyRetentionDays")
            try await fixture.withModel { model in
                #expect(model.permission == .unavailable)
                #expect(model.retention == .sevenDays)
                model.managementCallbacks().onRetentionChange(.sixtyDays)
                try await eventually { model.retention == .sixtyDays }
                #expect(defaults.integer(forKey: "historyRetentionDays") == 60)
            }
            try await fixture.withModel { model in
                #expect(model.retention == .sixtyDays)
            }
        }
    }

    @Test
    func terminationPreparationDoesNotUnregisterBeforeExitIsCommitted() async throws {
        try await withFixture { fixture in
            try await fixture.withModel { model in
                #expect(fixture.shortcuts.activeRegistrations == 1)
                #expect(await model.prepareForTermination())
                #expect(fixture.shortcuts.activeRegistrations == 1)
                model.stop()
                #expect(fixture.shortcuts.activeRegistrations == 0)
                model.stop()
                #expect(fixture.shortcuts.activeRegistrations == 0)
            }
        }
    }
}
