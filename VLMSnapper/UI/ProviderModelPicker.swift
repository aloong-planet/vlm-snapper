import AppKit
import SwiftUI

struct ProviderModelPicker: NSViewRepresentable {
    let modelIDs: [String]
    @Binding var selection: String?
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let picker = NSPopUpButton(frame: .zero, pullsDown: false)
        picker.isBordered = false
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.select(_:))
        picker.setAccessibilityLabel(VLMSnapperStrings.currentModel)
        return picker
    }

    func updateNSView(_ picker: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        let titles = [VLMSnapperStrings.chooseModel] + modelIDs
        if picker.itemTitles != titles {
            picker.removeAllItems()
            picker.addItems(withTitles: titles)
        }
        for (index, item) in picker.itemArray.enumerated() {
            item.representedObject = index == 0 ? nil : modelIDs[index - 1]
        }
        picker.selectItem(at: selection.flatMap { modelIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        picker.isEnabled = isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: proposal.height ?? 32)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String?>
        init(selection: Binding<String?>) { self.selection = selection }
        @objc func select(_ sender: NSPopUpButton) {
            guard sender.isEnabled else { return }
            selection.wrappedValue = sender.selectedItem?.representedObject as? String
        }
    }
}
