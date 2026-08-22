import Foundation
import AppKit

// Regressions from `docs/plan/review-5A.md` that live under `Views/`:
// 5A-07 / 5A-10 (thumbnail rendering + cache), 5A-14 (the pinned-first
// invariant the list's new separator logic relies on), 5A-22 (a stale
// selection index), 5A-30 (selection-wide menu labels) and review-2B's
// Clear History wording.
enum ViewRegressionTests {
    static let tests: [(String, () throws -> Void)] = [
        ("thumbnail_rendersOffTheMainThreadWithoutLockFocus", testThumbnailRendersOffMain),
        ("thumbnail_isCachedPerItemAndSizeAndEvictedOnDelete", testThumbnailCache),
        ("filteredItems_pinnedRunIsAContiguousPrefix", testPinnedPrefixInvariant),
        ("staleSelectionIndex_isClampedAndExtendSelectionIsSafe", testStaleSelectionIndex),
        ("rowMenuLabels_nameTheSelectionWideEntries", testRowMenuLabels),
        ("clearHistoryMessage_saysProtectedOrLocked", testClearHistoryMessage),
    ]

    // MARK: - Helpers

    /// A tiny solid-colour PNG.
    private static func pngData(width: Int = 64, height: Int = 64) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw TestFailure(message: "could not make a bitmap", file: #file, line: #line) }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw TestFailure(message: "could not encode PNG", file: #file, line: #line)
        }
        return data
    }

    /// Runs the main run loop until `condition` holds or `timeout` elapses.
    @discardableResult
    private static func pump(timeout: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    // MARK: - 5A-07: no `lockFocus` off the main thread

    /// `NSImage.lockFocus` is main-thread-only; the renderer now draws into
    /// an `NSBitmapImageRep` through an explicit context, which is safe from
    /// any thread. This drives it from a background queue, which is exactly
    /// how `ClipRow` uses it.
    static func testThumbnailRendersOffMain() throws {
        let source = NSImage(data: try pngData())
        try expectNotNil(source, "precondition: the fixture image decodes")

        var rendered: NSImage?
        var finished = false
        DispatchQueue.global(qos: .userInitiated).async {
            rendered = ImageThumbnailCache.render(source!, size: NSSize(width: 76, height: 76))
            finished = true
        }
        try expect(pump { finished }, "the background render should complete")

        let thumb = try require(rendered, "an off-main render must produce an image")
        try expectEqual(thumb.size, NSSize(width: 76, height: 76), "the thumbnail is the requested size")
        try expect(!thumb.representations.isEmpty, "the thumbnail carries a real bitmap representation")
    }

    // MARK: - 5A-10: thumbnails are cached, and dropped on delete

    static func testThumbnailCache() throws {
        try ClipboardStoreTests.withStore { store, _ in
            let filename = try require(store.saveImage(try pngData()), "the fixture image should save")
            var item = ClipboardItem.image(filename: filename)
            item.kind = .image
            store.add(item)

            func thumbnail(size: CGFloat = 38) throws -> NSImage {
                var result: NSImage??
                Task { result = await ImageThumbnailCache.thumbnail(for: item, store: store, size: size) }
                try expect(pump { result != nil }, "the thumbnail request should finish")
                return try require(result ?? nil, "the thumbnail should render")
            }

            let first = try thumbnail()
            let second = try thumbnail()
            try expect(first === second, "a second request for the same item and size is a cache hit")

            let bigger = try thumbnail(size: 240)
            try expect(bigger !== first, "a different size is a different cache entry")

            ImageThumbnailCache.evict(itemIDs: [item.id])
            let afterEvict = try thumbnail()
            try expect(afterEvict !== first, "eviction drops the cached copy")
        }
    }

    // MARK: - 5A-14: the invariant the list's separator logic relies on

    /// `ClipList` no longer materialises `Array(items.enumerated())`; it
    /// counts the pinned prefix instead. That is only equivalent because
    /// `FilterState.apply` partitions pinned items to the front as a
    /// contiguous run — pinned here, so the list cannot silently start
    /// drawing separators in the wrong place.
    static func testPinnedPrefixInvariant() throws {
        var items: [ClipboardItem] = []
        for i in 0..<40 {
            items.append(ClipboardItem(type: .text, textContent: "item \(i)", isPinned: i % 7 == 0))
        }
        let filtered = FilterState.apply(items, FilterState())
        let pinnedCount = filtered.prefix(while: { $0.isPinned }).count

        try expectEqual(pinnedCount, items.filter { $0.isPinned }.count,
                        "every pinned item is in the leading run")
        try expect(filtered.dropFirst(pinnedCount).allSatisfy { !$0.isPinned },
                   "nothing pinned appears after the run")

        // The first unpinned row — where the separator is drawn.
        try expectEqual(filtered[safe: pinnedCount]?.isPinned, false)
    }

    // MARK: - 5A-22: a stale index must not crash ⇧↑ / ⇧↓

    static func testStaleSelectionIndex() throws {
        try FolderUXTests.withViewModel { vm, store in
            FolderUXTests.seed(vm, store, ["a", "b", "c", "d", "e"])
            vm.applyFilters(resetSelection: .defaultItem)

            // The latent state the finding describes: an index left pointing
            // past the end of a now-shorter list, with no selected id to
            // re-anchor it.
            vm.selectedID = nil
            vm.selectedIDs = []
            vm.selectedIndex = 4
            store.items = Array(store.items.prefix(2))
            vm.applyFilters(resetSelection: .preserve)

            try expect(vm.selectedIndex < vm.filteredItems.count,
                       "applyFilters must clamp an out-of-range index")

            // Both of these used to index `filteredItems` directly.
            vm.keyExtendUp()
            vm.keyExtendDown()

            // And with an empty list.
            store.items = []
            vm.applyFilters(resetSelection: .preserve)
            vm.keyExtendUp()
            vm.keyExtendDown()
            try expectEqual(vm.selectedIndex, 0, "an empty list clamps to 0")
        }
    }

    // MARK: - 5A-30 / review-2B wording

    static func testRowMenuLabels() throws {
        try expectEqual(RowMenuLabels.lock(selectionCount: 1, allLocked: false), "Lock")
        try expectEqual(RowMenuLabels.lock(selectionCount: 1, allLocked: true), "Unlock")
        try expectEqual(RowMenuLabels.lock(selectionCount: 10, allLocked: false), "Lock 10 Clips",
                        "a selection-wide lock says how many clips it will lock")
        try expectEqual(RowMenuLabels.lock(selectionCount: 10, allLocked: true), "Unlock 10 Clips")
        try expectEqual(RowMenuLabels.delete(selectionCount: 1), "Delete")
        try expectEqual(RowMenuLabels.delete(selectionCount: 3), "Delete 3 Clips")
        try expectEqual(RowMenuLabels.moveToFolder(selectionCount: 1), "Move to Folder")
        try expectEqual(RowMenuLabels.moveToFolder(selectionCount: 2), "Move 2 Clips to Folder")
        try expectEqual(RowMenuLabels.saveToDisk(selectionCount: 1), "Save to Disk…")
        try expectEqual(RowMenuLabels.saveToDisk(selectionCount: 4), "Save 4 Clips to Disk…")
    }

    static func testClearHistoryMessage() throws {
        try expectEqual(
            StatusBarController.clearResultMessage(deleted: 12, kept: 0, keepProtected: true),
            "Cleared 12 clips."
        )
        try expectEqual(
            StatusBarController.clearResultMessage(deleted: 1, kept: 0, keepProtected: true),
            "Cleared 1 clip."
        )
        // Checkbox on: everything protected survives, not just locks.
        try expectEqual(
            StatusBarController.clearResultMessage(deleted: 12, kept: 3, keepProtected: true),
            "Cleared 12 clips; 3 protected clips kept."
        )
        try expectEqual(
            StatusBarController.clearResultMessage(deleted: 12, kept: 1, keepProtected: true),
            "Cleared 12 clips; 1 protected clip kept."
        )
        // Checkbox off: only locks can survive, so the wording says so.
        try expectEqual(
            StatusBarController.clearResultMessage(deleted: 12, kept: 2, keepProtected: false),
            "Cleared 12 clips; 2 locked clips kept."
        )
    }

    // MARK: - Local helper

    private static func require<T>(_ value: T?, _ message: String, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let value else { throw TestFailure(message: message, file: file, line: line) }
        return value
    }
}
