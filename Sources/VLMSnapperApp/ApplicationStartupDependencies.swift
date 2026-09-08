import AppKit
import VLMSnapperCore
import VLMSnapperUI

/// Process boundaries resolved at startup. Model adapters remain lazy until
/// the primary-instance lock has been acquired.
@MainActor
struct ApplicationStartupDependencies {
    let root: URL
    let defaults: UserDefaults
    let pasteboard: NSPasteboard
    let messaging: any PrimaryInstanceMessaging
    let makeModelDependencies: () throws -> ApplicationModelDependencies

    static func live() throws -> Self {
        Self(
            root: try ApplicationDirectories.applicationSupportRoot(),
            defaults: .standard,
            pasteboard: .general,
            messaging: DistributedPrimaryInstanceMessaging(),
            makeModelDependencies: { try .live() }
        )
    }
}
