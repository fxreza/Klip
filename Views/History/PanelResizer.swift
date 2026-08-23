// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) — UI/Overlay/PanelResizer.swift

import SwiftUI
import AppKit

/// A thin draggable divider that resizes an adjacent fixed-width panel.
///
/// `side: .leading` means the panel being resized is to the divider's left
/// (the sidebar — dragging right widens it). `.trailing` means the panel is to
/// the right (the preview — dragging left widens it).
struct PanelResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    var side: HorizontalEdge = .leading

    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            // Hit area is wider than the visible hairline below (12pt vs 1pt).
            // `.overlay` centers its content by default, so the 1pt line stays
            // centered in the 12pt strip without any extra alignment work.
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .overlay(
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                // Was `NSCursor.resizeLeftRight.push()` / `.pop()`. push/pop
                // maintains a stack, and SwiftUI can fire a spurious
                // `onHover(false)` during a view update with no matching
                // `true` before it (measured happening a lot over the image
                // preview, whose body re-lays-out on nearly every frame while
                // an image clip is selected). Each stray `false` popped the
                // stack without a matching push, so the resize cursor
                // silently stopped being applied over this divider — it
                // looked like the strip couldn't be grabbed, when actually
                // the geometry was fine and only the cursor feedback was
                // gone. `.set()` has no stack to unbalance: every call is
                // independent, so extra or out-of-order callbacks are
                // harmless.
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let translation = Double(value.translation.width)
                        let delta = side == .leading ? translation : -translation
                        // `translation` is continuous, so without `.rounded()`
                        // the pane lands on a fractional point boundary on every
                        // gesture event (574.4786993982766, not 574). Whole
                        // points are what AppKit hands SwiftUI during an edge
                        // resize, so this just makes the divider behave the same
                        // way.
                        //
                        // NOTE: this was first written to fix the ghosting/
                        // flicker seen while dragging a divider. It does not —
                        // that bug survives whole-point widths and is still
                        // open. Kept because whole points are correct anyway and
                        // because of the write reduction below; do not cite it
                        // as the flicker fix.
                        //
                        // It also cuts persistence churn by ~two orders of
                        // magnitude: `SettingsManager.sidebarWidth`/`previewWidth`
                        // write to UserDefaults from `didSet`, which used to fire
                        // on every event of every drag and now fires only when a
                        // whole point is crossed.
                        width = min(max(start + delta, range.lowerBound), range.upperBound)
                            .rounded()
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
