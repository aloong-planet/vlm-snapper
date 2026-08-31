import AppKit
import Combine
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

@MainActor
final class VLMSnapperApplicationDelegate: NSObject, NSApplicationDelegate {
    private var primaryCoordinator: PrimaryInstanceCoordinator?
    private var model: VLMSnapperApplicationModel?
    private var menuController: MenuBarPanelController<MenuBarContainerView>?
    private var managementController: ManagementCenterWindowController?
    private var onboardingController: NSWindowController?
    private var onboardingHostingController: NSHostingController<OnboardingContainerView>?
    private var isPreparingForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !isPreparingForTermination else { return .terminateLater }
        isPreparingForTermination = true
        Task {
            let canTerminate = await model.prepareForTermination()
            isPreparingForTermination = false
            sender.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }

    private func start() async {
        do {
            let root = try ApplicationDirectories.applicationSupportRoot()
            let coordinator = PrimaryInstanceCoordinator(
                lock: POSIXPrimaryInstanceLock(
                    lockFileURL: root.appendingPathComponent("primary.lock")
                ),
                messaging: DistributedPrimaryInstanceMessaging()
            )
            primaryCoordinator = coordinator
            let role = try await coordinator.start(
                onActivation: { [weak self] in
                    await self?.activatePrimarySurface()
                },
                initializePrimary: { [weak self] in
                    try await self?.initializePrimary(root: root)
                }
            )
            if role == .secondary {
                NSApp.terminate(nil)
            }
        } catch {
            let message = "VLMSnapper startup failed: \(error)\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            NSApp.terminate(nil)
        }
    }

    private func initializePrimary(root: URL) async throws {
        let languageStore = UserDefaultsApplicationLanguageStore()
        let preference = await languageStore.load()
        let effectiveLanguage = ApplicationLanguageResolver().resolve(
            preference: preference,
            preferredLanguages: Locale.preferredLanguages
        )
        VLMSnapperLocalization.configure(effectiveLanguage: effectiveLanguage)

        let model = try VLMSnapperApplicationModel(
            applicationSupportRoot: root,
            languageStore: languageStore
        )
        self.model = model
        model.onSnapshotChange = { [weak self] in
            self?.refreshPresentedSurfaces()
        }
        model.onNavigate = { [weak self] destination in
            self?.showManagementCenter(destination: destination)
        }
        model.onShowOnboarding = { [weak self] in
            self?.showOnboarding()
        }

        let menuController = MenuBarPanelController(
            content: model.menuView(),
            onQuit: { NSApp.terminate(nil) }
        )
        self.menuController = menuController
        try await model.start()
        refreshPresentedSurfaces()
        if !model.hasFinishedOnboarding {
            showOnboarding()
        }
    }

    private func refreshPresentedSurfaces() {
        guard let model else { return }
        menuController?.update(content: model.menuView())
        menuController?.updateIndicator(for: model.updateState)
        if onboardingController?.window?.isVisible == true {
            onboardingHostingController?.rootView = model.onboardingView()
        }
        managementController?.update(
            records: model.historyRecords,
            selectedRecordID: model.selectedHistoryRecordID,
            selectedImage: model.selectedHistoryImage,
            cleanupFailureCount: model.cleanupFailureCount,
            retention: model.retention,
            settings: model.settings,
            providerSettings: model.providerSettingsConfiguration()
        )
    }

    private func showOnboarding() {
        guard let model else { return }
        if let onboardingController {
            onboardingHostingController?.rootView = model.onboardingView()
            onboardingController.showWindow(nil)
            onboardingController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VLMSnapper"
        window.center()
        let hostingController = NSHostingController(rootView: model.onboardingView())
        onboardingHostingController = hostingController
        window.contentViewController = hostingController
        let controller = NSWindowController(window: window)
        onboardingController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showManagementCenter(destination: ManagementCenterDestination) {
        guard let model else { return }
        if managementController == nil {
            managementController = ManagementCenterWindowController(
                records: model.historyRecords,
                selectedRecordID: model.selectedHistoryRecordID,
                selectedImage: model.selectedHistoryImage,
                cleanupFailureCount: model.cleanupFailureCount,
                retention: model.retention,
                settings: model.settings,
                providerSettings: model.providerSettingsConfiguration(),
                callbacks: model.managementCallbacks()
            )
        }
        managementController?.show(destination: destination)
    }

    private func activatePrimarySurface() {
        if let keyWindow = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            keyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            menuController?.show()
        }
    }
}
