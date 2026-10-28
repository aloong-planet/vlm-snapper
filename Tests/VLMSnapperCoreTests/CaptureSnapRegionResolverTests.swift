import CoreGraphics
import Testing
@testable import VLMSnapperCore

// The window list below copies the shape of a real CGWindowListCopyWindowInfo result recorded
// on a 1512 × 982 display (2026-10-28): front to back, an alpha-0 input method window at a
// very high layer, status items as separate layer-25 windows, the menu bar as a layer-24
// window of the window server, the Dock as one layer-20 window covering the whole display,
// and ordinary layer-0 windows that overlap and reach past the display edge.
// Not covered here: the real list in a signed sandboxed app and real Dock and menu bar
// geometry, which are checked on the installed build.
@Suite("Capture snap region resolver")
struct CaptureSnapRegionResolverTests {
    private static let ownProcess: Int32 = 900
    private static let dockProcess: Int32 = 725
    private static let display = CaptureSnapDisplay(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 34, width: 1512, height: 900),
        pointPixelScale: 2
    )
    private static let terminal = CGRect(x: 40, y: 120, width: 700, height: 500)
    private static let chrome = CGRect(x: 400, y: 60, width: 1200, height: 700)
    private static let wifi = CGRect(x: 1322, y: 0, width: 38, height: 33)
    private static let menuBar = CGRect(x: 0, y: 0, width: 1512, height: 33)

    private static func window(
        _ bounds: CGRect,
        process: Int32 = 687,
        layer: Int = 0,
        alpha: Double = 1,
        onScreen: Bool = true
    ) -> CaptureWindowSnapshotEntry {
        CaptureWindowSnapshotEntry(
            ownerProcessID: process,
            layer: layer,
            alpha: alpha,
            isOnScreen: onScreen,
            bounds: bounds
        )
    }

    private static func resolver(
        front: [CaptureWindowSnapshotEntry] = [],
        dockVisible: Bool = true
    ) -> CaptureSnapRegionResolver {
        let recorded = [
            window(CGRect(x: 23, y: 874, width: 36, height: 36), process: 89004, layer: 2147483629, alpha: 0),
            window(wifi, process: 728, layer: 25),
            window(CGRect(x: 1360, y: 0, width: 42, height: 33), process: 728, layer: 25),
            window(menuBar, process: 412, layer: 24),
            window(CGRect(x: 0, y: 0, width: 1512, height: 982), process: dockProcess, layer: 20),
            window(terminal),
            window(chrome, process: 683),
        ]
        return CaptureSnapRegionResolver(
            snapshot: CaptureWindowSnapshot(
                windows: front + (dockVisible ? recorded : recorded.filter { $0.ownerProcessID != dockProcess }),
                dockProcessID: dockProcess
            ),
            excludedProcessID: ownProcess
        )
    }

    @Test("the topmost window under the pointer is snapped as a whole window")
    func snapsTopmostWindow() {
        let resolver = Self.resolver()
        #expect(resolver.region(at: CGPoint(x: 100, y: 300), on: Self.display) == Self.terminal)
        // Inside both windows the front one wins; past the Terminal only Chrome remains.
        #expect(resolver.region(at: CGPoint(x: 600, y: 300), on: Self.display) == Self.terminal)
        #expect(
            resolver.region(at: CGPoint(x: 1000, y: 300), on: Self.display)
                == CGRect(x: 400, y: 60, width: 1112, height: 700)
        )
    }

    @Test("a status item is snapped on its own and the rest of the menu bar as a whole")
    func snapsStatusItemAndMenuBar() {
        let resolver = Self.resolver()
        #expect(resolver.region(at: CGPoint(x: 1340, y: 15), on: Self.display) == Self.wifi)
        #expect(resolver.region(at: CGPoint(x: 300, y: 15), on: Self.display) == Self.menuBar)
    }

    @Test("the Dock strip is one region and an auto-hidden Dock falls through")
    func snapsDockStrip() {
        #expect(
            Self.resolver().region(at: CGPoint(x: 700, y: 960), on: Self.display)
                == CGRect(x: 0, y: 934, width: 1512, height: 48)
        )
        let autoHidden = CaptureSnapDisplay(
            frame: Self.display.frame,
            visibleFrame: CGRect(x: 0, y: 34, width: 1512, height: 948),
            pointPixelScale: 2
        )
        // With no reserved strip the point is over the desktop.
        #expect(Self.resolver().region(at: CGPoint(x: 700, y: 960), on: autoHidden) == Self.display.frame)
        // Without the Dock window at all, the reserved strip is not a region either.
        #expect(
            Self.resolver(dockVisible: false).region(at: CGPoint(x: 700, y: 960), on: Self.display)
                == Self.display.frame
        )
    }

    @Test("the desktop snaps to the whole display")
    func snapsDesktopToDisplay() {
        #expect(Self.resolver().region(at: CGPoint(x: 20, y: 800), on: Self.display) == Self.display.frame)
    }

    @Test("own, transparent, off-screen and system overlay windows are skipped")
    func skipsWindowsOutsideTheFrozenFrame() {
        let point = CGPoint(x: 100, y: 300)
        let resolver = Self.resolver(front: [
            Self.window(Self.display.frame, process: Self.ownProcess, layer: 1000),
            Self.window(CGRect(x: 60, y: 200, width: 400, height: 300), process: Self.ownProcess),
            Self.window(CGRect(x: 60, y: 200, width: 400, height: 300), process: 501, alpha: 0),
            Self.window(CGRect(x: 60, y: 200, width: 400, height: 300), process: 502, onScreen: false),
            Self.window(CGRect(x: 60, y: 200, width: 400, height: 300), process: 503, layer: 103),
        ])
        #expect(resolver.region(at: point, on: Self.display) == Self.terminal)
    }

    @Test("regions stay on the pointer's display and skip windows under two pixels")
    func clipsToDisplayAndSkipsTinyWindows() {
        let second = CaptureSnapDisplay(
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 25, width: 1920, height: 1055),
            pointPixelScale: 1
        )
        let resolver = Self.resolver(front: [
            Self.window(CGRect(x: 1700, y: 400, width: 1.5, height: 300), process: 504),
        ])
        // Chrome reaches past the first display: on the second one only its part there counts.
        #expect(
            resolver.region(at: CGPoint(x: 1550, y: 300), on: second)
                == CGRect(x: 1512, y: 60, width: 88, height: 700)
        )
        // The 1.5 pt window is one pixel wide at scale 1 and is skipped for the desktop below it.
        #expect(resolver.region(at: CGPoint(x: 1700.5, y: 500), on: second) == second.frame)
    }
}
