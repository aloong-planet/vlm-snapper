import AppKit
import SwiftUI

extension View {
    func permitsApplicationTerminationWhilePresented() -> some View {
        background(ApplicationTerminationWindowConfigurator())
    }
}

private struct ApplicationTerminationWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ApplicationTerminationPolicyView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ApplicationTerminationPolicyView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.preventsApplicationTerminationWhenModal = false
    }
}
