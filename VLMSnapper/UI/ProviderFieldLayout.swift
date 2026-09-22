import SwiftUI

// Preserve the approved field ratio while allowing the two columns to stack.
struct ProviderFieldLayout: Layout {
    private let gap: CGFloat = 14

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let sizes = sizes(width: width, subviews: subviews)
        return CGSize(width: width, height: width >= 680
            ? sizes.map(\.height).max() ?? 0
            : sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, sizes.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(width: bounds.width, subviews: subviews)
        var origin = bounds.origin
        for (view, size) in zip(subviews, sizes) {
            view.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
            if bounds.width >= 680 { origin.x += size.width + gap }
            else { origin.y += size.height + gap }
        }
    }

    private func sizes(width: CGFloat, subviews: Subviews) -> [CGSize] {
        subviews.enumerated().map { index, view in
            let fieldWidth = width >= 680 ? (width - gap) * (index == 0 ? 1 : 1.1) / 2.1 : width
            let height = view.sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil)).height
            return CGSize(width: fieldWidth, height: height)
        }
    }
}
