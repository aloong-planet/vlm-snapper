import SwiftUI
import VLMSnapperCore

// SF Symbols are centralized here so icon geometry stays native and no view
// substitutes text, Unicode glyphs, or emoji for interface icons.
// The explicitly approved Provider identity monograms below are the sole
// exception: they reproduce the prototype's labels, not generic action icons.
enum VLMSnapperIcon: String {
    case extract = "text.alignleft"
    case translate = "character.book.closed"
    case language = "globe"
    case provider = "cpu"
    case close = "xmark"
    case copy = "doc.on.doc"
    case retry = "arrow.clockwise"
    case capture = "viewfinder"
    case permission = "rectangle.inset.filled.and.person.filled"
    case complete = "checkmark.circle.fill"
    case warning = "exclamationmark.triangle.fill"
    case key = "key.fill"
    case model = "cpu.fill"
    case info = "info.circle"
    case history = "clock.arrow.circlepath"
    case settings = "gearshape"
    case update = "arrow.down.circle"
    case folder = "folder"
    case search = "magnifyingglass"
    case pin = "pin"
    case pinned = "pin.fill"
    case delete = "trash"
    case providerList = "server.rack"
    case general = "slider.horizontal.3"
    case warningBadge = "exclamationmark.circle.fill"
    case downloaded = "checkmark.circle"
    case diagnostics = "doc.text.magnifyingglass"
    case chevronDown = "chevron.down"
    case lock = "lock.fill"
    case eye = "eye"
    case eyeSlash = "eye.slash"

    var image: Image {
        Image(systemName: rawValue)
    }
}

struct ProviderIdentityMark: View {
    let provider: ProviderID

    private var monogram: String {
        switch provider {
        case .deepSeek: "DS"
        case .openAI: "OA"
        case .gemini: "G"
        }
    }

    var body: some View {
        Text(verbatim: monogram)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(VLMSnapperTheme.providerMarkForeground)
            .frame(
                width: ManagementCenterMetrics.providerMarkSize,
                height: ManagementCenterMetrics.providerMarkSize
            )
            .background(VLMSnapperTheme.providerMarkBackground, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

// The brand emblem follows the approved onboarding vector, not a text glyph.
struct OnboardingBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(CGRect(x: 5, y: 7, width: 14, height: 10))
        for x in [8.0, 16.0] {
            path.move(to: CGPoint(x: x, y: 4))
            path.addLine(to: CGPoint(x: x, y: 7))
            path.move(to: CGPoint(x: x, y: 17))
            path.addLine(to: CGPoint(x: x, y: 20))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}
