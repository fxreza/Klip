import Cocoa

/// Custom panel that closes when clicking outside
class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onClickOutside?()
    }
}
