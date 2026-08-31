import CoreGraphics

public enum VLMSnapperUIConstants {
    public static let toolbarSelectionGap: CGFloat = 4
    public static let toolbarPadding: CGFloat = 3
    public static let toolbarControlGap: CGFloat = 3
    public static let toolbarControlHeight: CGFloat = 25
    public static let compactCornerRadius: CGFloat = 6
    public static let cardCornerRadius: CGFloat = 12
    public static let attachedSheetCornerRadius: CGFloat = 8
    public static let providerMarkSize: CGFloat = 24
}

public enum OnboardingMetrics {
    public static let width: CGFloat = 760
    public static let minimumHeight: CGFloat = 540
    public static let rowCornerRadius: CGFloat = 9
    public static let rowMinimumHeight: CGFloat = 94
}

public enum ProviderSetupMetrics {
    public static let width: CGFloat = 720
    public static let bodyHeight: CGFloat = 410
    public static let cornerRadius: CGFloat = 8
    public static let headerHeight: CGFloat = 63
    public static let footerHeight: CGFloat = 57
}

public enum PermissionRecoveryMetrics {
    public static let width: CGFloat = 520
    public static let cornerRadius: CGFloat = 8
}

public enum ResultWorkspaceMetrics {
    public static let minimumSize = CGSize(width: 1_020, height: 620)
    public static let headerHeight: CGFloat = 58
    public static let footerHeight: CGFloat = 50
}

public enum ManagementCenterMetrics {
    public static let defaultSize = CGSize(width: 1_200, height: 720)
    public static let sidebarWidth: CGFloat = 218
    public static let titlebarHeight: CGFloat = 46
}
