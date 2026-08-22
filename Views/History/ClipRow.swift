// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/ClipRowView.swift.

import SwiftUI
import AppKit

/// One clipboard item in the list.
///
/// Replaces `Views/ClipboardItemRow.swift`. Layout is Clipfield's: a 38×38
/// badge, a two-line title, a subtitle (source app · relative time · tags) and
/// trailing state badges. Every size goes through `CGFloat.klipScaled` and
/// every font through `Font.klip` so the whole row tracks the user's list
/// text-size setting.
///
/// Click behaviour is **not** here — `ClipList` owns it, and it is deliberately
/// unchanged from Buffer: a single click only selects, a double-click copies
/// and closes. Clipfield's single-click-pastes is not adopted.
struct ClipRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    /// The focused row (full accent gradient).
    let isPrimarySelection: Bool
    /// Part of a multi-selection (same gradient, dimmed).
    let isMultiSelected: Bool
    let isHovered: Bool
    var onTagTap: ((String) -> Void)? = nil

    @State private var thumbnail: NSImage?

    private var isHighlighted: Bool { isPrimarySelection || isMultiSelected }
    private var badgeSize: CGFloat { .klipScaled(38) }
    private var secondaryColor: Color { isHighlighted ? Theme.onAccentSecondary : .secondary }

    var body: some View {
        HStack(spacing: 11) {
            badge

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .lineLimit(2)
                    .font(.klip(item.displayKind == .code ? .rowTitleMono : .rowTitle))
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    .multilineTextAlignment(.leading)
                subtitle
            }

            Spacer(minLength: 6)

            trailingBadges
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: .klipScaled(54))
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius))
        .animation(Theme.selectionSpring, value: isPrimarySelection)
        .animation(Theme.selectionSpring, value: isMultiSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .task(id: item.id) {
            // Load thumbnail off the main thread, as before.
            if item.type == .image && thumbnail == nil {
                thumbnail = await loadThumbnail()
            }
        }
    }

    // MARK: - Title

    /// Collapse whitespace so multi-line clips still read as a compact preview.
    private var titleText: String {
        let text = item.previewText
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Badge

    @ViewBuilder
    private var badge: some View {
        if item.type == .image {
            imageBadge
        } else if let swatch = item.swatchColor {
            RoundedRectangle(cornerRadius: Theme.badgeCornerRadius)
                .fill(swatch)
                .frame(width: badgeSize, height: badgeSize)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.badgeCornerRadius)
                        .strokeBorder(Theme.swatchStroke, lineWidth: 1)
                )
                .shadow(color: swatch.opacity(0.5), radius: 4, y: 1)
        } else if item.type == .file, let icon = item.fileIcon(store: store) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: badgeSize, height: badgeSize)
        } else {
            kindBadge
        }
    }

    @ViewBuilder
    private var imageBadge: some View {
        if let img = thumbnail {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: badgeSize, height: badgeSize)
                .clipShape(RoundedRectangle(cornerRadius: Theme.badgeCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.badgeCornerRadius)
                        .strokeBorder(Theme.badgeStroke, lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: Theme.badgeCornerRadius)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: badgeSize, height: badgeSize)
        }
    }

    private var kindBadge: some View {
        let kind = item.displayKind
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.badgeCornerRadius)
                .fill(isHighlighted ? Theme.badgeFillSelected : Theme.badgeFill(kind))
                .frame(width: badgeSize, height: badgeSize)
            Image(systemName: item.type == .file ? "doc" : kind.systemImage)
                .font(Theme.icon(15, weight: .medium))
                .foregroundStyle(isHighlighted ? Color.white : Theme.kindTint(kind))
        }
    }

    // MARK: - Subtitle

    private var subtitle: some View {
        HStack(spacing: 5) {
            if let app = item.sourceApp {
                Text(app)
                    .fontWeight(.medium)
                    .font(.klip(.rowSubtitle))
                    .foregroundStyle(secondaryColor)
                Text("·")
                    .font(.klip(.rowSubtitle))
                    .foregroundStyle(secondaryColor)
            }

            RelativeTimestampView(timestamp: item.timestamp, role: .rowSubtitle, color: secondaryColor)

            ForEach(item.tags.prefix(2), id: \.self) { tag in
                TagChip(label: tag, onTap: { onTagTap?(tag) })
            }

            if item.tags.count > 2 {
                Text("+\(item.tags.count - 2)")
                    .font(.klip(.badge))
                    .foregroundStyle(secondaryColor)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Trailing state badges

    private var trailingBadges: some View {
        HStack(spacing: 6) {
            if item.isLocked {
                Image(systemName: "lock.fill")
                    .font(.klip(.badge))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.95) : Theme.lockTint)
                    .help("Locked — cannot be deleted")
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.klip(.badge))
                    .rotationEffect(.degrees(40))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.95) : Theme.pinTint)
                    .help("Pinned")
            }
            if item.isBookmarked {
                Image(systemName: "star.fill")
                    .font(.klip(.badge))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.95) : Theme.bookmarkTint)
                    .help("Favorite")
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
            .fill(fillStyle)
            .shadow(color: isPrimarySelection ? Theme.selectionGlow : .clear, radius: 6, y: 2)
    }

    private var fillStyle: AnyShapeStyle {
        if isPrimarySelection {
            return AnyShapeStyle(Theme.accentGradient)
        }
        if isMultiSelected {
            return AnyShapeStyle(Theme.accentGradient.opacity(Theme.multiSelectFillOpacity))
        }
        return AnyShapeStyle(isHovered ? Theme.rowHover : Color.clear)
    }

    // MARK: - Thumbnail

    /// Generate a small thumbnail asynchronously (unchanged from
    /// `ClipboardItemRow`, but sized for the larger 38pt badge).
    private func loadThumbnail() async -> NSImage? {
        let store = self.store
        let item = self.item
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let original = store.image(for: item) else {
                    continuation.resume(returning: nil)
                    return
                }

                let thumbSize = NSSize(width: 76, height: 76)
                let thumb = NSImage(size: thumbSize)
                thumb.lockFocus()
                original.draw(
                    in: NSRect(origin: .zero, size: thumbSize),
                    from: NSRect(origin: .zero, size: original.size),
                    operation: .copy,
                    fraction: 1.0
                )
                thumb.unlockFocus()

                continuation.resume(returning: thumb)
            }
        }
    }
}
