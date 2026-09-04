import SwiftUI

enum VLMSnapperTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let subtleSurface = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        .opacity(0.35)
    static let border = Color(nsColor: .separatorColor)
    static let shadow = Color(nsColor: .shadowColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let accent = Color.accentColor
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)
}
