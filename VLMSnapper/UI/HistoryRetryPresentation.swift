import SwiftUI
import VLMSnapperCore

/// Application-owned progress survives management-window hiding and reopening.
@MainActor
public final class HistoryRetryPresentation: ObservableObject {
    @Published public var recordID: UUID?
    @Published public var slot = WorkspaceOperationSlot()
    @Published public var isRunning = false
    @Published public var allowsStart = false
    @Published public var providerSummary = ""

    public var preventsDiscard: Bool { isRunning || slot.unsavedResult != nil }

    public init() {}
}
