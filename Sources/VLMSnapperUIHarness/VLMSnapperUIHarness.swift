import AppKit
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

@main
struct VLMSnapperUIHarness: App {
    @NSApplicationDelegateAdaptor(HarnessApplicationDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            HarnessRoot(mode: HarnessMode(arguments: CommandLine.arguments))
                .preferredColorScheme(
                    CommandLine.arguments.contains("--dark") ? .dark : .light
                )
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
private final class HarnessApplicationDelegate: NSObject, NSApplicationDelegate {
    private var editingSmoke: ProviderEditingSmoke?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--provider-editing-smoke") {
            let smoke = ProviderEditingSmoke()
            editingSmoke = smoke
            DispatchQueue.main.async { smoke.run() }
        }
    }
}

private struct HarnessRoot: View {
    let mode: HarnessMode
    @StateObject private var toolbarState = CaptureToolbarState(targetLanguageCode: "zh-Hans")
    @StateObject private var resultBoxState = HarnessResultBox.state()

    @ViewBuilder
    var body: some View {
        switch mode {
        case .toolbar:
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                VStack(alignment: .leading, spacing: VLMSnapperUIConstants.toolbarSelectionGap) {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 680, height: 210)
                        .overlay {
                            Rectangle().stroke(Color.accentColor, lineWidth: 1)
                        }
                    CaptureOperationToolbar(
                        state: toolbarState,
                        targetLanguages: [
                            TargetLanguageOption(
                                code: "zh-Hans",
                                name: "Chinese (Simplified)"
                            ),
                            TargetLanguageOption(code: "en", name: "English"),
                            TargetLanguageOption(code: "ja", name: "Japanese"),
                        ],
                        onStart: { _ in },
                        onTargetLanguageChange: { _ in },
                        onCopy: {},
                        onSave: {},
                        onCancel: {}
                    )
                }
            }
            .frame(width: 780, height: 320)
        case .result:
            CaptureResultBoxView(
                state: resultBoxState,
                actions: CaptureResultBoxActions(onCopy: { _ in }, onRetry: {}, onRetrySave: {}, onClose: {})
            )
            .frame(width: CaptureResultBoxMetrics.width, height: CaptureResultBoxMetrics.maximumHeight)
        case .onboarding:
            OnboardingView(
                snapshot: OnboardingSession(
                    permission: .ready,
                    provider: .pendingModel(.deepSeek)
                ).snapshot,
                onConfigurePermission: {},
                onConfigureProvider: {},
                onViewPrivacy: {},
                onStart: {},
                onFinishLater: {}
            )
            .frame(width: 680, height: 620)
        case .permission:
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                ScreenCapturePermissionRecoveryView(
                    state: .unavailable,
                    onPrimaryAction: {},
                    onDismiss: {}
                )
            }
            .frame(width: 620, height: 360)
        case .menu:
            MenuBarPanelView(
                recentItems: [
                    MenuRecentItem(
                        id: "1",
                        title: "Designing Calm Software",
                        detail: "DeepSeek · Translate"
                    ),
                    MenuRecentItem(
                        id: "2",
                        title: "Provider setup notes",
                        detail: "OpenAI · Extract Text"
                    ),
                ],
                onCapture: {},
                onOpenRecent: { _ in },
                onNavigate: { _ in },
                onCheckUpdates: {}
            )
        case .privacy:
            StoragePrivacyDetailView(onClose: {})
        }
    }
}

@MainActor
private enum HarnessResultBox {
    static func state() -> CaptureResultBoxState {
        let state = CaptureResultBoxState()
        state.presentation = CaptureResultBoxPresentation(
            operation: .translate,
            targetLanguageName: "Chinese (Simplified)",
            providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
            slot: WorkspaceOperationSlot(
                attempt: .succeeded,
                committedResult: WorkspaceCommittedResult(
                    sourceMarkdown: "# Designing Calm Software\n\nGood utility software stays close to the task.",
                    translationMarkdown: "# Designing Calm Software\n\nUseful software stays close to the current task."
                )
            )
        )
        return state
    }
}

private enum HarnessMode {
    case result
    case toolbar
    case onboarding
    case permission
    case menu
    case privacy

    init(arguments: [String]) {
        if arguments.contains("--toolbar") {
            self = .toolbar
        } else if arguments.contains("--onboarding") {
            self = .onboarding
        } else if arguments.contains("--permission") {
            self = .permission
        } else if arguments.contains("--menu") {
            self = .menu
        } else if arguments.contains("--privacy") {
            self = .privacy
        } else {
            self = .result
        }
    }
}
