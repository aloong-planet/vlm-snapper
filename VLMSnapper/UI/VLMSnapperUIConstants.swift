import CoreGraphics

public enum VLMSnapperUIConstants {
    public static let toolbarSelectionGap: CGFloat = 4
    public static let toolbarResultBoxGap: CGFloat = 8
    public static let toolbarPadding: CGFloat = 3
    public static let toolbarControlGap: CGFloat = 3
    public static let toolbarControlHeight: CGFloat = 25
    public static let compactCornerRadius: CGFloat = 6
    public static let cardCornerRadius: CGFloat = 12
    public static let attachedSheetCornerRadius: CGFloat = 8
    public static let providerMarkSize: CGFloat = 24
}

public enum OnboardingMetrics {
    public static let width: CGFloat = 900
    public static let minimumHeight: CGFloat = 604
    public static let rowCornerRadius: CGFloat = 9
    public static let rowMinimumHeight: CGFloat = 94
}

public enum PermissionRecoveryMetrics {
    public static let width: CGFloat = 520
    public static let cornerRadius: CGFloat = 8
}

public enum CaptureResultBoxMetrics {
    public static let width: CGFloat = 380
    public static let maximumHeight: CGFloat = 640
    public static let edgeInset: CGFloat = 12
    public static let headerHeight: CGFloat = 37
    public static let cornerRadius: CGFloat = 10
    public static let bodyHorizontalInset: CGFloat = 16
    public static let bodyVerticalInset: CGFloat = 14
}

public enum ManagementCenterMetrics {
    public static let defaultSize = CGSize(width: 1_200, height: 780)
    public static let sidebarWidth: CGFloat = 180
    public static let titlebarHeight: CGFloat = 46
    public static let providerContentWidth: CGFloat = 850
    public static let providerHeaderHeight: CGFloat = 54
    public static let providerMarkSize: CGFloat = 29
    public static let providerCredentialFieldHeight: CGFloat = 32
}
