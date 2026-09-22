import Testing

@Suite("Native condition wait", .serialized)
@MainActor
struct NativeConditionWaitTests {
    @Test("an already satisfied condition returns without waiting")
    func immediatelyReady() {
        var elapsed = 0.0
        let ready = waitForNativeCondition(timeout: 0.1, now: { elapsed }, pause: { elapsed += $0 }) { true }
        #expect(ready)
        #expect(elapsed == 0)
    }

    @Test("a pending condition is rechecked every ten milliseconds and stops when ready")
    func becomesReady() {
        var elapsed = 0.0
        var observations: [Double] = []
        let ready = waitForNativeCondition(timeout: 0.1, now: { elapsed }, pause: { elapsed += $0 }) {
            observations.append(elapsed)
            return elapsed >= 0.02
        }
        #expect(ready)
        #expect(observations == [0, 0.01, 0.02])
        #expect(elapsed == 0.02)
    }

    @Test("an unmet condition fails at the original deadline without a full final polling delay")
    func deadlineIsPreserved() {
        var elapsed = 0.0
        var observations: [Double] = []
        let ready = waitForNativeCondition(timeout: 0.025, now: { elapsed }, pause: { elapsed += $0 }) {
            observations.append(elapsed)
            return false
        }
        #expect(!ready)
        #expect(observations == [0, 0.01, 0.02, 0.025])
        #expect(elapsed == 0.025)
    }

    @Test("zero timeout still checks the current state without waiting", arguments: [false, true])
    func zeroTimeout(ready: Bool) {
        var elapsed = 0.0
        let result = waitForNativeCondition(timeout: 0, now: { elapsed }, pause: { elapsed += $0 }) { ready }
        #expect(result == ready)
        #expect(elapsed == 0)
    }
}
