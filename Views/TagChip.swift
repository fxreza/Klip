import SwiftUI

/// A small coloured pill for a user tag. Used in rows (tap to filter) and in
/// the preview pane's tag strip (tap the ✕ to remove).
struct TagChip: View {
    let label: String
    var onTap: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    private var chipColor: Color { TagChip.color(for: label) }

    static func color(for tag: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.40, green: 0.62, blue: 1.00),
            Color(red: 0.36, green: 0.78, blue: 0.57),
            Color(red: 1.00, green: 0.65, blue: 0.30),
            Color(red: 0.93, green: 0.45, blue: 0.63),
            Color(red: 0.68, green: 0.50, blue: 0.93),
            Color(red: 0.35, green: 0.82, blue: 0.82),
        ]
        return palette[abs(tag.hashValue) % palette.count]
    }

    static func normalize(_ input: String) -> String {
        let lower = input.lowercased()
        let dashed = lower.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        let trimmed = dashed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(32))
    }

    var body: some View {
        HStack(spacing: 2) {
            if let onTap = onTap {
                Button(action: onTap) { chipLabel }
                    .buttonStyle(.plain)
                    .help("Filter by #\(label)")
            } else {
                chipLabel
            }
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.klip(.badge))
                        .fontWeight(.bold)
                        .foregroundStyle(chipColor.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove tag")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(chipColor.opacity(0.14)))
        .overlay(Capsule().strokeBorder(chipColor.opacity(0.25), lineWidth: 0.5))
        .fixedSize()
    }

    private var chipLabel: some View {
        Text(label)
            .font(.klip(.badge))
            .foregroundStyle(chipColor)
    }
}
