import AppKit
import SwiftUI
import Testing
@testable import VLMSnapperUI

@Suite("Theme surface rendering", .serialized)
@MainActor
struct ThemeSurfaceRenderingTests {
    @Test("the secondary surface stays light in Aqua appearance")
    func lightSecondarySurface() throws {
        let color = try renderedColor(
            VLMSnapperTheme.subtleSurface,
            appearance: NSAppearance.Name.aqua
        )

        #expect(relativeLuminance(color) > 0.8)
    }

    @Test("the secondary surface stays dark in Dark Aqua appearance")
    func darkSecondarySurface() throws {
        let color = try renderedColor(
            VLMSnapperTheme.subtleSurface,
            appearance: NSAppearance.Name.darkAqua
        )

        #expect(relativeLuminance(color) < 0.2)
    }

    private func renderedColor(_ color: Color, appearance: NSAppearance.Name) throws -> NSColor {
        let size = CGSize(width: 20, height: 20)
        let hostingView = NSHostingView(
            rootView: ZStack {
                VLMSnapperTheme.window
                Rectangle().fill(color)
            }
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(named: appearance)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw ThemeRenderFailure.bitmapUnavailable
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let sampled = bitmap.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB) else {
            throw ThemeRenderFailure.pixelUnavailable
        }
        return sampled
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}

private enum ThemeRenderFailure: Error {
    case bitmapUnavailable
    case pixelUnavailable
}
