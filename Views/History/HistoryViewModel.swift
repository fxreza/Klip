import AppKit
import SwiftUI

/// All mutable state and behaviour of the history window.
///
/// Before the Phase 1 split this lived as ~35 `@State` properties plus a dozen
/// private helpers inside `HistoryContentView`. It is owned by
/// `HistoryWindowController` so it survives SwiftUI view identity resets, which
/// is why `shouldResetOnOpen` / `savedSelectedID` no longer need `@Binding`
/// plumbing back to the controller.
///
/// Focus is deliberately *not* here: `@FocusState` only works inside a `View`,
/// so `HistoryContentView` owns the three focus flags and reacts to
/// `isEditing` / `showTagInput` changes.
@MainActor
final class HistoryViewModel: ObservableObject {
    let store: ClipboardStore

    // MARK: - Controller callbacks (wired by HistoryWindowController)

    // Phase 3D: every write-back takes an explicit `PasteMode` (rich/plain) —
    // `HistoryWindowController` threads it straight through to
    // `PasteController`. Call sites that don't care about the distinction
    // (multi-select bulk actions, etc.) pass `defaultPasteMode`.
    var onCopyToClipboard: (ClipboardItem, PasteMode) -> Void = { _, _ in }
    var onPaste: (ClipboardItem, PasteMode) -> Void = { _, _ in }
    var onPasteMultiple: ([ClipboardItem], PasteMode) -> Void = { _, _ in }
    var onDismiss: () -> Void = { }

    // MARK: - Controller-owned persistence of search/selection across opens

    /// Set to true by `HistoryWindowController` when the window has been closed for
    /// more than 90 seconds (or on the very first open). Search/tag state is reset
    /// only when this is true; the open handler then writes false back so a second
    /// notification in the same session is a no-op.
    var shouldResetOnOpen: Bool = true
    /// Last selected item UUID, kept in sync with `selectedID` and restored on
    /// reopen within the threshold.
    var savedSelectedID: UUID?

    // MARK: - Search

    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            let newValue = searchText
            showTagAutocomplete = newValue.hasPrefix("#")

            searchDebounceTask?.cancel()

            if newValue.isEmpty {
                // Instantly update when search text is cleared
                debouncedSearchText = newValue
            } else {
                searchDebounceTask = Task { [weak self] in
                    // 200ms debounce
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.debouncedSearchText = newValue }
                }
            }
        }
    }

    @Published var debouncedSearchText = "" {
        didSet {
            guard debouncedSearchText != oldValue else { return }
            // Don't reset selection when in tag autocomplete mode (list is unchanged)
            applyFilters(resetSelection: debouncedSearchText.hasPrefix("#") ? .keep : .defaultItem)
        }
    }

    private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Filtering

    @Published var activeTagFilter: String? = nil {
        didSet {
            guard activeTagFilter != oldValue else { return }
            // Reset selection to the first item of the new tag filter
            applyFilters(resetSelection: .defaultItem)
        }
    }

    /// Sidebar section (All / Favorites / a folder).
    @Published var scope: Scope = .all {
        didSet {
            guard scope != oldValue else { return }
            applyFilters(resetSelection: .defaultItem)
            scrollTrigger = true
        }
    }

    /// Content-kind chip under the search field.
    @Published var chipFilter: ChipFilter = .all {
        didSet {
            guard chipFilter != oldValue else { return }
            applyFilters(resetSelection: .defaultItem)
            scrollTrigger = true
        }
    }

    @Published var filteredItems: [ClipboardItem] = []

    var filterState: FilterState {
        FilterState(query: debouncedSearchText, tag: activeTagFilter, scope: scope, chip: chipFilter)
    }

    // MARK: - Inline prompts
    //
    // A system alert would make the borderless panel resign key and close, so
    // every confirmation is an inline `PromptCard` over a scrim instead.

    /// New-folder prompt visibility. Rename/delete prompts arrive in 3B.
    @Published var showNewFolderPrompt = false
    @Published var newFolderName = ""

    /// True while any inline prompt owns the keyboard, so list shortcuts stand
    /// down and Esc dismisses the prompt rather than the window.
    var isPromptShowing: Bool { showNewFolderPrompt || isFolderPromptShowing }  // 3B

    // MARK: - Selection

    @Published var selectedIndex = 0 {
        didSet {
            guard selectedIndex != oldValue else { return }
            selectedID = filteredItems[safe: selectedIndex]?.id
        }
    }
    /// Track selection by ID so it survives list insertions.
    @Published var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            // Keep savedSelectedID in sync so the controller can restore it on next open
            savedSelectedID = selectedID
        }
    }
    @Published var selectedIDs: Set<UUID> = []
    @Published var selectionAnchor: UUID?
    /// Triggers scroll-to-selection in `ClipList` on keyboard navigation / scope changes.
    @Published var scrollTrigger = false

    // MARK: - Detail pane

    @Published var previewImage: NSImage?
    @Published var chunkedText = ChunkedTextState()
    @Published var itemSize: Int?
    @Published var isExtractingText = false
    @Published var showDeleteConfirmation = false

    // MARK: - Tag input

    @Published var showTagAutocomplete: Bool = false
    @Published var showTagInput: Bool = false
    @Published var tagInputText: String = ""

    // MARK: - Editing

    @Published var isEditing = false
    @Published var editText = ""
    @Published var editingItemID: UUID?

    // MARK: - Presentation

    /// Drives the panel's open animation (scale 0.96 → 1 + fade). Flipped by
    /// `HistoryWindowController` right after the window is ordered in.
    @Published var isPresented = false

    // MARK: - 3E state
    //
    // Custom shortcuts (Phase 3E) need no additional stored state here: the
    // key → action table lives in `ShortcutManager.shared` (observed
    // directly by `ActionBar` and `Views/Settings/ShortcutsTab.swift`), and
    // every dispatch target in `GlobalKeyMonitor`/
    // `HistoryViewModel+Shortcuts.swift` reuses selection/mode state that
    // already exists above (`isEditing`, `showTagInput`, `selectedItem`,
    // `filteredItems`, …). This block is a marker for future 3E-owned state,
    // kept separate from sibling tasks' own `// MARK: - 3x state` blocks.

    // MARK: - Init

    init(store: ClipboardStore) {
        self.store = store
    }

    // MARK: - Derived values

    var tagSuggestions: [String] {
        let query = searchText.hasPrefix("#") ? String(searchText.dropFirst()).lowercased() : ""
        if query.isEmpty { return store.allTags }
        return store.allTags.filter { $0.hasPrefix(query) }
    }

    func tagInputSuggestions(excluding existing: [String]) -> [String] {
        guard !tagInputText.isEmpty else { return [] }
        return store.allTags.filter { $0.hasPrefix(tagInputText.lowercased()) && !existing.contains($0) }
    }

    /// Get the first unpinned item, or the first pinned item if no unpinned items exist
    var defaultSelectedItem: ClipboardItem? {
        return filteredItems.first(where: { !$0.isPinned }) ?? filteredItems.first
    }

    /// Get all selected items in filtered list order
    var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    /// Get the primary selected item (for detail pane when multiple selected or single item)
    /// Returns the first selected item in list order
    var selectedItem: ClipboardItem? {
        selectedItems.first
    }

    /// Selection status for UI display
    var selectionCount: Int {
        selectedIDs.count
    }

    /// Total size of all selected items
    var selectedItemsTotalSize: Int {
        selectedItems.reduce(0) { sum, item in
            sum + (store.itemSize(for: item) ?? 0)
        }
    }

    // MARK: - Filtering + selection reset

    /// How `applyFilters` should re-point the selection after recomputing the list.
    enum SelectionReset {
        /// Leave the selection untouched (first render, and `#…` autocomplete typing).
        case keep
        /// Snap to the first unpinned item (or the first item if all are pinned).
        case defaultItem
        /// Keep the selected UUID if it survived; otherwise take the item now at the
        /// same position, or the last one. Used when the store's items change.
        case preserve
        /// Restore the given UUID if it is still in the list, else `defaultItem`.
        /// The caller passes the value captured *before* any other reset ran, which
        /// is what the pre-split code observed (its `savedSelectedID` write was
        /// deferred to the next SwiftUI update pass).
        case restore(UUID?)
    }

    /// The single recompute-and-reselect path. Replaces the five copy-pasted
    /// blocks that used to live in `HistoryContentView`'s onChange/onReceive
    /// handlers.
    func applyFilters(resetSelection: SelectionReset) {
        let currentFiltered = FilterState.apply(store.items, filterState)
        self.filteredItems = currentFiltered

        switch resetSelection {
        case .keep:
            return

        case .defaultItem:
            // Find first unpinned item in filtered results
            let defaultItem = currentFiltered.first(where: { !$0.isPinned }) ?? currentFiltered.first
            point(at: defaultItem?.id, in: currentFiltered)

        case .restore(let saved):
            // • Within threshold + saved UUID still in filtered list → restore it
            // • Otherwise → first unpinned item (or first if all pinned)
            let targetID: UUID?
            if let saved = saved, currentFiltered.contains(where: { $0.id == saved }) {
                targetID = saved
            } else {
                targetID = (currentFiltered.first(where: { !$0.isPinned }) ?? currentFiltered.first)?.id
            }
            point(at: targetID, in: currentFiltered)

        case .preserve:
            // Remove deleted items from selection set
            selectedIDs = selectedIDs.filter { id in
                currentFiltered.contains { $0.id == id }
            }

            // Preserve selection by UUID lookup, adjust index if needed
            guard let id = selectedID else { return }
            if let newIndex = currentFiltered.firstIndex(where: { $0.id == id }) {
                if selectedIndex != newIndex { selectedIndex = newIndex }
            } else {
                // Selected item was deleted — select the item now at the same position (or last)
                let fallbackIndex = min(selectedIndex, currentFiltered.count - 1)
                if let fallbackItem = currentFiltered[safe: fallbackIndex] {
                    selectedID = fallbackItem.id
                    selectedIDs = [fallbackItem.id]
                    selectionAnchor = fallbackItem.id
                    selectedIndex = fallbackIndex
                } else {
                    selectedID = nil
                    selectedIDs = []
                    selectionAnchor = nil
                    selectedIndex = 0
                }
            }
        }
    }

    /// Make `targetID` the one and only selection, syncing index and anchor.
    private func point(at targetID: UUID?, in list: [ClipboardItem]) {
        selectedID = targetID
        if let id = targetID {
            selectedIDs = [id]
            selectionAnchor = id
        } else {
            selectedIDs = []
            selectionAnchor = nil
        }
        // Calculate the correct index
        if let index = list.firstIndex(where: { $0.id == targetID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }

    // MARK: - Selection helpers

    /// Select a single item (clears previous multi-selection)
    func selectSingle(_ id: UUID) {
        selectedIDs = [id]
        selectionAnchor = id
        selectedID = id  // Explicitly set selectedID
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        }
    }

    /// Toggle an item in multi-select (Cmd+click behavior)
    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        selectionAnchor = id
        if let index = filteredItems.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
            // selectedID is synced by selectedIndex's didSet
        }
    }

    /// Extend selection from anchor to target item (Shift+click behavior)
    func extendSelectionTo(_ targetID: UUID) {
        guard let anchorID = selectionAnchor else {
            selectSingle(targetID)
            return
        }

        guard let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchorID }),
              let targetIndex = filteredItems.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(filteredItems[range].map { $0.id })
        selectedIndex = targetIndex
    }

    /// Extend selection upward (Shift+↑ behavior)
    func extendSelectionUp() {
        guard selectedIndex > 0 else { return }

        let currentItem = filteredItems[selectedIndex]
        let previousIndex = selectedIndex - 1
        let previousItem = filteredItems[previousIndex]

        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }

        // If moving up, always include the new item
        selectedIDs.insert(previousItem.id)
        selectionAnchor = selectionAnchor ?? currentItem.id

        selectedIndex = previousIndex
    }

    /// Extend selection downward (Shift+↓ behavior)
    func extendSelectionDown() {
        guard selectedIndex < filteredItems.count - 1 else { return }

        let currentItem = filteredItems[selectedIndex]
        let nextIndex = selectedIndex + 1
        let nextItem = filteredItems[nextIndex]

        if selectedIDs.isEmpty {
            selectSingle(currentItem.id)
            return
        }

        // If moving down, always include the new item
        selectedIDs.insert(nextItem.id)
        selectionAnchor = selectionAnchor ?? currentItem.id

        selectedIndex = nextIndex
    }

    /// Clear all selections
    func clearSelection() {
        selectedIDs = []
        selectionAnchor = nil
        selectedID = nil
    }

    func navigateUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
            // Clear multi-selection when navigating without Shift
            if let item = filteredItems[safe: selectedIndex] {
                selectedID = item.id
                selectedIDs = [item.id]
                selectionAnchor = item.id
            }
        }
    }

    func navigateDown() {
        if selectedIndex < filteredItems.count - 1 {
            selectedIndex += 1
            // Clear multi-selection when navigating without Shift
            if let item = filteredItems[safe: selectedIndex] {
                selectedID = item.id
                selectedIDs = [item.id]
                selectionAnchor = item.id
            }
        }
    }

    // MARK: - Scopes (sidebar)

    /// Every selectable scope in sidebar order: All, Favorites, then folders.
    var orderedScopes: [Scope] {
        [.all, .favorites] + store.folders.map { .folder($0.id) }
    }

    var favoritesCount: Int {
        store.items.reduce(0) { $0 + ($1.isBookmarked ? 1 : 0) }
    }

    /// Display name of the current scope, used by the empty state.
    func title(for scope: Scope) -> String {
        switch scope {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .folder(let id): return store.folders.first(where: { $0.id == id })?.name ?? "Folder"
        }
    }

    /// ⌘] / ⌘[ — move to the next / previous sidebar scope, wrapping around.
    func cycleScope(by delta: Int) {
        let scopes = orderedScopes
        guard !scopes.isEmpty else { return }
        let current = scopes.firstIndex(of: scope) ?? 0
        let count = scopes.count
        let next = ((current + delta) % count + count) % count
        scope = scopes[next]
    }

    /// Drop back to `.all` if the selected folder disappeared (deleted in 3B,
    /// or a stale scope after a store reload).
    func validateScope() {
        if case .folder(let id) = scope, !store.folders.contains(where: { $0.id == id }) {
            scope = .all
        }
    }

    // MARK: - Folders (create; rename/delete/drag are 3B)

    /// Open the inline "New Folder" prompt. A system alert cannot be used here:
    /// it makes the borderless panel resign key, which closes the window.
    func requestNewFolder() {
        newFolderName = ""
        showNewFolderPrompt = true
    }

    /// Create the folder and switch the sidebar to it.
    func confirmNewFolder() {
        let name = newFolderName
        showNewFolderPrompt = false
        newFolderName = ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let folder = store.createFolder(name: name)
        scope = .folder(folder.id)
    }

    func cancelNewFolder() {
        showNewFolderPrompt = false
        newFolderName = ""
    }

    /// Esc while a prompt is up closes the top-most prompt only.
    /// Returns true when a prompt was dismissed.
    @discardableResult
    func dismissTopPrompt() -> Bool {
        if dismissTopFolderPrompt() { return true }  // 3B
        if showNewFolderPrompt {
            cancelNewFolder()
            return true
        }
        return false
    }

    // MARK: - Layout toggles (persisted in SettingsManager)

    func toggleSidebar() {
        SettingsManager.shared.sidebarCollapsed.toggle()
    }

    func togglePreviewPane() {
        SettingsManager.shared.showPreviewPane.toggle()
    }

    // MARK: - Window lifecycle

    /// Runs on `.bufferWindowDidOpen`. Returns nothing; the view still owns the
    /// deferred search-field focus because focus cannot live in an ObservableObject.
    func handleWindowDidOpen() {
        // Captured before the resets below, because those can move the selection
        // (and therefore savedSelectedID) as a side effect.
        let restoreTarget = savedSelectedID

        // Only reset persistent search state if the window was closed long enough ago
        // (or this is the first open). shouldResetOnOpen is set by the controller in
        // showWindow(_:) before the notification fires.
        if shouldResetOnOpen {
            searchText = ""
            debouncedSearchText = ""
            activeTagFilter = nil
            scope = .all
            chipFilter = .all
        } else {
            debouncedSearchText = searchText
            // A folder deleted while the window was closed must not strand the
            // sidebar on an empty scope.
            validateScope()
        }

        // Transient UI state always resets
        showTagAutocomplete = false
        showTagInput = false
        tagInputText = ""
        isEditing = false
        showNewFolderPrompt = false
        newFolderName = ""
        showDeleteConfirmation = false
        resetFolderPrompts()  // 3B

        // Recalculate cache immediately and point at the restored / default item
        applyFilters(resetSelection: shouldResetOnOpen ? .defaultItem : .restore(restoreTarget))

        // Trigger scroll so ClipList brings the selected row into view
        scrollTrigger = true
    }

    // MARK: - Editing

    func enterEditMode() {
        guard let item = selectedItem, item.isEditable else { return }
        editingItemID = item.id
        editText = item.textContent ?? ""
        isEditing = true
        showTagInput = false
    }

    func exitEditMode() {
        // Commit edit to the original item (not selectedItem, which may have changed)
        if let itemID = editingItemID,
           let item = store.items.first(where: { $0.id == itemID }) {
            store.updateText(editText, for: item)

            // Phase 3D deliverable 3: editing a rich item keeps plain text
            // only — its RTF/flavors backing is now stale (it describes text
            // that no longer exists) and is dropped along with the files.
            if item.rtfFilename != nil || item.flavorsFilename != nil {
                store.clearRichFlavors(for: item)
            }

            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(editText, forType: .string)
        }
        editingItemID = nil
        isEditing = false
    }

    func toggleEditMode() {
        if isEditing {
            exitEditMode()
        } else {
            enterEditMode()
        }
    }

    // MARK: - Item actions

    func copySelected() {
        if let item = selectedItem { onCopyToClipboard(item, defaultPasteMode) }
    }

    func copy(_ item: ClipboardItem) {
        if store.fileIsMissing(item) {
            showToast("Some files are missing from disk")
        }
        onCopyToClipboard(item, defaultPasteMode)
    }

    func togglePinOnSelection() {
        if let item = selectedItem { store.togglePin(for: item) }
    }

    func toggleBookmarkOnSelection() {
        if let item = selectedItem { store.toggleBookmark(for: item) }
    }

    // Delete entry points below all funnel through `performDelete(ids:)`
    // (Views/History/HistoryViewModel+Lock.swift, task 3A) so locked items are
    // skipped consistently, kept selected, and reported via `toast` no matter
    // which UI path triggered the delete.

    func deleteSelection() {
        guard let item = selectedItem else { return }
        performDelete(ids: [item.id])
    }

    func delete(_ item: ClipboardItem) {
        performDelete(ids: [item.id])
    }

    func deleteSelectedItems() {
        performDelete(ids: selectedIDs)
    }

    func saveSelectedImage() {
        if selectedItem?.type == .image, let img = previewImage {
            PasteController.saveImageToDisk(img)
        }
    }

    /// Save an arbitrary image item (row context menu). Reuses the already
    /// decoded preview when it happens to be the selected item.
    func saveImage(for item: ClipboardItem) {
        guard item.type == .image else { return }
        if item.id == selectedItem?.id, let img = previewImage {
            PasteController.saveImageToDisk(img)
            return
        }
        guard let img = store.image(for: item) else { return }
        PasteController.saveImageToDisk(img)
    }

    func extractTextFromSelection() async {
        guard let img = previewImage, let item = selectedItem else { return }
        isExtractingText = true
        let result = await OCRService.shared.recognizeText(from: img)
        let text = result ?? "No text found in this image."
        store.setOCRText(text, for: item)
        isExtractingText = false
    }

    func copyOCRText(_ ocrText: String) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ocrText, forType: .string)
    }

    // MARK: - Tags

    func addTag(_ tag: String, to item: ClipboardItem) {
        store.addTag(tag, to: item)
    }

    func removeTag(_ tag: String, from item: ClipboardItem) {
        store.removeTag(tag, from: item)
    }

    /// Commit the inline tag input's raw text to `item`.
    func commitTagInput(for item: ClipboardItem?) {
        if let item = item {
            let normalized = TagChip.normalize(tagInputText)
            if !normalized.isEmpty { store.addTag(normalized, to: item) }
        }
        tagInputText = ""
        showTagInput = false
    }

    /// Pick a suggestion from the inline tag input's autocomplete row.
    func applyTagSuggestion(_ suggestion: String, to item: ClipboardItem) {
        store.addTag(suggestion, to: item)
        tagInputText = ""
        showTagInput = false
    }

    func cancelTagInput() {
        tagInputText = ""
        showTagInput = false
    }

    /// Apply a tag as the active list filter (chip tap / autocomplete bar tap).
    func applyTagFilter(_ tag: String) {
        activeTagFilter = tag
        searchText = ""
        showTagAutocomplete = false
    }

    // MARK: - Preview loading

    /// Body of `HistoryContentView`'s `.task(id: selectedItem?.id)`.
    func reloadPreview() async {
        // Clear preview
        previewImage = nil
        chunkedText = ChunkedTextState()
        isExtractingText = false
        itemSize = nil
        showTagInput = false
        tagInputText = ""

        // Load new preview async
        if let item = selectedItem {
            itemSize = store.itemSize(for: item)

            if item.type == .image {
                previewImage = await loadPreviewImage(for: item)
            } else if item.type == .text {
                if item.isFileBacked || (item.textContent?.count ?? 0) > 5000 {
                    await loadInitialChunk(for: item)
                } else {
                    chunkedText.visibleText = item.textContent ?? ""
                    chunkedText.reachedEOF = true
                }
            }
        }
    }

    private func loadPreviewImage(for item: ClipboardItem) async -> NSImage? {
        let store = self.store
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let img = store.image(for: item)
                continuation.resume(returning: img)
            }
        }
    }

    private func loadInitialChunk(for item: ClipboardItem) async {
        chunkedText.isLoadingMore = true // Initial load spinner

        let chunkResult = await Task.detached(priority: .userInitiated) {
            self.store.textChunk(for: item, charCount: ChunkedTextState.initialChars)
        }.value

        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }

    func loadNextChunk(for item: ClipboardItem) async {
        guard !chunkedText.isLoadingMore && chunkedText.hasMore else { return }

        chunkedText.isLoadingMore = true
        let nextCharCount = chunkedText.loadedCharCount + ChunkedTextState.chunkSize

        let chunkResult = await Task.detached(priority: .userInitiated) {
            self.store.textChunk(for: item, charCount: nextCharCount)
        }.value

        if let result = chunkResult {
            chunkedText.visibleText = result.text
            chunkedText.totalBytes = result.totalBytes
            chunkedText.loadedCharCount = result.text.count
            chunkedText.reachedEOF = result.reachedEOF
        }
        chunkedText.isLoadingMore = false
    }

    // MARK: - Formatting

    func formattedByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    func formattedSize(bytes: Int) -> String {
        return formattedByteCount(bytes)
    }

    // MARK: - Key handlers (called by GlobalKeyMonitor)

    func keyUp() {
        guard !isEditing else { return }
        scrollTrigger = true
        navigateUp()
    }

    func keyDown() {
        guard !isEditing else { return }
        scrollTrigger = true
        navigateDown()
    }

    func keyExtendUp() {
        guard !isEditing else { return }
        scrollTrigger = true
        extendSelectionUp()
    }

    func keyExtendDown() {
        guard !isEditing else { return }
        scrollTrigger = true
        extendSelectionDown()
    }

    func keyEnter() {
        if isEditing { return }
        if showTagInput {
            commitTagInput(for: selectedItem)
        } else if searchText.hasPrefix("#") {
            let tagQuery = String(searchText.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let match = store.allTags.first(where: { $0 == tagQuery }) ?? store.allTags.first(where: { $0.hasPrefix(tagQuery) }) {
                applyTagFilter(match)
            }
        } else if !selectedItems.isEmpty {
            onPasteMultiple(Array(selectedItems), defaultPasteMode)
        } else if let item = selectedItem {
            onPaste(item, defaultPasteMode)
        }
    }

    /// Esc unwinds one layer at a time: edit mode → tag input → inline prompt →
    /// close the window.
    func keyEscape() {
        if isEditing {
            exitEditMode()
            return
        }
        if showTagInput {
            showTagInput = false
            tagInputText = ""
            return
        }
        if dismissTopPrompt() { return }
        onDismiss()
    }

    func keyDelete() {
        guard !isEditing else { return }
        deleteSelection()
    }

    func keyCopy() {
        guard !isEditing else { return }
        copySelected()
    }

    func keyPin() {
        guard !isEditing else { return }
        togglePinOnSelection()
    }

    func keyBookmark() {
        guard !isEditing else { return }
        toggleBookmarkOnSelection()
    }

    /// ⌘S — "Save to Disk". Generalized in Phase 3F to any selected item
    /// (image/text/file), not just images; the name stays `keySaveImage` so
    /// `GlobalKeyMonitor`'s existing wiring doesn't need to change.
    func keySaveImage() {
        guard !isEditing else { return }
        saveSelectedToDisk()
    }

    func keyAddTag() {
        guard !isEditing else { return }
        guard selectedItem != nil else { return }
        showTagInput = true
    }

    func keyEdit() {
        toggleEditMode()
    }

    /// ⌘] — next sidebar scope.
    func keyNextScope() {
        guard !isEditing else { return }
        cycleScope(by: 1)
    }

    /// ⌘[ — previous sidebar scope.
    func keyPrevScope() {
        guard !isEditing else { return }
        cycleScope(by: -1)
    }

    /// Debug helper (`KLIP_SELECT_FIRST=1`): point the selection at the first
    /// row so screenshots can show the selected state without driving the UI.
    func selectFirstItem() {
        guard let first = filteredItems.first else { return }
        selectSingle(first.id)
    }

    func keyTabComplete() {
        guard !isEditing else { return }
        if showTagInput {
            guard !tagInputText.isEmpty, let item = selectedItem else { return }
            let suggestions = store.allTags.filter {
                $0.hasPrefix(tagInputText.lowercased()) && !item.tags.contains($0)
            }
            guard let first = suggestions.first else { return }
            applyTagSuggestion(first, to: item)
        } else if searchText.hasPrefix("#") {
            let tagQuery = String(searchText.dropFirst()).lowercased()
            let suggestions = store.allTags.filter { tagQuery.isEmpty || $0.hasPrefix(tagQuery) }
            guard let first = suggestions.first else { return }
            applyTagFilter(first)
        }
    }

    /// ⌫ with an empty search field clears the active tag filter.
    /// Returns true if the key was consumed. `searchFieldHasFocus` comes from the
    /// view because focus state cannot live here.
    func keyBackspace(searchFieldHasFocus: Bool) -> Bool {
        guard !isEditing else { return false }
        guard searchFieldHasFocus, searchText.isEmpty, activeTagFilter != nil else { return false }
        activeTagFilter = nil
        return true
    }

    // MARK: - 3A state

    /// A transient bottom-of-content message (currently only used for the
    /// "N locked clips were not deleted" notice). Methods live in
    /// `HistoryViewModel+Lock.swift`; rendered by `Views/History/Toast.swift`.
    struct ToastMessage: Equatable {
        let text: String
        let systemImage: String
    }

    @Published var toast: ToastMessage?

    /// Cancelled/replaced whenever a new toast is shown, so an earlier
    /// auto-clear never stomps a newer message.
    var toastDismissTask: Task<Void, Never>?
    // MARK: - 3B state
    //
    // Folder rename / delete / move prompts and drag-and-drop. Behaviour lives
    // in `HistoryViewModel+Folders.swift`; only stored state is here so the file
    // stays mergeable with the other Phase 3 tasks.

    /// Inline rename prompt (double-click a sidebar folder, context menu, ⌘R).
    @Published var showRenameFolderPrompt = false
    @Published var renameFolderID: UUID?
    @Published var renameFolderName = ""

    /// Stages of the inline "Delete Folder" card.
    enum FolderDeleteStage: Equatable {
        /// Move the clips out, or delete them.
        case choice
        /// Locked clips found — typing DELETE is required to include them.
        case lockedConfirm
        /// What happened, after a delete that left locked clips behind.
        case result
    }

    @Published var showDeleteFolderPrompt = false
    @Published var deleteFolderID: UUID?
    @Published var deleteFolderStage: FolderDeleteStage = .choice
    /// Must read exactly `HistoryViewModel.lockedDeleteConfirmationWord`.
    @Published var deleteLockedConfirmText = ""
    /// Outcome line shown in `.result` (e.g. "Deleted 4, kept 2 locked clips…").
    @Published var folderActionMessage: String?

    /// Inline "Move to Folder" picker (⌘M / context menu).
    @Published var showMoveToFolderPrompt = false
    @Published var moveFolderQuery = ""
    /// Index into `moveToFolderOptions`.
    @Published var moveFolderHighlight = 0
    /// Ids the picker will move; captured when it opens so a later selection
    /// change cannot retarget it.
    var pendingMoveIDs: Set<UUID> = []

    /// Sidebar row currently highlighted as a drop target, or nil.
    @Published var dropTargetScope: Scope?
}
