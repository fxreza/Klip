import Foundation
import AppKit
import Combine

/// Manages persistent storage of clipboard history
class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []

    /// Folders, always sorted by `sortIndex`.
    @Published private(set) var folders: [Folder] = []

    private func runOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    /// Item cap, or `nil` when the user chose "Unlimited" (never evict).
    private var maxItems: Int? { SettingsManager.shared.historyLimit.maxItems }
    private let fileManager = FileManager.default
    private let saveQueue = DispatchQueue(label: "com.buffer.save", qos: .utility)

    /// Debounce window for history writes. Every public mutation schedules a
    /// save; bursts collapse into one atomic write.
    private static let saveDebounceInterval: TimeInterval = 0.3

    // Guarded by `saveQueue`.
    private var pendingItems: [ClipboardItem]?
    private var pendingSaveWorkItem: DispatchWorkItem?

    // MARK: - On-disk schema

    private static let historySchemaVersion = 2
    private static let foldersSchemaVersion = 1

    private struct HistoryFile: Codable {
        var version: Int
        var items: [ClipboardItem]
    }

    private struct FoldersFile: Codable {
        var version: Int
        var folders: [Folder]
    }

    // MARK: - Locations

    private var storageDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["KLIP_DATA_DIR"], !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Klip", isDirectory: true)
    }

    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }

    private var foldersFileURL: URL {
        storageDirectory.appendingPathComponent("folders.json")
    }

    private var imagesDirectory: URL {
        storageDirectory.appendingPathComponent("images", isDirectory: true)
    }

    private var textsDirectory: URL {
        storageDirectory.appendingPathComponent("texts", isDirectory: true)
    }

    /// Copied-in file payloads, one subdirectory per item (Phase 3F).
    private var filesDirectory: URL {
        storageDirectory.appendingPathComponent("files", isDirectory: true)
    }

    /// Archived pasteboard flavors, one plist per item (Phase 3D).
    private var flavorsDirectory: URL {
        storageDirectory.appendingPathComponent("flavors", isDirectory: true)
    }

    init() {
        migrateFromBufferIfNeeded()
        ensureDirectoriesExist()
        loadHistory()
        loadFolders()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLimitChanged),
            name: .bufferHistoryLimitChanged,
            object: nil
        )
    }

    /// One-time, copy-only migration of history from the old "Buffer" app's data
    /// directory into the new "Klip" one. Never touches or deletes the originals.
    /// Skipped entirely when KLIP_DATA_DIR is set (test/dev runs should not inherit
    /// the user's real history).
    private func migrateFromBufferIfNeeded() {
        guard ProcessInfo.processInfo.environment["KLIP_DATA_DIR"] == nil else { return }

        let root = storageDirectory
        let historyDest = root.appendingPathComponent("history.json")
        guard !fileManager.fileExists(atPath: historyDest.path) else { return }

        let bufferRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Buffer", isDirectory: true)
        let bufferHistory = bufferRoot.appendingPathComponent("history.json")
        guard fileManager.fileExists(atPath: bufferHistory.path) else { return }

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.copyItem(at: bufferHistory, to: historyDest)

            let bufferImages = bufferRoot.appendingPathComponent("images", isDirectory: true)
            let imagesDest = root.appendingPathComponent("images", isDirectory: true)
            if fileManager.fileExists(atPath: bufferImages.path) && !fileManager.fileExists(atPath: imagesDest.path) {
                try fileManager.copyItem(at: bufferImages, to: imagesDest)
            }

            let bufferTexts = bufferRoot.appendingPathComponent("texts", isDirectory: true)
            let textsDest = root.appendingPathComponent("texts", isDirectory: true)
            if fileManager.fileExists(atPath: bufferTexts.path) && !fileManager.fileExists(atPath: textsDest.path) {
                try fileManager.copyItem(at: bufferTexts, to: textsDest)
            }

            print("[Buffer] Migrated history from ~/Library/Application Support/Buffer (copy only, originals untouched)")
        } catch {
            print("[Buffer] Migration from Buffer data directory failed, continuing with an empty store: \(error)")
        }
    }

    @objc private func handleLimitChanged() {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let limit = self.maxItems else { return }
            var trimmed = self.items
            // Same rule as performAdd: the cap counts non-protected items only.
            // Locked, pinned, bookmarked, tagged and foldered items are never
            // evicted and never count toward the limit.
            var unprotectedCount = trimmed.reduce(0) { $0 + ($1.isProtected ? 0 : 1) }
            guard unprotectedCount > limit else { return }
            while unprotectedCount > limit,
                  let idx = trimmed.lastIndex(where: { !$0.isProtected }) {
                self.deleteAssociatedFiles(for: trimmed[idx])
                trimmed.remove(at: idx)
                unprotectedCount -= 1
            }
            self.items = trimmed
            self.scheduleSave()
        }
    }

    // MARK: - Public API

    func add(_ item: ClipboardItem) {
        // Must be called on main thread for SwiftUI updates
        if Thread.isMainThread {
            performAdd(item)
        } else {
            DispatchQueue.main.sync {
                performAdd(item)
            }
        }
    }

    private func performAdd(_ item: ClipboardItem) {
        print("[Buffer] Store: Adding item, current count: \(items.count)")

        // Insert at beginning (newest first)
        items.insert(item, at: 0)

        // The history limit caps **non-protected** items only. Protected items
        // (pinned, bookmarked, tagged, locked, foldered) are never evicted and
        // do not count toward the cap, so the total may exceed the limit by the
        // number of protected items. The clip that was just copied is therefore
        // always kept: an add can only ever push out an *older* non-protected item.
        if let limit = maxItems {
            var unprotectedCount = items.reduce(0) { $0 + ($1.isProtected ? 0 : 1) }
            while unprotectedCount > limit,
                  let indexToRemove = items.lastIndex(where: { !$0.isProtected }) {
                let removed = items.remove(at: indexToRemove)
                deleteAssociatedFiles(for: removed)
                unprotectedCount -= 1
            }
        }

        print("[Buffer] Store: New count: \(items.count)")

        scheduleSave()
    }

    /// Delete a single item. Returns `false` (and changes nothing) when the
    /// item is locked.
    @discardableResult
    func delete(_ item: ClipboardItem) -> Bool {
        var didDelete = false
        performOnMainSync { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            guard !self.items[index].isLocked else { return }
            let removed = self.items.remove(at: index)
            self.deleteAssociatedFiles(for: removed)
            didDelete = true
            self.scheduleSave()
        }
        return didDelete
    }

    struct DeleteResult: Equatable {
        let deleted: Int
        let skippedLocked: Int
    }

    /// Delete multiple items in a single batch operation. Locked items are
    /// skipped and reported in `skippedLocked`.
    @discardableResult
    func delete(_ itemsToDelete: [ClipboardItem]) -> DeleteResult {
        var result = DeleteResult(deleted: 0, skippedLocked: 0)
        performOnMainSync { [weak self] in
            guard let self = self else { return }
            let requested = Set(itemsToDelete.map { $0.id })
            let removable = self.items.filter { requested.contains($0.id) && !$0.isLocked }
            let skipped = self.items.filter { requested.contains($0.id) && $0.isLocked }.count

            let removableIDs = Set(removable.map { $0.id })
            self.items.removeAll { removableIDs.contains($0.id) }
            for item in removable {
                self.deleteAssociatedFiles(for: item)
            }

            result = DeleteResult(deleted: removable.count, skippedLocked: skipped)
            self.scheduleSave()
        }
        return result
    }

    /// Toggle pin state for an item
    func togglePin(for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].isPinned.toggle()
            self.scheduleSave()
        }
    }

    /// Toggle bookmark state for an item (protected from eviction, stays in place)
    func toggleBookmark(for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].isBookmarked.toggle()
            self.scheduleSave()
        }
    }

    // MARK: - Lock

    /// Toggle lock state. A locked item can never be deleted or evicted.
    func toggleLock(_ item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].isLocked.toggle()
            self.scheduleSave()
        }
    }

    /// Set the lock state on a batch of items.
    func setLocked(ids: Set<UUID>, locked: Bool) {
        guard !ids.isEmpty else { return }
        runOnMain { [weak self] in
            guard let self = self else { return }
            var changed = false
            for index in self.items.indices where ids.contains(self.items[index].id) {
                if self.items[index].isLocked != locked {
                    self.items[index].isLocked = locked
                    changed = true
                }
            }
            guard changed else { return }
            self.scheduleSave()
        }
    }

    /// Update text content for an editable text item
    func updateText(_ text: String, for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].textContent = text
            self.scheduleSave()
        }
    }

    var allTags: [String] {
        Array(Set(items.flatMap { $0.tags })).sorted()
    }

    func addTag(_ tag: String, to item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            guard !self.items[index].tags.contains(tag) else { return }
            self.items[index].tags.append(tag)
            self.scheduleSave()
        }
    }

    func removeTag(_ tag: String, from item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].tags.removeAll { $0 == tag }
            self.scheduleSave()
        }
    }

    /// Save extracted OCR text for an image item
    func setOCRText(_ text: String, for item: ClipboardItem) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index].ocrText = text
            self.scheduleSave()
        }
    }

    /// Clear the history.
    ///
    /// With `keepProtected` (the default) everything protected survives:
    /// pinned, bookmarked, tagged, locked and foldered items. With
    /// `keepProtected: false` everything except **locked** items is deleted —
    /// a lock is absolute and outranks an explicit clear.
    @discardableResult
    func clear(keepProtected: Bool = true) -> DeleteResult {
        var result = DeleteResult(deleted: 0, skippedLocked: 0)
        performOnMainSync { [weak self] in
            guard let self = self else { return }
            let shouldDelete: (ClipboardItem) -> Bool = keepProtected
                ? { !$0.isProtected }
                : { !$0.isLocked }

            let doomed = self.items.filter(shouldDelete)
            let skipped = self.items.filter { $0.isLocked }.count
            for item in doomed {
                self.deleteAssociatedFiles(for: item)
            }
            self.items.removeAll(where: shouldDelete)

            result = DeleteResult(deleted: doomed.count, skippedLocked: skipped)
            self.scheduleSave()
        }
        return result
    }

    // MARK: - Folders

    /// Create a folder. An empty/whitespace name becomes "Untitled Folder";
    /// duplicate names are allowed.
    @discardableResult
    func createFolder(name: String) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Folder" : trimmed
        var folder = Folder(name: finalName, sortIndex: 0)

        performOnMainSync { [weak self] in
            guard let self = self else { return }
            let nextIndex = (self.folders.map { $0.sortIndex }.max() ?? -1) + 1
            folder.sortIndex = nextIndex
            self.folders.append(folder)
            self.sortFolders()
            self.saveFolders()
        }
        return folder
    }

    func renameFolder(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Folder" : trimmed
        runOnMain { [weak self] in
            guard let self = self else { return }
            guard let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
            self.folders[index].name = finalName
            self.saveFolders()
        }
    }

    enum FolderDeleteMode {
        /// Keep the items, drop their folder membership.
        case moveItemsOut
        /// Delete the items too. With `includeLocked: false` locked items are
        /// left behind and the folder itself survives.
        case deleteItems(includeLocked: Bool)
    }

    struct FolderDeleteResult: Equatable {
        let folderDeleted: Bool
        let movedOut: Int
        let deleted: Int
        let skippedLocked: Int
    }

    @discardableResult
    func deleteFolder(id: UUID, mode: FolderDeleteMode) -> FolderDeleteResult {
        var result = FolderDeleteResult(folderDeleted: false, movedOut: 0, deleted: 0, skippedLocked: 0)
        performOnMainSync { [weak self] in
            guard let self = self else { return }
            guard self.folders.contains(where: { $0.id == id }) else { return }

            switch mode {
            case .moveItemsOut:
                var movedOut = 0
                for index in self.items.indices where self.items[index].folderID == id {
                    self.items[index].folderID = nil
                    movedOut += 1
                }
                self.folders.removeAll { $0.id == id }
                result = FolderDeleteResult(folderDeleted: true, movedOut: movedOut, deleted: 0, skippedLocked: 0)

            case .deleteItems(let includeLocked):
                let inFolder = self.items.filter { $0.folderID == id }
                let lockedCount = inFolder.filter { $0.isLocked }.count
                let doomed = includeLocked ? inFolder : inFolder.filter { !$0.isLocked }

                for item in doomed {
                    self.deleteAssociatedFiles(for: item)
                }
                let doomedIDs = Set(doomed.map { $0.id })
                self.items.removeAll { doomedIDs.contains($0.id) }

                // Locked items left behind keep the folder alive; the UI asks
                // for explicit confirmation and calls again with includeLocked.
                let removeFolder = includeLocked || lockedCount == 0
                if removeFolder {
                    self.folders.removeAll { $0.id == id }
                }
                result = FolderDeleteResult(
                    folderDeleted: removeFolder,
                    movedOut: 0,
                    deleted: doomed.count,
                    skippedLocked: includeLocked ? 0 : lockedCount
                )
            }

            self.saveFolders()
            self.scheduleSave()
        }
        return result
    }

    /// Move items into a folder (`folderID != nil`) or back out (`nil`).
    /// Filing an item into a folder also locks it — folder clips are locked by
    /// default. Moving out leaves the lock state untouched.
    func moveItems(ids: Set<UUID>, toFolder folderID: UUID?) {
        guard !ids.isEmpty else { return }
        runOnMain { [weak self] in
            guard let self = self else { return }
            if let folderID = folderID, !self.folders.contains(where: { $0.id == folderID }) { return }
            var changed = false
            for index in self.items.indices where ids.contains(self.items[index].id) {
                self.items[index].folderID = folderID
                if folderID != nil {
                    self.items[index].isLocked = true
                }
                changed = true
            }
            guard changed else { return }
            self.scheduleSave()
        }
    }

    func items(inFolder id: UUID) -> [ClipboardItem] {
        items.filter { $0.folderID == id }
    }

    func folderCounts() -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for item in items {
            guard let folderID = item.folderID else { continue }
            counts[folderID, default: 0] += 1
        }
        return counts
    }

    /// Reorder folders to match `ids`. Ids not present are ignored; folders
    /// missing from `ids` keep their relative order at the end.
    func reorderFolders(_ ids: [UUID]) {
        runOnMain { [weak self] in
            guard let self = self else { return }
            var rank: [UUID: Int] = [:]
            for (offset, id) in ids.enumerated() { rank[id] = offset }
            let tailBase = ids.count

            let ordered = self.folders.enumerated().sorted { lhs, rhs in
                let l = rank[lhs.element.id] ?? (tailBase + lhs.offset)
                let r = rank[rhs.element.id] ?? (tailBase + rhs.offset)
                return l < r
            }.map { $0.element }

            self.folders = ordered.enumerated().map { offset, folder in
                var copy = folder
                copy.sortIndex = offset
                return copy
            }
            self.saveFolders()
        }
    }

    // MARK: - Assets

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.type == .image, let filename = item.imageFilename else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return NSImage(contentsOf: url)
    }

    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let url = imagesDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            print("[Buffer] Failed to save image: \(error)")
            return nil
        }
    }

    /// Save large text to a file and return the filename
    func saveText(_ text: String) -> String? {
        let filename = UUID().uuidString + ".txt"
        let url = textsDirectory.appendingPathComponent(filename)

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return filename
        } catch {
            print("[Buffer] Failed to save text file: \(error)")
            return nil
        }
    }

    /// Load full text content from file (lazy loading for large text)
    func fullText(for item: ClipboardItem) -> String? {
        guard let filename = item.textFilename else { return item.textContent }
        let url = textsDirectory.appendingPathComponent(filename)

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            print("[Buffer] Failed to load text file: \(error)")
            return item.textContent // Fallback to inline preview
        }
    }

    /// Load a chunk of text content, reading only what's necessary
    func textChunk(for item: ClipboardItem, charCount: Int) -> (text: String, totalBytes: Int, reachedEOF: Bool)? {
        if let filename = item.textFilename {
            // File-backed large text
            let url = textsDirectory.appendingPathComponent(filename)

            do {
                // Get total size from attributes without reading file
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let totalBytes = attributes[.size] as? Int ?? 0

                // Read a chunk that should contain enough characters
                // UTF-8 can be up to 4 bytes per character, so we read charCount * 4
                // to guarantee we have enough bytes for the requested characters
                let maximumBytesToRead = min(charCount * 4, totalBytes)

                let fileHandle = try FileHandle(forReadingFrom: url)
                defer { try? fileHandle.close() }

                let data = try fileHandle.read(upToCount: maximumBytesToRead) ?? Data()

                // Decode to string and take exact requested characters
                let fullChunkStr = String(decoding: data, as: UTF8.self)
                let exactChunkStr = String(fullChunkStr.prefix(charCount))

                // If the decoded string length is less than requested, we hit EOF
                let reachedEOF = fullChunkStr.count < charCount

                return (exactChunkStr, totalBytes, reachedEOF)

            } catch {
                print("[Buffer] Failed to read text chunk: \(error)")
                return nil
            }
        } else {
            // Inline text
            let content = item.textContent ?? ""
            let totalBytes = content.utf8.count

            let prefix = String(content.prefix(charCount))
            let reachedEOF = content.count <= charCount

            return (prefix, totalBytes, reachedEOF)
        }
    }

    /// Get the total size of an item (in bytes) for UI display
    func itemSize(for item: ClipboardItem) -> Int? {
        if let attachment = item.fileAttachment {
            return Int(attachment.byteSize)
        }

        switch item.type {
        case .text:
            if let filename = item.textFilename {
                let url = textsDirectory.appendingPathComponent(filename)
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.size] as? Int
            } else {
                return item.textContent?.utf8.count
            }
        case .image:
            if let filename = item.imageFilename {
                let url = imagesDirectory.appendingPathComponent(filename)
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                return attributes?[.size] as? Int
            }
        }
        return nil
    }

    // MARK: - Saving

    /// Schedule a debounced write of the current items. Safe to call from the
    /// main thread after any mutation.
    private func scheduleSave() {
        let snapshot = items
        saveQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingItems = snapshot
            self.pendingSaveWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.pendingSaveWorkItem = nil
                guard let toSave = self.pendingItems else { return }
                self.pendingItems = nil
                self.saveHistoryToDisk(toSave)
            }
            self.pendingSaveWorkItem = work
            self.saveQueue.asyncAfter(deadline: .now() + Self.saveDebounceInterval, execute: work)
        }
    }

    /// Write any debounced history immediately and wait for it to land.
    /// Called from `applicationWillTerminate` and by tests before reading files.
    func flushPendingSave() {
        saveQueue.sync {
            self.pendingSaveWorkItem?.cancel()
            self.pendingSaveWorkItem = nil
            guard let toSave = self.pendingItems else { return }
            self.pendingItems = nil
            self.saveHistoryToDisk(toSave)
        }
    }

    // MARK: - Private

    /// Runs `action` on the main thread and waits for it, so `@discardableResult`
    /// return values are meaningful for callers already on main.
    private func performOnMainSync(_ action: () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.sync(execute: action)
        }
    }

    private func sortFolders() {
        folders.sort { lhs, rhs in
            lhs.sortIndex == rhs.sortIndex ? lhs.createdAt < rhs.createdAt : lhs.sortIndex < rhs.sortIndex
        }
    }

    private func ensureDirectoriesExist() {
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: textsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: flavorsDirectory, withIntermediateDirectories: true)
    }

    /// Rename a file that failed to decode so it is preserved for inspection
    /// instead of being silently overwritten by the next save.
    private func quarantine(_ url: URL, prefix: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        var destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(prefix).corrupt-\(stamp).json")

        // Collision within the same second — very unlikely, still cheap to handle.
        var suffix = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = url.deletingLastPathComponent()
                .appendingPathComponent("\(prefix).corrupt-\(stamp)-\(suffix).json")
            suffix += 1
        }

        do {
            try fileManager.moveItem(at: url, to: destination)
            print("[Buffer] Quarantined undecodable \(url.lastPathComponent) as \(destination.lastPathComponent)")
        } catch {
            print("[Buffer] Failed to quarantine \(url.lastPathComponent): \(error)")
        }
    }

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            print("[Buffer] No history file found")
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: historyFileURL)
        } catch {
            print("[Buffer] Failed to read history: \(error)")
            return
        }

        let decoder = JSONDecoder()

        // v2: { "version": 2, "items": [...] }
        if let file = try? decoder.decode(HistoryFile.self, from: data) {
            self.items = file.items
            print("[Buffer] Loaded \(file.items.count) items from history (v\(file.version))")
            return
        }

        // v1: a bare array. Re-saved in the v2 wrapper on the next write.
        if let legacy = try? decoder.decode([ClipboardItem].self, from: data) {
            self.items = legacy
            print("[Buffer] Loaded \(legacy.count) items from a v1 history file, upgrading to v2")
            scheduleSave()
            return
        }

        print("[Buffer] Failed to decode history; starting empty")
        quarantine(historyFileURL, prefix: "history")
    }

    private func saveHistoryToDisk(_ itemsToSave: [ClipboardItem]) {
        do {
            let file = HistoryFile(version: Self.historySchemaVersion, items: itemsToSave)
            let data = try JSONEncoder().encode(file)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("[Buffer] Failed to save history: \(error)")
        }
    }

    private func loadFolders() {
        guard fileManager.fileExists(atPath: foldersFileURL.path) else {
            // Seed the versioned wrapper so the storage layout is complete and
            // self-describing from the first launch.
            saveFolders()
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: foldersFileURL)
        } catch {
            print("[Buffer] Failed to read folders: \(error)")
            return
        }

        let decoder = JSONDecoder()
        if let file = try? decoder.decode(FoldersFile.self, from: data) {
            self.folders = file.folders
            sortFolders()
            print("[Buffer] Loaded \(file.folders.count) folders (v\(file.version))")
            return
        }
        if let bare = try? decoder.decode([Folder].self, from: data) {
            self.folders = bare
            sortFolders()
            saveFolders()
            return
        }

        print("[Buffer] Failed to decode folders; starting with none")
        quarantine(foldersFileURL, prefix: "folders")
    }

    /// Folders are tiny and mutated rarely, so they are written straight
    /// through (atomically) rather than debounced.
    private func saveFolders() {
        let snapshot = folders
        saveQueue.sync {
            do {
                let file = FoldersFile(version: Self.foldersSchemaVersion, folders: snapshot)
                let data = try JSONEncoder().encode(file)
                try data.write(to: self.foldersFileURL, options: .atomic)
            } catch {
                print("[Buffer] Failed to save folders: \(error)")
            }
        }
    }

    private func deleteImageFile(for item: ClipboardItem) {
        guard item.type == .image, let filename = item.imageFilename else { return }
        let url = imagesDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    private func deleteTextFile(for item: ClipboardItem) {
        guard let filename = item.textFilename else { return }
        let url = textsDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: url)
    }

    /// Delete every on-disk asset belonging to an item: image, text file,
    /// copied file payload (`files/<uuid>/`), archived flavors
    /// (`flavors/<uuid>.plist`) and the RTF flavor (`texts/<uuid>.rtf`).
    private func deleteAssociatedFiles(for item: ClipboardItem) {
        deleteImageFile(for: item)
        deleteTextFile(for: item)

        let itemFiles = filesDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: itemFiles.path) {
            try? fileManager.removeItem(at: itemFiles)
        }

        let flavors = item.flavorsFilename ?? "\(item.id.uuidString).plist"
        let flavorsURL = flavorsDirectory.appendingPathComponent(flavors)
        if fileManager.fileExists(atPath: flavorsURL.path) {
            try? fileManager.removeItem(at: flavorsURL)
        }

        let rtf = item.rtfFilename ?? "\(item.id.uuidString).rtf"
        let rtfURL = textsDirectory.appendingPathComponent(rtf)
        if fileManager.fileExists(atPath: rtfURL.path) {
            try? fileManager.removeItem(at: rtfURL)
        }
    }
}
