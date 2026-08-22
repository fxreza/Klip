import AppKit

/// Handlers for the `ShortcutAction`s that `GlobalKeyMonitor` dispatches to
/// but that belong to other Phase 3 tasks' models (locking, folders) or that
/// are genuinely new (quick paste, paste/copy-as-plain-text).
///
/// Everything marked `// 3E-stub` is a placeholder so this worktree builds
/// and its tests pass standalone; the owning task replaces it wholesale at
/// merge time:
///   - `keyLock()` → 3A (`Views/History/HistoryViewModel+Lock.swift`)
///   - `keyNewFolder()`, `keyRenameFolder()`, `keyMoveToFolder()` → 3B
///     (`Views/History/HistoryViewModel+Folders.swift`)
///   - `keyPastePlain()`, `keyCopyPlain()` → 3D (real plain-text paste/copy)
///
/// `quickPaste(index:)` is not a stub — selecting the Nth visible item and
/// pasting it is this task's own feature (⌘1…⌘9).
extension HistoryViewModel {
    // MARK: - Quick paste (⌘1…⌘9)

    /// Selects the `index`-th (1-based) visible item, if one exists, and
    /// pastes it — mirrors `keyEnter()`'s single-item paste path so a
    /// multi-selection is not disturbed by a stray ⌘-digit.
    func quickPaste(index: Int) {
        guard !isEditing else { return }
        guard let item = filteredItems[safe: index - 1] else { return }
        selectSingle(item.id)
        onPaste(item)
    }

    // MARK: - Plain-text paste/copy (3E-stub: replaced at merge by 3D)

    /// Until 3D lands real plain-text paste, ⌥↩ behaves like ↩.
    func keyPastePlain() {
        // 3E-stub: replaced at merge by 3D
        keyEnter()
    }

    /// Until 3D lands real plain-text copy, ⌥⌘C behaves like ⌘C.
    func keyCopyPlain() {
        // 3E-stub: replaced at merge by 3D
        keyCopy()
    }

}
