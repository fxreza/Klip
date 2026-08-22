import SwiftUI

/// Main content view - Split pane with list and detail.
///
/// All state lives in `HistoryViewModel` (owned by `HistoryWindowController`)
/// except the three `@FocusState` flags, which SwiftUI only supports inside a
/// `View`. This view is therefore just layout plus the change/notification
/// wiring that drives the view model.
struct HistoryContentView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var viewModel: HistoryViewModel

    @FocusState private var isSearchFocused: Bool
    @FocusState private var isTagInputFocused: Bool
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(store: store, viewModel: viewModel, isSearchFocused: $isSearchFocused)

            // Tag autocomplete (when typing #...)
            if viewModel.showTagAutocomplete && !store.allTags.isEmpty {
                TagAutocompleteBar(store: store, viewModel: viewModel)
            }

            Divider()

            // Split pane: List + Detail
            HSplitView {
                // Left: List
                listPane
                    .frame(minWidth: 280, maxWidth: 350)

                // Right: Detail
                DetailPane(
                    store: store,
                    viewModel: viewModel,
                    isTextEditorFocused: $isTextEditorFocused,
                    isTagInputFocused: $isTagInputFocused
                )
                .frame(minWidth: 300)
            }

            Divider()

            // Bottom action bar
            ActionBar(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        // searchText / debouncedSearchText / activeTagFilter reactions now live in
        // HistoryViewModel's didSet observers (debounce + applyFilters).
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
        .onChange(of: isTextEditorFocused) { newValue in
            if !newValue && viewModel.isEditing {
                viewModel.exitEditMode()
            }
        }
        .onChange(of: viewModel.selectedItem?.id) { _ in
            if viewModel.isEditing {
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

    private var listPane: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                VStack {
                    Spacer()
                    Text(viewModel.searchText.isEmpty && viewModel.activeTagFilter == nil ? "No clipboard history" : "No matches")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ClipboardListView(
                    items: viewModel.filteredItems,
                    selectedIndex: $viewModel.selectedIndex,
                    scrollTrigger: $viewModel.scrollTrigger,
                    store: store,
                    onSelect: { item in viewModel.copy(item) },
                    onDismiss: { viewModel.onDismiss() },
                    selectedID: viewModel.selectedID,
                    selectedIDs: $viewModel.selectedIDs,
                    onSelectSingle: { id in viewModel.selectSingle(id) },
                    onToggleSelection: { id in viewModel.toggleSelection(id) },
                    onExtendSelectionTo: { id in viewModel.extendSelectionTo(id) },
                    onTagTap: { tag in viewModel.activeTagFilter = tag }
                )
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}
