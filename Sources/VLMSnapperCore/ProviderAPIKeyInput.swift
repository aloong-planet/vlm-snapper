import Foundation

public enum ProviderAPIKeyInputIssue: Error, Equatable, Sendable {
    case empty
    case containsNewline
    case tooLong
}

public enum ProviderAPIKeyInput {
    public static func issue(in value: String) -> ProviderAPIKeyInputIssue? {
        if value.isEmpty { return .empty }
        if value.unicodeScalars.contains(where: CharacterSet.newlines.contains) {
            return .containsNewline
        }
        if value.utf8.count > 4096 { return .tooLong }
        return nil
    }
}
