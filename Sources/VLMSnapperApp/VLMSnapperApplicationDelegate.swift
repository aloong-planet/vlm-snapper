import AppKit
import Combine
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

@MainActor
final class VLMSnapperApplicationDelegate: NSObject, NSApplicationDelegate {
    private let makeStartupDependencies: () throws -> ApplicationStartupDependencies
    private var primaryCoordinator: PrimaryInstanceCoordinator?
    private var model: VLMSnapperApplicationModel?
    private var menuController: MenuBarPanelController<MenuBarContainerView>?
    private var managementController: ManagementCenterWindowController?
    private var onboardingController: NSWindowController?
    private var onboardingHostingController: NSHostingController<OnboardingContainerView>?
    private var isPreparingForTermination = false
    private var providerSettingsReturnContext = ProviderSettingsReturnContext()
    private var startupTask: Task<Void, Never>?

    override convenience init() {
        self.init(makeStartupDependencies: { try .live() })
    }

    init(makeStartupDependencies: @escaping () throws -> ApplicationStartupDependencies) {
        self.makeStartupDependencies = makeStartupDependencies
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startupTask = Task {
            do {
                if try await start() == .secondary { NSApp.terminate(nil) }
            } catch {
                guard !Task.isCancelled else { return }
                let message = "VLMSnapper startup failed: \(error)\n"
                try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func prepareForTermination() async -> Bool {
        await model?.prepareForTermination() ?? true
    }

    func stop() {
        startupTask?.cancel()
        providerSettingsReturnContext = ProviderSettingsReturnContext()
        model?.stop()
        managementController?.close()
        onboardingController?.close()
        menuController?.stop()
        managementController = nil
        onboardingController = nil
        onboardingHostingController = nil
        menuController = nil
        model = nil
        primaryCoordinator = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model != nil else {
            startupTask?.cancel()
            return .terminateNow
        }
        guard !isPreparingForTermination else { return .terminateLater }
        isPreparingForTermination = true
        Task {
            let canTerminate = await prepareForTermination()
            if canTerminate { startupTask?.cancel() }
            isPreparingForTermination = false
            sender.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }

    func start() async throws -> PrimaryInstanceRole {
        let dependencies = try makeStartupDependencies()
        let coordinator = PrimaryInstanceCoordinator(
            lock: POSIXPrimaryInstanceLock(
                lockFileURL: dependencies.root.appendingPathComponent("primary.lock")
            ),
            messaging: dependencies.messaging
        )
        primaryCoordinator = coordinator
        return try await coordinator.start(
            onActivation: { [weak self] in
                await self?.activatePrimarySurface()
            },
            initializePrimary: { [weak self] in
                try await self?.initializePrimary(dependencies: dependencies)
            }
        )
    }

    private func initializePrimary(dependencies: ApplicationStartupDependencies) async throws {
        let languageStore = UserDefaultsApplicationLanguageStore(defaults: dependencies.defaults)
        let preference = await languageStore.load()
        let effectiveLanguage = ApplicationLanguageResolver().resolve(
            preference: preference,
            preferredLanguages: Locale.preferredLanguages
        )
        VLMSnapperLocalization.configure(effectiveLanguage: effectiveLanguage)
        NSApp.mainMenu = VLMSnapperApplicationMenuBuilder.makeMainMenu(
            applicationName: "VLMSnapper", pasteboard: dependencies.pasteboard
        )

        let model = try VLMSnapperApplicationModel(
            applicationSupportRoot: dependencies.root,
            languageStore: languageStore,
            defaults: dependencies.defaults,
            dependencies: try dependencies.makeModelDependencies()
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
        model.onOpenProviderSettingsFromOnboarding = { [weak self] in
            self?.openProviderSettingsFromOnboarding()
        }
        model.onProviderConfigurationCompleted = { [weak self] in
            self?.completeProviderSettingsFromOnboardingIfNeeded()
        }
        model.onRetireManagementCenter = { [weak self] action in
            guard let controller = self?.managementController else {
                action()
                return
            }
            controller.performAfterHiding(action)
        }
        model.onRetireCaptureSources = { [weak self] in
            self?.menuController?.hideForCapture()
            self?.managementController?.hideForCapture()
            self?.onboardingController?.window?.orderOut(nil)
        }

        let menuController = MenuBarPanelController(
            content: model.menuView(),
            onQuit: { NSApp.terminate(nil) }
        )
        self.menuController = menuController
        try await model.start()
        try Task.checkCancellation()
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
            presentOnboarding(onboardingController)
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
        presentOnboarding(controller)
    }

    private func presentOnboarding(_ controller: NSWindowController) {
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
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
                callbacks: model.managementCallbacks(),
                onClose: { [weak self] in
                    self?.returnToOnboardingIfNeeded()
                }
            )
        }
        managementController?.show(destination: destination)
    }

    private func openProviderSettingsFromOnboarding() {
        providerSettingsReturnContext.beginFromOnboarding()
        onboardingController?.window?.orderOut(nil)
        showManagementCenter(destination: .providerSettings)
    }

    private func completeProviderSettingsFromOnboardingIfNeeded() {
        guard providerSettingsReturnContext.consumeAfterModelSelection() else { return }
        managementController?.window?.orderOut(nil)
        showOnboarding()
    }

    private func returnToOnboardingIfNeeded() {
        guard providerSettingsReturnContext.consumeAfterWindowClose() else { return }
        showOnboarding()
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
