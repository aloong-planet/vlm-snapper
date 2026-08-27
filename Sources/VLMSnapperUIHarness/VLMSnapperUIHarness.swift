import AppKit
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

@main
struct VLMSnapperUIHarness: App {
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

private struct HarnessRoot: View {
    let mode: HarnessMode
    @State private var operation: WorkspaceOperationKind = .translate
    @State private var apiKey = ""
    @State private var modelID: String? = "deepseek-v4-flash-vision-exp"

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
                        operation: $operation,
                        targetLanguage: "Chinese (Simplified)",
                        providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
                        onStart: { _ in },
                        onCancel: {}
                    )
                }
            }
            .frame(width: 780, height: 320)
        case .result:
            ResultWorkspaceView(
                operation: $operation,
                snapshot: sampleSnapshot,
                originalImage: sampleImage,
                providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
                targetLanguage: "Chinese (Simplified)",
                onStart: { _ in },
                onCopy: { _ in },
                onRetrySave: {}
            )
            .frame(width: 980, height: 640)
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
        case .provider:
            ProviderSetupView(
                snapshot: ProviderSetupSnapshot(
                    selectedProvider: .deepSeek,
                    availableModelIDs: [
                        "deepseek-v4-flash-vision-exp",
                        "deepseek-vl2",
                    ],
                    selectedModelID: "deepseek-v4-flash-vision-exp",
                    phase: .ready,
                    failure: nil
                ),
                apiKey: $apiKey,
                pendingModelID: $modelID,
                onSelectProvider: { _ in },
                onValidate: {},
                onRefresh: {},
                onSelectModel: { _ in },
                onCancel: {},
                onDone: {}
            )
            .frame(width: 820, height: 640)
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
                onCheckUpdates: {},
                onQuit: {}
            )
        case .privacy:
            StoragePrivacyDetailView(onClose: {})
        }
    }

    private var sampleSnapshot: OperationWorkspaceSnapshot {
        OperationWorkspaceSnapshot(
            selectedOperation: operation,
            extract: WorkspaceOperationSlot(),
            translate: WorkspaceOperationSlot(
                attempt: .succeeded,
                committedResult: WorkspaceCommittedResult(
                    sourceMarkdown: "# Designing Calm Software\n\nGood utility software stays close to the task.",
                    translationMarkdown: "# Designing Calm Software\n\nUseful software stays close to the current task."
                )
            )
        )
    }

    private var sampleImage: NSImage {
        NSImage(size: NSSize(width: 640, height: 420), flipped: false) { rect in
            NSColor(calibratedRed: 0.92, green: 0.95, blue: 1, alpha: 1).setFill()
            rect.fill()
            let title = "Designing Calm Software"
            title.draw(
                at: NSPoint(x: 42, y: 285),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 34, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            return true
        }
    }
}

private enum HarnessMode {
    case result
    case toolbar
    case onboarding
    case provider
    case permission
    case menu
    case privacy

    init(arguments: [String]) {
        if arguments.contains("--toolbar") {
            self = .toolbar
        } else if arguments.contains("--onboarding") {
            self = .onboarding
        } else if arguments.contains("--provider") {
            self = .provider
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
