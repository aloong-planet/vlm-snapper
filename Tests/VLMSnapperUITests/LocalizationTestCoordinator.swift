import Foundation
import VLMSnapperCore
@testable import VLMSnapperUI

enum LocalizationTestCoordinator {
    private static let lock = NSLock()

    static func acquire() {
        lock.lock()
    }

    static func release() {
        VLMSnapperLocalization.configure(effectiveLanguage: .simplifiedChinese)
        lock.unlock()
    }

    static func withExclusiveAccess<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        acquire()
        defer { release() }
        return try operation()
    }
}
