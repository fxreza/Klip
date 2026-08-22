import SwiftUI

/// The Paste action button in the action bar: paste glyph, the Return key hint
/// and the "Paste" label.
///
/// Phase 3D turns this into a split button (Paste / Paste as Plain Text).
struct PasteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                    .font(Theme.icon(11, weight: .medium))

                Image(systemName: "return")
                    .font(Theme.icon(10, weight: .medium))

                Text("Paste")
                    .font(.klip(.chip))
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.accentGradient))
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .help("Paste into the previous app (↩)")
    }
}
