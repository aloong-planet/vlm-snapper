import AppKit
import SwiftUI
import VLMSnapperCore
import VLMSnapperUI

@main
struct VLMSnapperUIHarness: App {
    var body: some Scene {
        WindowGroup {
            HarnessRoot(showsToolbar: CommandLine.arguments.contains("--toolbar"))
                .preferredColorScheme(
                    CommandLine.arguments.contains("--dark") ? .dark : .light
                )
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct HarnessRoot: View {
    let showsToolbar: Bool
    @State private var operation: WorkspaceOperationKind = .translate

    var body: some View {
        if showsToolbar {
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
        } else {
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
