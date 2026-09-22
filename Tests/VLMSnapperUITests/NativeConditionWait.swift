import Foundation

// Test-only clock and run-loop seams; callers supply the observable UI condition.
@MainActor
func waitForNativeCondition(
    timeout: TimeInterval,
    now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    pause: (TimeInterval) -> Void = { RunLoop.current.run(until: Date().addingTimeInterval($0)) },
    until predicate: () -> Bool
) -> Bool {
    let deadline = now() + timeout
    while true {
        if predicate() { return true }
        let remaining = deadline - now()
        guard remaining > 0 else { return false }
        pause(min(0.01, remaining))
    }
}
