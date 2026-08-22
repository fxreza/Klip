import SwiftUI
import AppKit

/// A simple wrapper that detects clicks with modifier keys.
///
/// Phase 3B also makes it the **drag source** for clip rows. It has to be: the
/// overlay swallows `mouseDown`, so a SwiftUI `.onDrag` placed on the row below
/// it would never start. A drag begins once the pointer has travelled more than
/// `dragThreshold` points with the button held; anything short of that is a
/// plain click and behaves exactly as it did before (select / ⌘ / ⇧, with the
/// double-click recogniser still living in `ClipList`).
struct ClickModifierDetector: NSViewRepresentable {
    let onClickWithModifiers: (NSEvent.ModifierFlags) -> Void

    /// Asked **once per mouse-down, before `onClickWithModifiers` runs**, so the
    /// payload reflects the selection as it was when the press started. Return
    /// nil to make the row undraggable.
    var dragPayload: (() -> ClipDragRequest?)? = nil

    /// Called on the main actor when a drag actually starts, with the ids being
    /// dragged. `ClipList` uses it to put the multi-selection back after the
    /// mouse-down collapsed it.
    var onDragBegan: (([UUID]) -> Void)? = nil

    /// Pointer travel, in points, that separates a click from a drag.
    static let dragThreshold: CGFloat = 4

    class ClickView: NSView, NSDraggingSource {
        var onClickWithModifiers: ((NSEvent.ModifierFlags) -> Void)?
        var dragPayload: (() -> ClipDragRequest?)?
        var onDragBegan: (([UUID]) -> Void)?

        private var mouseDownPoint: CGPoint?
        private var pendingDrag: ClipDragRequest?
        private var isDragging = false

        override func mouseDown(with event: NSEvent) {
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            isDragging = false
            // Snapshot the payload *before* the click mutates the selection, so
            // pressing on a row that is part of a multi-selection still drags
            // the whole selection even though the press collapses it.
            pendingDrag = dragPayload?()
            onClickWithModifiers?(event.modifierFlags)
        }

        override func mouseDragged(with event: NSEvent) {
            // Anything that is not a drag keeps the pre-3B behaviour of letting
            // the event travel on up the responder chain.
            guard !isDragging,
                  let origin = mouseDownPoint,
                  let request = pendingDrag,
                  !request.ids.isEmpty,
                  window != nil else {
                super.mouseDragged(with: event)
                return
            }

            let point = convert(event.locationInWindow, from: nil)
            guard hypot(point.x - origin.x, point.y - origin.y) > ClickModifierDetector.dragThreshold else {
                super.mouseDragged(with: event)
                return
            }
            isDragging = true

            let image = request.image
            let item = NSDraggingItem(pasteboardWriter: ClipDragPayload.pasteboardItem(ids: request.ids))
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
            onDragBegan?(request.ids)
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownPoint = nil
            pendingDrag = nil
            // The pre-3B view had no `mouseUp` override, so the event reached
            // the next responder. Keep it that way.
            super.mouseUp(with: event)
        }

        // MARK: NSDraggingSource

        /// In-app only: the payload is a private type, so letting it leave the
        /// app would just produce a rejected drag elsewhere.
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
            isDragging = false
            mouseDownPoint = nil
            pendingDrag = nil
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.onClickWithModifiers = onClickWithModifiers
        view.dragPayload = dragPayload
        view.onDragBegan = onDragBegan
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let clickView = nsView as? ClickView {
            clickView.onClickWithModifiers = onClickWithModifiers
            clickView.dragPayload = dragPayload
            clickView.onDragBegan = onDragBegan
        }
    }
}

// MARK: - Modifier Flags Extension
extension NSEvent.ModifierFlags {
    var hasCommand: Bool {
        self.contains(.command)
    }

    var hasShift: Bool {
        self.contains(.shift)
    }
}
