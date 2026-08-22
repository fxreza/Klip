import AppKit
import SwiftUI

/// Drag-and-drop plumbing for filing clips into folders (Phase 3B).
///
/// SwiftUI's `.onDrag` cannot be used on a clip row: the row's mouse events are
/// owned by the `ClickModifierDetector` overlay (it is what makes ⌘/⇧-click
/// visible to the view model), and an `.onDrag` modifier under that overlay
/// never sees a mouse-down. So the drag is started by AppKit from the overlay
/// itself (`ClickModifierDetector.ClickView.mouseDragged`) and the sidebar rows
/// are AppKit drop targets (`SidebarDropTarget`).
///
/// The payload is a private pasteboard type carrying newline-separated UUID
/// strings, so a drag that escapes the app is inert rather than pasting
/// something surprising into another application.
enum ClipDragPayload {
    /// Clip ids being dragged out of the list.
    static let clipsType = NSPasteboard.PasteboardType("com.fxreza.klip.clipids")
    /// A folder id being dragged inside the sidebar (reordering).
    static let folderType = NSPasteboard.PasteboardType("com.fxreza.klip.folderid")

    // MARK: - Encoding

    /// `[uuid, uuid, …]` → `"uuid\nuuid\n…"`.
    static func encode(_ ids: [UUID]) -> String {
        ids.map { $0.uuidString }.joined(separator: "\n")
    }

    /// Inverse of `encode`. Unparseable lines are dropped, duplicates are
    /// collapsed and the original order is preserved.
    ///
    /// Splitting goes through `CharacterSet.newlines` on purpose: `"\r\n"` is a
    /// *single* Swift `Character`, so comparing characters against `"\n"` would
    /// silently glue two lines together.
    static func decode(_ string: String) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for line in string.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let id = UUID(uuidString: trimmed), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        return result
    }

    static func pasteboardItem(ids: [UUID]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(encode(ids), forType: clipsType)
        return item
    }

    static func pasteboardItem(folderID: UUID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(folderID.uuidString, forType: folderType)
        return item
    }

    // MARK: - Reading

    static func ids(from pasteboard: NSPasteboard) -> [UUID] {
        guard let string = pasteboard.string(forType: clipsType) else { return [] }
        return decode(string)
    }

    static func folderID(from pasteboard: NSPasteboard) -> UUID? {
        guard let string = pasteboard.string(forType: folderType) else { return nil }
        return UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// What `ClickModifierDetector` should put on the dragging pasteboard, captured
/// at mouse-down time (before the click handler mutates the selection) so the
/// click semantics are untouched.
struct ClipDragRequest {
    let ids: [UUID]
    let image: NSImage
}

// MARK: - Sidebar drop target / folder drag source

/// Invisible AppKit layer placed in the **background** of a sidebar row.
///
/// It is deliberately *not* an overlay: `mouseDown` is forwarded to the next
/// responder so the row's SwiftUI tap gestures (select scope, double-click to
/// rename) and its `.contextMenu` keep working exactly as they do without it.
/// The view exists only so AppKit has something registered for dragged types
/// under the mouse, plus — for folder rows — a place to start a reorder drag.
struct SidebarDropTarget: NSViewRepresentable {
    /// Accept dragged clip ids (All + folder rows; Favorites does not).
    var acceptsClips: Bool = false
    /// Non-nil on a folder row: makes this row a reorder drag source and lets it
    /// accept another folder being dropped on it.
    var folderID: UUID? = nil
    /// Title used for the reorder drag image.
    var folderName: String = ""
    /// Return true if the drop was consumed.
    var onDropClips: ([UUID]) -> Bool = { _ in false }
    /// Reorder: the dragged folder id was dropped on this row.
    var onDropFolder: (UUID) -> Bool = { _ in false }
    /// Highlight feedback for the SwiftUI row.
    var onTargetChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        apply(to: view)
        view.refreshRegistration()
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        apply(to: nsView)
        nsView.refreshRegistration()
    }

    private func apply(to view: DropView) {
        view.acceptsClips = acceptsClips
        view.folderID = folderID
        view.folderName = folderName
        view.onDropClips = onDropClips
        view.onDropFolder = onDropFolder
        view.onTargetChanged = onTargetChanged
    }

    final class DropView: NSView, NSDraggingSource {
        var acceptsClips = false
        var folderID: UUID?
        var folderName: String = ""
        var onDropClips: (([UUID]) -> Bool)?
        var onDropFolder: ((UUID) -> Bool)?
        var onTargetChanged: ((Bool) -> Void)?

        private var registeredClips = false
        private var registeredFolders = false
        private var isTargeted = false {
            didSet {
                guard isTargeted != oldValue else { return }
                onTargetChanged?(isTargeted)
            }
        }

        private var mouseDownPoint: CGPoint?
        private var isDraggingFolder = false

        /// Register only for what this row can actually take, so AppKit shows
        /// the "no drop" cursor over rows that would reject the drag anyway.
        func refreshRegistration() {
            let wantsClips = acceptsClips
            let wantsFolders = folderID != nil
            guard wantsClips != registeredClips || wantsFolders != registeredFolders else { return }
            registeredClips = wantsClips
            registeredFolders = wantsFolders
            var types: [NSPasteboard.PasteboardType] = []
            if wantsClips { types.append(ClipDragPayload.clipsType) }
            if wantsFolders { types.append(ClipDragPayload.folderType) }
            unregisterDraggedTypes()
            if !types.isEmpty { registerForDraggedTypes(types) }
        }

        // MARK: Mouse — forwarded, never consumed

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            isDraggingFolder = false
            // Forward: the SwiftUI row above owns click/double-click/right-click.
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isDraggingFolder,
                  let folderID = folderID,
                  let origin = mouseDownPoint,
                  window != nil else {
                super.mouseDragged(with: event)
                return
            }
            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - origin.x, point.y - origin.y) > 4 else {
                super.mouseDragged(with: event)
                return
            }
            isDraggingFolder = true

            let image = ClipRowDragImage.make(title: folderName, count: 1, symbolName: "folder.fill")
            let item = NSDraggingItem(pasteboardWriter: ClipDragPayload.pasteboardItem(folderID: folderID))
            item.setDraggingFrame(
                NSRect(
                    x: point.x - image.size.width / 2,
                    y: point.y - image.size.height / 2,
                    width: image.size.width,
                    height: image.size.height
                ),
                contents: image
            )
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownPoint = nil
            super.mouseUp(with: event)
        }

        // MARK: NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            isDraggingFolder = false
            mouseDownPoint = nil
        }

        // MARK: NSDraggingDestination

        /// What, if anything, this row would do with the drag currently over it.
        private func operation(for info: NSDraggingInfo) -> NSDragOperation {
            let pasteboard = info.draggingPasteboard
            if acceptsClips, !ClipDragPayload.ids(from: pasteboard).isEmpty {
                return .move
            }
            if let dragged = ClipDragPayload.folderID(from: pasteboard),
               let folderID = folderID, dragged != folderID {
                return .move
            }
            return []
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let op = operation(for: sender)
            isTargeted = op != []
            return op
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let op = operation(for: sender)
            isTargeted = op != []
            return op
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            isTargeted = false
        }

        override func draggingEnded(_ sender: NSDraggingInfo) {
            isTargeted = false
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            operation(for: sender) != []
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { isTargeted = false }
            let pasteboard = sender.draggingPasteboard

            let ids = ClipDragPayload.ids(from: pasteboard)
            if acceptsClips, !ids.isEmpty {
                return onDropClips?(ids) ?? false
            }
            if let dragged = ClipDragPayload.folderID(from: pasteboard),
               let folderID = folderID, dragged != folderID {
                return onDropFolder?(dragged) ?? false
            }
            return false
        }
    }
}
