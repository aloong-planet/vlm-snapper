import Foundation

public actor UserDefaultsPermissionRequestHistoryStore:
    PermissionRequestHistoryStoring
{
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "screenCapturePermissionRequested"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func hasRequestedPermission() -> Bool {
        defaults.bool(forKey: key)
    }

    public func markPermissionRequested() {
        defaults.set(true, forKey: key)
    }
}
