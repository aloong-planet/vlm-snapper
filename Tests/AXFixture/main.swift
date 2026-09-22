import AppKit
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

// An isolated host for the production view. No network, Keychain or user store.
// AX actions are not evidence of physical mouse hit testing or keyboard focus.
@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    let credential = ProviderCredentialEditor(
        loadedValue: CommandLine.arguments.contains("--prefilled") ? "initial-key" : ""
    )
    var blocked = CommandLine.arguments.contains("--blocked")
    var window: NSWindow!
    var expiry: Timer?
    var submissions = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        window = NSWindow(
            contentRect: NSRect(x: 100, y: 100,
                                width: CommandLine.arguments.contains("--narrow") ? 920 : 1200,
                                height: 780),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "AX fixture ready"
        render()
        window.orderBack(nil)
        expiry = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    func render() {
        if CommandLine.arguments.contains("--history-image") {
            let image = NSImage(size: NSSize(width: 1200, height: 300))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 1200, height: 300).fill()
            ("Original screenshot fixture" as NSString).draw(at: NSPoint(x: 40, y: 140),
                withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
            image.unlockFocus()
            let record = HistoryRecord(operation: StoredOperation(id: UUID(),
                screenshot: ManagedScreenshot(path: "/unused-fixture.png", sha256: "fixture"),
                selection: ProviderSelection(providerID: "deepseek", modelID: "fixture"),
                status: .succeeded, sourceMarkdown: "Preview source", translationMarkdown: "Preview translation", kind: .translate),
                createdAt: Date(timeIntervalSince1970: 1_787_725_812), isPinned: false)
            window.contentViewController = NSHostingController(rootView: ManagementCenterView(
                destination: .history, records: [record], selectedRecordID: record.id,
                selectedImage: CommandLine.arguments.contains("--missing-image") ? nil : image))
            return
        }
        let configuration = ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(
                selectedProvider: .deepSeek, availableModelIDs: [], selectedModelID: nil,
                phase: .awaitingValidation, failure: nil,
                activity: blocked ? .credential(.openAI) : nil
            ),
            credentialEditor: credential, pendingModelID: .constant(nil),
            onSelectProvider: { _ in },
            onValidate: { [weak self] submission in
                guard let self else { return }
                submissions += 1
                if CommandLine.arguments.contains("--drop-result") {
                    window.title = "AX fixture result dropped"
                    return
                }
                // Independent expected bytes, not echoed from the scenario input.
                window.title = submission.provider == .deepSeek
                    && submission.value == "poc-key-ax-only"
                    ? "AX fixture validated exact value \(submissions)"
                    : "AX fixture unexpected submission"
                credential.complete(submission, succeeded: true)
            }, onRefresh: {}, onSelectModel: { _ in }
        )
        let root = VStack(spacing: 0) {
            ManagementCenterView(destination: .providerSettings, records: [], providerSettings: configuration)
            HStack {
                Button("Publish fixture snapshot") { self.render() }
                Button("Finish fixture activity") { self.blocked = false; self.render() }
            }.padding(8)
        }
        // Preserve the hosting controller identity across snapshot updates.
        if let host = window.contentViewController as? NSHostingController<AnyView> {
            host.rootView = AnyView(root)
        } else {
            window.contentViewController = NSHostingController(rootView: AnyView(root))
        }
    }
}

let application = NSApplication.shared
let fixture = FixtureDelegate()
application.setActivationPolicy(.accessory)
application.delegate = fixture
withExtendedLifetime(fixture) { application.run() }
