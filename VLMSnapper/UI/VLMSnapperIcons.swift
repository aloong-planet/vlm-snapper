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

// Save uses a floppy disk, the convention the user chose (2026-10-29). SF Symbols has no floppy disk, so
// this is the one generic action icon drawn here: Lucide's "save" outline on its 24-unit grid.
struct FloppyDiskShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: 3))
        path.addLine(to: CGPoint(x: 15.2, y: 3))
        path.addQuadCurve(to: CGPoint(x: 16.6, y: 3.6), control: CGPoint(x: 16, y: 3))
        path.addLine(to: CGPoint(x: 20.4, y: 7.4))
        path.addQuadCurve(to: CGPoint(x: 21, y: 8.8), control: CGPoint(x: 21, y: 8))
        path.addLine(to: CGPoint(x: 21, y: 19))
        path.addArc(tangent1End: CGPoint(x: 21, y: 21), tangent2End: CGPoint(x: 19, y: 21), radius: 2)
        path.addLine(to: CGPoint(x: 5, y: 21))
        path.addArc(tangent1End: CGPoint(x: 3, y: 21), tangent2End: CGPoint(x: 3, y: 19), radius: 2)
        path.addLine(to: CGPoint(x: 3, y: 5))
        path.addArc(tangent1End: CGPoint(x: 3, y: 3), tangent2End: CGPoint(x: 5, y: 3), radius: 2)
        path.closeSubpath()
        // Label area at the bottom.
        path.move(to: CGPoint(x: 17, y: 21))
        path.addLine(to: CGPoint(x: 17, y: 14))
        path.addArc(tangent1End: CGPoint(x: 17, y: 13), tangent2End: CGPoint(x: 16, y: 13), radius: 1)
        path.addLine(to: CGPoint(x: 8, y: 13))
        path.addArc(tangent1End: CGPoint(x: 7, y: 13), tangent2End: CGPoint(x: 7, y: 14), radius: 1)
        path.addLine(to: CGPoint(x: 7, y: 21))
        // Shutter at the top.
        path.move(to: CGPoint(x: 7, y: 3))
        path.addLine(to: CGPoint(x: 7, y: 7))
        path.addArc(tangent1End: CGPoint(x: 7, y: 8), tangent2End: CGPoint(x: 8, y: 8), radius: 1)
        path.addLine(to: CGPoint(x: 15, y: 8))
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
    }
}

struct FloppyDiskIcon: View {
    var body: some View {
        FloppyDiskShape()
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }
}

