import Cocoa
import SwiftUI

/// Manages the floating history window
class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    /// Owns the window's state so it survives SwiftUI view identity resets.
    let viewModel: HistoryViewModel
    var previousApp: NSRunningApplication?

    /// Timestamp of the last close — used to decide whether to persist search state
    private var lastClosedAt: Date?

    /// Shared flag: true if the content view should reset search on the next open
    var shouldResetOnOpen: Bool {
        get { viewModel.shouldResetOnOpen }
        set { viewModel.shouldResetOnOpen = newValue }
    }

    /// Last selected item UUID — restored when reopening within the threshold
    var savedSelectedID: UUID? {
        get { viewModel.savedSelectedID }
        set { viewModel.savedSelectedID = newValue }
    }

    /// Reset search if window was closed more than 1.5 minutes ago (or never opened)
    private var shouldResetSearch: Bool {
        guard let lastClosed = lastClosedAt else { return true }
        return Date().timeIntervalSince(lastClosed) > 90
    }

    init(store: ClipboardStore) {
        self.store = store
        self.viewModel = HistoryViewModel(store: store)

        // Wider window for split pane
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        panel.onClickOutside = { [weak self] in
            self?.close()
        }

        setupPanel(panel)
        setupContent()
    }

    override func close() {
        lastClosedAt = Date()
        super.close()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPanel(_ panel: NSPanel) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true

        panel.center()

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // Notify content view when window becomes key so it can reset state
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: .bufferWindowDidOpen, object: nil)
        }
    }

    private func setupContent() {
        viewModel.onCopyToClipboard = { [weak self] item in
            self?.copyToClipboard(item)
        }
        viewModel.onPaste = { [weak self] item in
            self?.pasteItem(item)
        }
        viewModel.onPasteMultiple = { [weak self] items in
            self?.pasteMultiple(items)
        }
        viewModel.onDismiss = { [weak self] in
            self?.close()
        }

        let contentView = HistoryContentView(store: store, viewModel: viewModel)
        window?.contentView = NSHostingView(rootView: contentView)
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.copyToClipboard(item, store: store)
    }

    func pasteItem(_ item: ClipboardItem) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(item, store: store, previousApp: appToRestore)
    }

    func pasteMultiple(_ items: [ClipboardItem]) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.pasteMultiple(items, store: store, previousApp: appToRestore)
    }

    override func showWindow(_ sender: Any?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Compute reset decision *before* super.showWindow fires didBecomeKeyNotification
        // → bufferWindowDidOpen, so the content view onReceive handler sees the right value.
        shouldResetOnOpen = shouldResetSearch
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }
}
