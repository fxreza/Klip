import Cocoa
import SwiftUI

/// Manages the floating history window.
///
/// Public API is unchanged (`showWindow`, `close`, `pasteItem`,
/// `pasteMultiple`, `previousApp`, `viewModel`) — `AppDelegate`,
/// `StatusBarController` and the debug hooks call it. There is deliberately no
/// `toggle()`: `AppDelegate.toggleHistoryWindow()` owns that.
class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private let store: ClipboardStore
    /// Owns the window's state so it survives SwiftUI view identity resets.
    let viewModel: HistoryViewModel
    var previousApp: NSRunningApplication?

    /// Timestamp of the last close — used to decide whether to persist search state
    private var lastClosedAt: Date?

    /// Default window size when the user has never resized it (Clipfield's
    /// "standard" overlay size).
    private static let defaultSize = NSSize(width: 880, height: 540)
    private static let minSize = NSSize(width: 560, height: 380)
    private static let maxSize = NSSize(width: 1600, height: 1100)

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

    /// Persisted content size, clamped so a stale value cannot make the window
    /// unusable.
    private var panelSize: NSSize {
        let settings = SettingsManager.shared
        guard let w = settings.windowWidth, let h = settings.windowHeight, w > 0, h > 0 else {
            return Self.defaultSize
        }
        return NSSize(
            width: min(max(w, Self.minSize.width), Self.maxSize.width),
            height: min(max(h, Self.minSize.height), Self.maxSize.height)
        )
    }

    init(store: ClipboardStore) {
        self.store = store
        self.viewModel = HistoryViewModel(store: store)

        let panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
        viewModel.isPresented = false
        super.close()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupPanel(_ panel: HistoryPanel) {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // The SwiftUI content draws its own rounded material card, so the window
        // itself is clear and its shadow tracks that shape.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Not movable by its background: the panel is repositioned under the
        // mouse on every show (so a drag never survived anyway), and letting a
        // background drag move the window would fight the row drag-and-drop
        // that Phase 3B adds.
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        panel.contentMinSize = Self.minSize
        panel.contentMaxSize = Self.maxSize
        panel.delegate = self

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
        viewModel.onCopyToClipboard = { [weak self] item, mode in
            self?.copyToClipboard(item, mode: mode)
        }
        viewModel.onPaste = { [weak self] item, mode in
            self?.pasteItem(item, mode: mode)
        }
        viewModel.onPasteMultiple = { [weak self] items, mode in
            self?.pasteMultiple(items, mode: mode)
        }
        viewModel.onDismiss = { [weak self] in
            self?.close()
        }

        let contentView = HistoryContentView(store: store, viewModel: viewModel)
        let host = NSHostingView(rootView: contentView)
        // The window controls its own frame; without this the flexible SwiftUI
        // content drives the hosting view's fitting size and blows the window up.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panelSize)
        window?.contentView = host
    }

    private func copyToClipboard(_ item: ClipboardItem, mode: PasteMode) {
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.copyToClipboard(item, store: store, mode: mode)
    }

    func pasteItem(_ item: ClipboardItem, mode: PasteMode = .rich) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.paste(item, store: store, previousApp: appToRestore, mode: mode)
    }

    func pasteMultiple(_ items: [ClipboardItem], mode: PasteMode = .rich) {
        let appToRestore = previousApp
        close()
        NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
        PasteController.pasteMultiple(items, store: store, previousApp: appToRestore, mode: mode)
    }

    override func showWindow(_ sender: Any?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Compute reset decision *before* super.showWindow fires didBecomeKeyNotification
        // → bufferWindowDidOpen, so the content view onReceive handler sees the right value.
        shouldResetOnOpen = shouldResetSearch

        let panel = window as? HistoryPanel
        panel?.suppressResignUntil = Date().addingTimeInterval(0.4)
        position(window)

        // Start collapsed so the card can bounce in.
        viewModel.isPresented = false

        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.viewModel.isPresented = true
            } else {
                withAnimation(Theme.promptSpring) {
                    self.viewModel.isPresented = true
                }
            }
            self.applyDebugSelection()
        }
    }

    /// Centre the panel on the screen under the mouse, sitting 8 % above dead
    /// centre — reads better than perfectly centred (Clipfield's placement).
    private func position(_ window: NSWindow?) {
        guard let window else { return }
        let size = panelSize
        window.setContentSize(size)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            window.center()
            return
        }
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.08
        window.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: true
        )
    }

    /// `KLIP_DEBUG=1` + `KLIP_SELECT_FIRST=1`: point the selection at the first
    /// row on open, so screenshots can show the selected state without driving
    /// the UI with synthetic clicks.
    private func applyDebugSelection() {
        let env = ProcessInfo.processInfo.environment
        guard env["KLIP_DEBUG"] == "1", env["KLIP_SELECT_FIRST"] == "1" else { return }
        viewModel.selectFirstItem()
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let size = window?.contentView?.frame.size else { return }
        let settings = SettingsManager.shared
        settings.windowWidth = Double(size.width)
        settings.windowHeight = Double(size.height)
    }
}
