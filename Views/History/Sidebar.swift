// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/OverlayView.swift `sidebar` / `sidebarRow`.

import SwiftUI

/// Left rail: app title, the fixed **All** / **Favorites** scopes, the user's
/// folders with live counts, and the "New Folder" action.
///
/// Selection is an accent-gradient capsule moved between rows with
/// `matchedGeometryEffect("sidebarSel")` under `Theme.selectionSpring`.
///
/// Phase 3B makes the rows interactive beyond selection: double-clicking a
/// folder renames it, the context menu renames/deletes/creates, and every row
/// that can hold clips is an AppKit drop target (`SidebarDropTarget`) for rows
/// dragged out of the list — "All" meaning *remove from folder*. Folders are
/// also drag sources for reordering.
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

            row(title: "All", systemImage: "tray.full.fill", scopeValue: .all, acceptsClips: true)
                .contextMenu { generalMenu }
            row(
                title: "Favorites",
                systemImage: "star.fill",
                scopeValue: .favorites,
                count: viewModel.favoritesCount
            )
            .contextMenu { generalMenu }

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
                            count: counts[folder.id] ?? 0,
                            acceptsClips: true,
                            folder: folder
                        )
                        .contextMenu { folderMenu(folder) }
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: { viewModel.keyNewFolder() }) {
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
            .help("Create a folder")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Rows

    /// One sidebar row.
    ///
    /// Clicks are SwiftUI tap gestures rather than a `Button` so a folder can
    /// carry a second, double-click gesture (rename) without the button style
    /// swallowing it. `SidebarDropTarget` sits in the **background**: it
    /// forwards mouse-down to the responder chain, so the taps and the context
    /// menu above it keep working.
    @ViewBuilder
    private func row(
        title: String,
        systemImage: String,
        scopeValue: Scope,
        count: Int? = nil,
        acceptsClips: Bool = false,
        folder: Folder? = nil
    ) -> some View {
        let active = viewModel.scope == scopeValue
        let targeted = viewModel.dropTargetScope == scopeValue

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
        // Drop feedback: an accent-gradient outline plus a faint fill, so the
        // row reads as a target whether or not it is the selected scope.
        .background {
            if targeted {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent.opacity(0.18))
            }
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accentGradient, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .background(dropTarget(scopeValue: scopeValue, acceptsClips: acceptsClips, folder: folder))
        .onTapGesture(count: 2) {
            if let folder = folder {
                viewModel.requestRenameFolder(id: folder.id)
            } else {
                select(scopeValue)
            }
        }
        .onTapGesture(count: 1) { select(scopeValue) }
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private func select(_ scopeValue: Scope) {
        withAnimation(Theme.selectionSpring) { viewModel.scope = scopeValue }
    }

    private func dropTarget(scopeValue: Scope, acceptsClips: Bool, folder: Folder?) -> some View {
        SidebarDropTarget(
            acceptsClips: acceptsClips,
            folderID: folder?.id,
            folderName: folder?.name ?? "",
            onDropClips: { ids in
                viewModel.dropTargetScope = nil
                return viewModel.handleDrop(ids: ids, on: scopeValue)
            },
            onDropFolder: { dragged in
                viewModel.dropTargetScope = nil
                guard let folder = folder else { return false }
                return viewModel.reorderFolder(dragged: dragged, onto: folder.id)
            },
            onTargetChanged: { isTargeted in
                if isTargeted {
                    viewModel.dropTargetScope = scopeValue
                } else if viewModel.dropTargetScope == scopeValue {
                    viewModel.dropTargetScope = nil
                }
            }
        )
    }

    // MARK: - Menus

    /// Shown on the fixed scopes: only the create action makes sense there.
    @ViewBuilder
    private var generalMenu: some View {
        Button("New Folder…") { viewModel.keyNewFolder() }
    }

    /// Folder context menu.
    @ViewBuilder
    private func folderMenu(_ folder: Folder) -> some View {
        Button("Rename…") { viewModel.requestRenameFolder(id: folder.id) }

        if !viewModel.selectedIDs.isEmpty {
            Button("Move Selection Here") {
                viewModel.moveSelection(toFolder: folder.id)
            }
        }

        Divider()

        Button("New Folder…") { viewModel.keyNewFolder() }

        Divider()

        Button("Delete Folder…", role: .destructive) {
            viewModel.requestDeleteFolder(id: folder.id)
        }
    }
}
