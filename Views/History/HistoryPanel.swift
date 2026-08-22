// Panel chrome adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) —
// UI/Overlay/OverlayPanel.swift.

import Cocoa

/// Borderless, resizable floating panel that closes when it loses key focus.
///
/// Borderless windows cannot become key by default, so `canBecomeKey` is
/// overridden — the search field needs to accept text.
class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    /// Activating an accessory app is asynchronous and can produce a transient
    /// resign-key right after the panel is ordered in. The controller pushes
    /// this a moment into the future on every show so that blip does not close
    /// the window we just opened. Clicking away afterwards still closes it.
    var suppressResignUntil: Date = .distantPast

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        guard Date() >= suppressResignUntil else { return }
        onClickOutside?()
    }
}
