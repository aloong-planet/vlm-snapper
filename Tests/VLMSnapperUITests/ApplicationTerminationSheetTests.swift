import AppKit
import SwiftUI
import Testing
import VLMSnapperCore
@testable import VLMSnapperUI

@Suite("Application termination sheets", .serialized)
@MainActor
struct ApplicationTerminationSheetTests {
    private static var retainedParentWindows: [NSWindow] = []

    @Test("All application-owned sheets permit coordinated application termination")
    func applicationOwnedSheetsPermitTermination() throws {
        let contents = [
            AnyView(permissionRecovery),
            AnyView(StoragePrivacyDetailView(onClose: {})),
        ]
        let presentations = try contents.map(presentedSheet)

        #expect(presentations.count == 2)
        for presentation in presentations {
            #expect(presentation.sheet.preventsApplicationTerminationWhenModal == false)
        }

        for presentation in presentations {
            presentation.parent.endSheet(presentation.sheet)
            presentation.parent.orderOut(nil)
            // SwiftUI may finish tearing down a sheet after this test returns. Retaining the
            // parent avoids releasing AppKit state while that asynchronous teardown is pending.
            Self.retainedParentWindows.append(presentation.parent)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private var permissionRecovery: ScreenCapturePermissionRecoveryView {
        ScreenCapturePermissionRecoveryView(
            state: .unavailable,
            onPrimaryAction: {},
            onDismiss: {}
        )
    }

    private func presentedSheet(_ content: AnyView) throws -> SheetPresentation {
        let host = NSHostingController(rootView: SheetPresentationHost(content: content))
        let parent = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        parent.contentViewController = host
        parent.makeKeyAndOrderFront(nil)

        let deadline = Date().addingTimeInterval(2)
        while parent.attachedSheet == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        return SheetPresentation(
            parent: parent,
            sheet: try #require(parent.attachedSheet)
        )
    }
}

private struct SheetPresentation {
    let parent: NSWindow
    let sheet: NSWindow
}

private struct SheetPresentationHost<Content: View>: View {
    let content: Content
    @State private var isPresented = true

    var body: some View {
        Color.clear
            .frame(width: 820, height: 640)
            .sheet(isPresented: $isPresented) {
                content
            }
    }
}
