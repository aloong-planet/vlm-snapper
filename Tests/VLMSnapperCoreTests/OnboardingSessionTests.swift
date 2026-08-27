import Testing
@testable import VLMSnapperCore

@Suite("Onboarding readiness")
struct OnboardingSessionTests {
    @Test("permission is the first blocker and Later is always available")
    func permissionIsFirstBlocker() {
        let snapshot = OnboardingSession(
            permission: .notRequested,
            provider: .missing
        ).snapshot

        #expect(snapshot.blocker == .screenCapturePermission)
        #expect(!snapshot.canStart)
        #expect(snapshot.canFinishLater)
    }

    @Test("a configured provider becomes the blocker after permission is ready")
    func providerBecomesBlocker() {
        let snapshot = OnboardingSession(
            permission: .ready,
            provider: .pendingModel(.gemini)
        ).snapshot

        #expect(snapshot.blocker == .providerModel)
        #expect(!snapshot.canStart)
        #expect(snapshot.canFinishLater)
    }

    @Test("both required items enable Start")
    func allRequirementsEnableStart() {
        let snapshot = OnboardingSession(
            permission: .ready,
            provider: .ready(provider: .deepSeek, modelID: "deepseek-v4-flash-vision-exp")
        ).snapshot

        #expect(snapshot.blocker == nil)
        #expect(snapshot.canStart)
        #expect(snapshot.canFinishLater)
    }

    @Test("menu capture routes missing provider before permission recovery")
    func menuCaptureRoutesProviderFirst() {
        #expect(
            MenuCaptureRouter.route(
                permission: .notRequested,
                provider: .missing
            ) == .configureProvider
        )
        #expect(
            MenuCaptureRouter.route(
                permission: .unavailable,
                provider: .ready(provider: .openAI, modelID: "gpt-4.1")
            ) == .recoverPermission
        )
        #expect(
            MenuCaptureRouter.route(
                permission: .ready,
                provider: .ready(provider: .openAI, modelID: "gpt-4.1")
            ) == .capture
        )
    }
}
