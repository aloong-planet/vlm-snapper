import Testing

// Programmatic native input and delegate routing, not physical keyboard,
// OS foregrounding, live-account or signed-app acceptance. Delegate tests
// mutate process-wide AppKit/localization state; run this suite separately.
// Only external adapters are replaced; the editor, sessions, coordinator,
// model-list parser, metadata files and SQLite use production implementations.
// Capture uses synthetic pixels and real native selection/toolbar/result events.
// Bilingual layout, physical shortcuts, the history retry's modal unsaved-result
// dialog and every failure/cancellation permutation remain separate acceptance work.
@Suite(.serialized)
@MainActor
struct ProviderApplicationTests {}
