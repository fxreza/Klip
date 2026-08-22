// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/OverlayView.swift `chipBar` / `chip`.

import SwiftUI

/// Capsule chips under the search field: All / Text / Link / Image / File /
/// Color / Code / Email / Phone.
///
/// The chips are wired to `ContentKind`. Detection itself is Phase 3C — until
/// it backfills `ClipboardItem.kind`, the Image / File / Text chips still work
/// (they key off the storage type) and the rest correctly show nothing. See
/// `FilterState.matches(_:chip:)`.
struct FilterChipBar: View {
    @ObservedObject var viewModel: HistoryViewModel

    @Namespace private var chipNS

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ChipFilter.bar, id: \.self) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func chip(_ filter: ChipFilter) -> some View {
        let active = viewModel.chipFilter == filter
        Button {
            withAnimation(Theme.selectionSpring) {
                // Tapping the active chip clears back to All.
                viewModel.chipFilter = (active && filter != .all) ? .all : filter
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.systemImage)
                Text(filter.label)
            }
            .font(.klip(.chip))
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if active {
                    Capsule().fill(Theme.accentGradient)
                        .matchedGeometryEffect(id: "chipSel", in: chipNS)
                } else {
                    Capsule().fill(Theme.chipInactive)
                }
            }
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show \(filter.label.lowercased()) items")
    }
}
