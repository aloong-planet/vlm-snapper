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
    // History rows reproduce the approved surface palette, not macOS accent
    // or inactive-selection colors. Keep both appearance values explicit.
    static let historySurface = historyColor(light: 0xFFFFFF, dark: 0x2B2F36)
    static let historyHover = historyColor(light: 0xE8ECF1, dark: 0x343A43)
    static let historySelected = historyColor(light: 0xDCE6F5, dark: 0x314361)
    static let historyTitle = historyColor(light: 0x202329, dark: 0xF2F3F5)
    static let historySummary = historyColor(light: 0x646B75, dark: 0xB4BAC3)
    static let historyDate = historyColor(light: 0x8A929D, dark: 0x858D98)
    static let historyType = historyColor(light: 0x1553B2, dark: 0x9BC0FF)
    static let historySucceeded = historyColor(light: 0x20835B, dark: 0x62C596)
    static let historyCanceled = historyColor(light: 0xA96609, dark: 0xEFB45F)
    static let historyFailed = historyColor(light: 0xC34242, dark: 0xFF8080)
    static let historyDivider = historyColor(light: 0x383F49, dark: 0xE5E9F0, lightAlpha: 0.15, darkAlpha: 0.13)
    static let historyImageBorder = historyColor(light: 0x383F49, dark: 0xE5E9F0, lightAlpha: 0.27, darkAlpha: 0.24)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let destructive = Color(nsColor: .systemRed)
    static let onAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .white
    })
    static let accentSoft = tint(.controlAccentColor, light: 0.09, dark: 0.18)
    // Provider identity tiles use the approved prototype palette, independent
    // of the user's action accent. Both foreground and surface follow appearance.
    static let providerMarkForeground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 133 / 255, green: 141 / 255, blue: 152 / 255, alpha: 1)
            : NSColor(srgbRed: 138 / 255, green: 146 / 255, blue: 157 / 255, alpha: 1)
    })
    static let providerMarkBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 40 / 255, green: 62 / 255, blue: 96 / 255, alpha: 1)
            : NSColor(srgbRed: 230 / 255, green: 239 / 255, blue: 255 / 255, alpha: 1)
    })
    static let warningSoft = tint(.systemOrange, light: 0.09, dark: 0.15)
    static let successSoft = tint(.systemGreen, light: 0.09, dark: 0.15)
    static let destructiveHover = tint(.systemRed, light: 0.1, dark: 0.15)
    static let destructivePressed = tint(.systemRed, light: 0.18, dark: 0.24)

    private static func tint(_ color: NSColor, light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            color.withAlphaComponent(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func historyColor(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

struct HistoryImageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ImageSurface(configuration: configuration)
    }

    private struct ImageSurface: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(isHovered || configuration.isPressed ? VLMSnapperTheme.historyHover : VLMSnapperTheme.subtleSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isHovered ? VLMSnapperTheme.historyDate : VLMSnapperTheme.historyImageBorder, lineWidth: 1)
                }
                .onHover { isHovered = $0 }
        }
    }
}

struct HistoryRecordSurface: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? VLMSnapperTheme.historySelected
                        : isHovered ? VLMSnapperTheme.historyHover : VLMSnapperTheme.historySurface,
                        in: RoundedRectangle(cornerRadius: 9, style: .circular))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .circular))
            .onHover { isHovered = $0 }
    }
}

struct HistoryTypeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration, isSelected: isSelected)
    }

    private struct Label: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .frame(minWidth: 54)
                .frame(height: 28)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isSelected ? VLMSnapperTheme.primaryText : VLMSnapperTheme.secondaryText)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(VLMSnapperTheme.border)
                    }
                }
                .shadow(color: isSelected ? VLMSnapperTheme.shadow.opacity(0.12) : .clear, radius: 1, y: 1)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }

        private var background: Color {
            if isSelected { return VLMSnapperTheme.surface }
            return isHovered || configuration.isPressed ? VLMSnapperTheme.subtleSurface : .clear
        }
    }
}

struct SetupActionButtonStyle: ButtonStyle {
    var isDestructive = false
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isDestructive: isDestructive, horizontalPadding: horizontalPadding)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isDestructive: Bool
        let horizontalPadding: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, isDestructive ? 8 : horizontalPadding)
                .frame(height: isDestructive ? 28 : 32)
                .foregroundStyle(isDestructive ? VLMSnapperTheme.destructive : VLMSnapperTheme.primaryText)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if !isDestructive {
                        RoundedRectangle(cornerRadius: 6).stroke(VLMSnapperTheme.border)
                    }
                }
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.5)
                .onHover { isHovered = $0 }
        }

        private var background: Color {
            if isEnabled && (isHovered || configuration.isPressed) {
                return isDestructive ? (configuration.isPressed ? VLMSnapperTheme.destructivePressed : VLMSnapperTheme.destructiveHover)
                    : VLMSnapperTheme.subtleSurface
            }
            return isDestructive ? .clear : VLMSnapperTheme.surface
        }
    }
}
