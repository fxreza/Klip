import SwiftUI
import AppKit

/// Root of the history window: sidebar | (search / chips / list + preview /
/// action bar), on a `.regularMaterial` card with an 18pt radius and a hairline
/// border — Clipfield's shell.
///
/// All state lives in `HistoryViewModel` (owned by `HistoryWindowController`)
/// except the `@FocusState` flags, which SwiftUI only supports inside a `View`.
/// This view is layout plus the change/notification wiring that drives the view
/// model.
struct HistoryContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager = .shared

    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTagInputFocused: Bool
    @FocusState private var isTextEditorFocused: Bool
    @FocusState private var isFolderFieldFocused: Bool

    /// Reduce Motion turns the open animation into a plain cut.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if !settings.sidebarCollapsed {
                    Sidebar(store: store, viewModel: viewModel)
                        .frame(width: settings.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    PanelResizer(width: $settings.sidebarWidth, range: 120...320, side: .leading)
                }

                // Middle column: search / chips / list / action bar. 180
                // keeps the list usable at the 560pt minimum window width
                // with the sidebar at its 120pt minimum and the preview at
                // its 200pt minimum.
                VStack(spacing: 0) {
                    SearchBar(store: store, viewModel: viewModel, isSearchFocused: $isSearchFocused)

                    if viewModel.showTagAutocomplete && !store.allTags.isEmpty {
                        TagAutocompleteBar(store: store, viewModel: viewModel, tags: viewModel.tagSuggestions)
                    }

                    FilterChipBar(viewModel: viewModel)

                    // Task 6B: the Tags chip shows every tag (most-used
                    // first) under the chip row so a tap sets
                    // `activeTagFilter` without needing `#` search. Hidden
                    // while the `#`-mode bar above is already showing its
                    // own (differently ordered) list, so the two never
                    // double up.
                    if viewModel.showTagsChipBar {
                        TagAutocompleteBar(store: store, viewModel: viewModel, tags: viewModel.tagsByUsage)
                    }

                    Divider()

                    listPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    ActionBar(viewModel: viewModel, settings: settings)
                }
                .frame(minWidth: 180, maxWidth: .infinity)
                .overlay(alignment: .bottom) { ToastOverlay(toast: viewModel.toast) }

                // User item 5: the preview is a *panel*, a sibling of the
                // sidebar, so it runs the full height of the window instead
                // of being boxed in between the chip bar and the action bar.
                // `PreviewPane` carries its own 13pt top padding, matching
                // the search bar's, so the columns' first lines line up.
                if settings.showPreviewPane {
                    PanelResizer(width: $settings.previewWidth, range: 200...440, side: .trailing)
                    PreviewPane(
                        store: store,
                        viewModel: viewModel,
                        isTextEditorFocused: $isTextEditorFocused,
                        isTagInputFocused: $isTagInputFocused
                    )
                    .frame(width: settings.previewWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            if viewModel.showNewFolderPrompt {
                NewFolderPrompt(viewModel: viewModel, isFieldFocused: $isFolderFieldFocused)
            }

            FolderPromptLayer(viewModel: viewModel)  // 3B: rename / delete / move
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        // The single window-level layer that draws every `.klipHelp` tooltip.
        // AppKit's own tooltips never fire in this borderless non-activating
        // panel — the full explanation is at the top of
        // `Views/Theme/KlipTooltip.swift`.
        //
        // Placed *before* `.clipShape` on purpose, so tooltips are clipped to
        // the rounded window and can never spill onto the desktop. It has to
        // live out here rather than on the individual buttons: the sidebar and
        // the 200-440pt preview pane are `HStack` siblings, so a per-call-site
        // overlay would be painted under the neighbouring column (and, inside
        // `ClipList`'s ScrollView, clipped outright).
        .klipTooltipHost()
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .scaleEffect(viewModel.isPresented || reduceMotion ? 1 : 0.96)
        .opacity(viewModel.isPresented || reduceMotion ? 1 : 0)
        .tint(Theme.accent)
        .preferredColorScheme(settings.colorScheme.swiftUI)
        .onChange(of: viewModel.showTagInput) { newValue in
            if newValue {
                isSearchFocused = false
                isTextEditorFocused = false
                // Defer by one run loop so the TextField is in the hierarchy before focusing
                DispatchQueue.main.async { isTagInputFocused = true }
            } else {
                isTagInputFocused = false
                // Restore search field focus when tag input is dismissed
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.isEditing) { newValue in
            // Focus half of enter/exitEditMode — the state half is in the view model.
            if newValue {
                isSearchFocused = false
                DispatchQueue.main.async { isTextEditorFocused = true }
            } else {
                isTextEditorFocused = false
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.showNewFolderPrompt) { newValue in
            if newValue {
                isSearchFocused = false
            } else {
                isFolderFieldFocused = false
                isSearchFocused = true
            }
        }
        .onChange(of: isTextEditorFocused) { newValue in
            if !newValue && viewModel.isEditing {
                viewModel.exitEditMode()
            }
        }
        .onChange(of: viewModel.selectedItem?.id) { newID in
            // Moving the selection *away from the item being edited* commits the
            // edit. Comparing against `editingItemID` (rather than "is editing at
            // all") lets an action select a row and open the editor in the same
            // turn — the row context menu's Edit does exactly that.
            if viewModel.isEditing && viewModel.editingItemID != newID {
                viewModel.exitEditMode()
            }
            if viewModel.showTagInput {
                viewModel.showTagInput = false
                viewModel.tagInputText = ""
            }
        }
        .onChange(of: store.items) { _ in
            viewModel.applyFilters(resetSelection: .preserve)
        }
        .onChange(of: store.folders) { _ in
            viewModel.validateScope()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if viewModel.isEditing {
                viewModel.exitEditMode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            if viewModel.isEditing {
                viewModel.exitEditMode()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
            viewModel.handleWindowDidOpen()
            // Delay needed for NSHostingView to have settled as key window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onAppear {
            viewModel.applyFilters(resetSelection: .keep)
        }
        .task(id: viewModel.selectedItem?.id) {
            await viewModel.reloadPreview()
        }
        .background(GlobalKeyMonitor(
            viewModel: viewModel,
            onBackspace: { viewModel.keyBackspace(searchFieldHasFocus: isSearchFocused) }
        ))
    }

    @ViewBuilder
    private var listPane: some View {
        if viewModel.filteredItems.isEmpty {
            emptyState
        } else {
            ClipList(store: store, viewModel: viewModel)
        }
    }

    private var emptyState: some View {
        let isFiltered = !viewModel.searchText.isEmpty
            || viewModel.activeTagFilter != nil
            || viewModel.chipFilter != .all
            || viewModel.scope != .all

        return VStack(spacing: 10) {
            Image(systemName: isFiltered ? "magnifyingglass" : "doc.on.clipboard")
                .font(Theme.icon(34))
                .foregroundStyle(.tertiary)
            Text(isFiltered ? "No matches" : "No clipboard history")
                .font(.klip(.preview))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
