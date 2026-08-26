import SwiftUI

struct MarkdownResultView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [String] {
        markdown
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func blockView(_ block: String) -> some View {
        if block.hasPrefix("### ") {
            Text(String(block.dropFirst(4)))
                .font(.system(size: 14, weight: .semibold))
        } else if block.hasPrefix("## ") {
            Text(String(block.dropFirst(3)))
                .font(.system(size: 16, weight: .semibold))
        } else if block.hasPrefix("# ") {
            Text(String(block.dropFirst(2)))
                .font(.system(size: 18, weight: .bold))
        } else if block.contains("|") {
            Text(block)
                .font(.system(size: 12, design: .monospaced))
        } else {
            Text(block)
                .font(.system(size: 13))
                .lineSpacing(4)
        }
    }
}
