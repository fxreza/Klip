// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/OverlayView.swift `sidebar` / `sidebarRow`.

import SwiftUI

/// Left rail: app title, the fixed **All** / **Favorites** scopes, the user's
/// folders with live counts, and the "New Folder" action.
///
/// Selection is an accent-gradient capsule moved between rows with
/// `matchedGeometryEffect("sidebarSel")` under `Theme.selectionSpring`.
struct Sidebar: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel

    @Namespace private var sidebarNS

    var body: some View {
        let counts = store.folderCounts()

        VStack(alignment: .leading, spacing: 3) {
            Text("Klip")
                .font(.klip(.sidebarTitle))
                .fontWeight(.bold)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 6)

            row(title: "All", systemImage: "tray.full.fill", scopeValue: .all)
            row(
                title: "Favorites",
                systemImage: "star.fill",
                scopeValue: .favorites,
                count: viewModel.favoritesCount
            )

            if !store.folders.isEmpty {
                Text("FOLDERS")
                    .font(.klip(.sectionHeader))
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.folders) { folder in
                        row(
                            title: folder.name,
                            systemImage: "folder.fill",
                            scopeValue: .folder(folder.id),
                            count: counts[folder.id] ?? 0
                        )
                        // 3B: rename (double-click / context menu / F2-style
                        // shortcut), delete with the move-vs-delete choice, and
                        // `onDrop` of dragged rows onto this row.
                        .contextMenu { folderMenu(folder) }
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: { viewModel.requestNewFolder() }) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.klip(.sidebar))
                    Text("New Folder")
                        .font(.klip(.sidebar))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .help("Create a folder (\(ShortcutManager.shared.displayString(for: .newFolder)))")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(title: String, systemImage: String, scopeValue: Scope, count: Int? = nil) -> some View {
        let active = viewModel.scope == scopeValue
        Button {
            withAnimation(Theme.selectionSpring) { viewModel.scope = scopeValue }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.klip(.chip))
                    .frame(width: .klipScaled(16))
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.klip(.caption))
                        .monospacedDigit()
                        .foregroundStyle(active ? Theme.onAccentSecondary : Color.secondary)
                }
            }
            .font(.klip(.sidebar))
            .fontWeight(active ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.accentGradient)
                        .matchedGeometryEffect(id: "sidebarSel", in: sidebarNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    /// Folder context menu. The entries exist so the surface (and its wording)
    /// is settled; 3B enables them.
    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        // 3B
        Button("Rename…") { }
            .disabled(true)
        Button("Delete Folder…", role: .destructive) { }
            .disabled(true)
    }
}
