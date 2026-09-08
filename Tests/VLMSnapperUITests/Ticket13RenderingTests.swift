import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Ticket 13 production UI rendering", .serialized)
@MainActor
// PNG generation is not interaction acceptance. Inspect the renders and separately
// exercise the confirmed prototype and installed application controls.
struct Ticket13RenderingTests {
    @Test("configured model refresh renders stable idle busy and failure surfaces")
    func modelRefreshSurfacesRender() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-provider-refresh-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in Ticket13Language.allCases {
            VLMSnapperLocalization.configure(effectiveLanguage: language.effectiveLanguage)
            for appearance in Ticket13Appearance.allCases {
                for width in [920, 1200] {
                    for state in ["idle", "busy", "failed"] {
                        let editor = ProviderCredentialEditor()
                        let load = editor.beginLoading(for: .deepSeek)
                        editor.completeLoad(load, value: "fixture-key")
                        let configuration = ProviderConfiguration(
                            models: [ProviderModelState(id: "deepseek-v4-flash-vision-exp")],
                            fetchedAt: Date(timeIntervalSince1970: 0),
                            selectedModelID: "deepseek-v4-flash-vision-exp"
                        )
                        try render(
                            ManagementCenterView(
                                destination: .providerSettings, records: [],
                                providerSettings: ProviderSettingsConfiguration(
                                    snapshot: ProviderSetupSnapshot(
                                        selectedProvider: .deepSeek,
                                        availableModelIDs: ["deepseek-v4-flash-vision-exp"],
                                        selectedModelID: "deepseek-v4-flash-vision-exp", phase: .ready,
                                        failure: nil, isReadOnly: state == "busy",
                                        activity: state == "busy" ? .credential(.deepSeek) : nil,
                                        refreshingProvider: state == "busy" ? .deepSeek : nil,
                                        modelRefreshFailure: state == "failed" ? .unavailable : nil
                                    ),
                                    configurations: [
                                        .deepSeek: configuration,
                                        .openAI: ProviderConfiguration(
                                            models: [ProviderModelState(id: "gpt-4o")],
                                            fetchedAt: Date(timeIntervalSince1970: 0), selectedModelID: "gpt-4o"
                                        )
                                    ], currentProvider: .openAI,
                                    credentialEditor: editor,
                                    pendingModelID: .constant("deepseek-v4-flash-vision-exp"),
                                    onSelectProvider: { _ in }, onValidate: { _ in }, onRefresh: {},
                                    onSelectModel: { _ in }
                                )
                            ),
                            size: CGSize(width: width, height: 700), appearance: appearance,
                            outputURL: output.appendingPathComponent(
                                "\(language.rawValue)-\(appearance.rawValue)-\(width)-\(state).png"
                            )
                        )
                    }
                }
            }
        }
    }

    @Test("a cleared candidate after a storage write failure renders the empty validation form")
    func clearedFailedCandidateRenders() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        VLMSnapperLocalization.configure(effectiveLanguage: .english)
        let editor = ProviderCredentialEditor()
        editor.edit("candidate-key")
        var submission: ProviderCredentialSubmission?
        #expect(editor.submit(for: .deepSeek, isReadOnly: false) { submission = $0 })
        editor.complete(try #require(submission), succeeded: false)
        editor.edit("")
        #expect(!editor.isDirty)
        try render(
            ManagementCenterView(
                destination: .providerSettings,
                records: [],
                providerSettings: ProviderSettingsConfiguration(
                    snapshot: ProviderSetupSnapshot(
                        selectedProvider: .deepSeek, availableModelIDs: [],
                        selectedModelID: nil, phase: .failed,
                        failure: .secureStorage, isReadOnly: false
                    ),
                    configurations: [:], currentProvider: nil,
                    credentialEditor: editor, pendingModelID: .constant(nil),
                    onSelectProvider: { _ in }, onValidate: { _ in },
                    onRefresh: {}, onSelectModel: { _ in }
                )
            ),
            size: CGSize(width: 920, height: 620), appearance: .light,
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ticket21-cleared-failed-candidate.png")
        )
    }

    @Test("every confirmed production surface renders in both languages and appearances")
    func confirmedSurfacesRender() throws {
        LocalizationTestCoordinator.acquire()
        defer { LocalizationTestCoordinator.release() }
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vlmsnapper-ticket13-renders", isDirectory: true)
        if FileManager.default.fileExists(atPath: outputDirectory.path) {
            try FileManager.default.removeItem(at: outputDirectory)
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        for language in Ticket13Language.allCases {
            VLMSnapperLocalization.configure(effectiveLanguage: language.effectiveLanguage)
            for appearance in Ticket13Appearance.allCases {
                let suffix = "\(language.rawValue)-\(appearance.rawValue)"
                try render(
                    MenuBarPanelChrome(arrowCenterX: 280) {
                        menuView
                    },
                    size: CGSize(width: 300, height: 394),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("menu-\(suffix).png")
                )
                try render(
                    onboardingView,
                    size: CGSize(width: 760, height: 540),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("onboarding-\(suffix).png")
                )
                try render(
                    permissionView,
                    size: CGSize(width: 620, height: 390),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("permission-\(suffix).png")
                )
                try render(
                    StoragePrivacyDetailView(onClose: {}),
                    size: CGSize(width: 620, height: 520),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("privacy-\(suffix).png")
                )
                try render(
                    resultView,
                    size: ResultWorkspaceMetrics.minimumSize,
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("result-\(suffix).png")
                )
                try render(
                    ManagementCenterView(
                        destination: .history,
                        records: records,
                        selectedRecordID: records.first?.id,
                        selectedImage: sampleImage
                    ),
                    size: ManagementCenterMetrics.defaultSize,
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("management-\(suffix).png")
                )
                try render(
                    ManagementCenterView(
                        destination: .history,
                        records: records,
                        selectedRecordID: records.first?.id,
                        selectedImage: sampleImage
                    ),
                    size: CGSize(width: 920, height: 620),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent(
                        "management-minimum-\(suffix).png"
                    )
                )
                try render(
                    ManagementCenterView(
                        destination: .settings,
                        records: records,
                        showsGeneralSettings: true,
                        settings: GeneralSettingsSnapshot(
                            updateState: .current(lastCheckedAt: nil)
                        ),
                        providerSettings: providerSettingsConfiguration
                    ),
                    size: ManagementCenterMetrics.defaultSize,
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent(
                        "management-general-\(suffix).png"
                    )
                )
                try render(
                    ManagementCenterView(
                        destination: .providerSettings,
                        records: records,
                        showsGeneralSettings: false,
                        providerSettings: providerSettingsConfiguration
                    ),
                    size: ManagementCenterMetrics.defaultSize,
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent(
                        "management-provider-\(suffix).png"
                    )
                )
                try render(
                    ManagementCenterView(
                        destination: .providerSettings,
                        records: records,
                        showsGeneralSettings: false,
                        providerSettings: providerSettingsConfiguration
                    ),
                    size: CGSize(width: 920, height: 620),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent(
                        "management-provider-minimum-\(suffix).png"
                    )
                )
                try render(
                    toolbarView,
                    size: CGSize(width: 780, height: 320),
                    appearance: appearance,
                    outputURL: outputDirectory.appendingPathComponent("toolbar-\(suffix).png")
                )
                for recovering in [true, false] {
                    let credentialEditor = ProviderCredentialEditor()
                    _ = credentialEditor.beginLoading(for: .deepSeek)
                    try render(
                        ManagementCenterView(
                            destination: .providerSettings,
                            records: [],
                            providerSettings: ProviderSettingsConfiguration(
                                snapshot: ProviderSetupSnapshot(
                                    selectedProvider: .deepSeek,
                                    availableModelIDs: [],
                                    selectedModelID: nil,
                                    phase: recovering ? .recovering : .failed,
                                    failure: recovering ? nil : .secureStorage,
                                    isReadOnly: true
                                ),
                                configurations: [:],
                                currentProvider: nil,
                                credentialEditor: credentialEditor,
                                pendingModelID: .constant(nil),
                                onSelectProvider: { _ in },
                                onValidate: { _ in },
                                onRefresh: {},
                                onSelectModel: { _ in }
                            )
                        ),
                        size: CGSize(width: 920, height: 620),
                        appearance: appearance,
                        outputURL: outputDirectory.appendingPathComponent(
                            "provider-\(recovering ? "recovering" : "storage-error")-\(suffix).png"
                        )
                    )
                }
            }
        }

        let names = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }.map(\.lastPathComponent)
        let expectedNames = Set(Ticket13Language.allCases.flatMap { language in
            Ticket13Appearance.allCases.flatMap { appearance in
                let suffix = "\(language.rawValue)-\(appearance.rawValue)"
                return [
                    "menu-\(suffix).png",
                    "onboarding-\(suffix).png",
                    "permission-\(suffix).png",
                    "privacy-\(suffix).png",
                    "result-\(suffix).png",
                    "management-\(suffix).png",
                    "management-minimum-\(suffix).png",
                    "management-general-\(suffix).png",
                    "management-provider-\(suffix).png",
                    "management-provider-minimum-\(suffix).png",
                    "toolbar-\(suffix).png",
                    "provider-recovering-\(suffix).png",
                    "provider-storage-error-\(suffix).png",
                ]
            }
        })
        #expect(Set(names) == expectedNames)
    }

    private var menuView: some View {
        MenuBarPanelView(
            recentItems: [
                MenuRecentItem(
                    id: "1",
                    title: "Designing Calm Software",
                    detail: "Translate · 2 min ago",
                    status: .succeeded
                ),
                MenuRecentItem(
                    id: "2",
                    title: "Vision API integration guide",
                    detail: "Extract Text · 18 min ago",
                    status: .succeeded
                ),
                MenuRecentItem(
                    id: "3",
                    title: "Provider request failed",
                    detail: "Translate · 1 hr ago",
                    status: .failed
                ),
            ],
            provider: .ready(provider: .deepSeek, modelID: "deepseek-v4-flash-vision-exp"),
            updateState: .available(
                AvailableUpdateVersion(version: "1.1.0", displayVersion: "1.1.0")
            ),
            onCapture: {},
            onOpenRecent: { _ in },
            onNavigate: { _ in },
            onCheckUpdates: {}
        )
    }

    private var onboardingView: some View {
        OnboardingView(
            snapshot: OnboardingSession(
                permission: .unavailable,
                provider: .pendingModel(.deepSeek)
            ).snapshot,
            onConfigurePermission: {},
            onConfigureProvider: {},
            onViewPrivacy: {},
            onStart: {},
            onFinishLater: {}
        )
    }

    private var providerSettingsConfiguration: ProviderSettingsConfiguration {
        ProviderSettingsConfiguration(
            snapshot: ProviderSetupSnapshot(
                selectedProvider: .deepSeek,
                availableModelIDs: ["deepseek-v4-flash-vision-exp"],
                selectedModelID: "deepseek-v4-flash-vision-exp",
                phase: .ready,
                failure: nil
            ),
            configurations: [.deepSeek: configuredDeepSeek],
            currentProvider: .deepSeek,
            credentialEditor: ProviderCredentialEditor(loadedValue: "demo-deepseek-api-key"),
            pendingModelID: .constant("deepseek-v4-flash-vision-exp"),
            onSelectProvider: { _ in },
            onValidate: { _ in },
            onRefresh: {},
            onSelectModel: { _ in }
        )
    }

    private var configuredDeepSeek: ProviderConfiguration {
        ProviderConfiguration(
            models: [
                ProviderModelState(
                    id: "deepseek-v4-flash-vision-exp",
                    visionCompatibility: .verified
                ),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1),
            selectedModelID: "deepseek-v4-flash-vision-exp"
        )
    }

    private var permissionView: some View {
        ZStack {
            VLMSnapperTheme.subtleSurface
            ScreenCapturePermissionRecoveryView(
                state: .unavailable,
                onPrimaryAction: {},
                onDismiss: {}
            )
        }
    }

    private var resultView: some View {
        ResultWorkspaceView(
            operation: .constant(.translate),
            snapshot: OperationWorkspaceSnapshot(
                selectedOperation: .translate,
                extract: WorkspaceOperationSlot(),
                translate: WorkspaceOperationSlot(
                    attempt: .succeeded,
                    committedResult: WorkspaceCommittedResult(
                        sourceMarkdown: "# Designing Calm Software\n\nGood utility software stays close to the task.",
                        translationMarkdown: "# 设计宁静的软件\n\n优秀的工具应该贴近当前任务。"
                    )
                )
            ),
            originalImage: sampleImage,
            providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
            targetLanguage: "Chinese (Simplified)",
            onStart: { _ in },
            onCopy: { _ in },
            onRetrySave: {}
        )
    }

    private var toolbarView: some View {
        ZStack {
            VLMSnapperTheme.subtleSurface
            VStack(alignment: .leading, spacing: VLMSnapperUIConstants.toolbarSelectionGap) {
                Rectangle()
                    .fill(VLMSnapperTheme.surface)
                    .frame(width: 680, height: 210)
                    .overlay(Rectangle().stroke(VLMSnapperTheme.accent))
                CaptureOperationToolbar(
                    operation: .constant(.extract),
                    targetLanguageCode: .constant("zh-Hans"),
                    targetLanguages: [
                        TargetLanguageOption(code: "zh-Hans", name: "Chinese (Simplified)"),
                        TargetLanguageOption(code: "en", name: "English"),
                    ],
                    providerSummary: "DeepSeek · deepseek-v4-flash-vision-exp",
                    onStart: { _ in },
                    onCancel: {}
                )
            }
        }
    }

    private var records: [HistoryRecord] {
        [
            record(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, kind: .translate),
            record(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, kind: .extract),
        ]
    }

    private func record(id: UUID, kind: PersistedOperationKind) -> HistoryRecord {
        HistoryRecord(
            operation: StoredOperation(
                id: id,
                screenshot: ManagedScreenshot(path: "/Pictures/\(id).png", sha256: "sha"),
                selection: ProviderSelection(
                    providerID: "DeepSeek",
                    modelID: "deepseek-v4-flash-vision-exp"
                ),
                status: .succeeded,
                sourceMarkdown: kind == .translate
                    ? "Designing Calm Software"
                    : "Vision API integration guide",
                translationMarkdown: kind == .translate
                    ? "Excellent utility software stays close to the task."
                    : nil,
                kind: kind,
                targetLanguage: kind == .translate ? "zh-Hans" : nil
            ),
            createdAt: Date(timeIntervalSince1970: 1_787_725_812),
            isPinned: kind == .translate,
            metrics: PersistedOperationMetrics(
                firstTextLatencyMilliseconds: 430,
                totalLatencyMilliseconds: 1_280,
                usage: ProviderTokenUsage(inputTokens: 124, outputTokens: 38, totalTokens: 162)
            )
        )
    }

    private var sampleImage: NSImage {
        NSImage(size: NSSize(width: 640, height: 360), flipped: false) { rect in
            NSColor(calibratedRed: 0.92, green: 0.95, blue: 1, alpha: 1).setFill()
            rect.fill()
            "Designing Calm Software".draw(
                at: NSPoint(x: 36, y: 240),
                withAttributes: [.font: NSFont.systemFont(ofSize: 32, weight: .bold)]
            )
            return true
        }
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        appearance: Ticket13Appearance,
        outputURL: URL
    ) throws {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: appearance.nsAppearanceName)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let representation = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        #expect(png.count > 10_000)
        try png.write(to: outputURL, options: .atomic)
    }
}

private enum Ticket13Language: String, CaseIterable {
    case zhHans
    case en

    var effectiveLanguage: EffectiveApplicationLanguage {
        switch self {
        case .zhHans: .simplifiedChinese
        case .en: .english
        }
    }
}

private enum Ticket13Appearance: String, CaseIterable {
    case light
    case dark

    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
