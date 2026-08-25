import Cocoa
import SwiftUI

/// Manages the menu bar status item - click to toggle window
class StatusBarController {
    private var statusItem: NSStatusItem?
    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private let onToggleHistory: () -> Void
    private var settingsWindowController: NSWindowController?
    private var activeAlert: NSAlert?

    init(store: ClipboardStore, watcher: ClipboardWatcher, onShowHistory: @escaping () -> Void) {
        self.store = store
        self.watcher = watcher
        self.onToggleHistory = onShowHistory

        if !SettingsManager.shared.hideStatusBar {
            // Deferred by one run-loop turn on purpose. Under the SwiftUI
            // `App` lifecycle, `applicationDidFinishLaunching` runs before
            // AppKit has finished setting up the menu bar, and a status item
            // created at that moment is registered but never laid out: it
            // reports a bogus frame at the top-right corner (x = screen width,
            // y = -1), draws nothing, and only responds to synthetic clicks.
            // Creating it once the launch turn has finished puts it in the bar
            // normally.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.statusItem == nil else { return }
                self.createStatusItem()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibilityChanged),
            name: .bufferStatusBarVisibilityChanged,
            object: nil
        )
    }
    
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
    }

    private func setupButton() {
        guard let button = statusItem?.button else { return }
        
        // Use SF Symbol for clipboard.
        //
        // `isTemplate` is set on the CONFIGURED image, not on the original:
        // `withSymbolConfiguration` returns a new NSImage that does not
        // inherit the flag. Setting it before the call left the menu bar with
        // a non-template, solid-black glyph — invisible on a dark menu bar,
        // while still occupying (and responding to clicks in) its 24pt slot.
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klip")
        let configured = image?.withSymbolConfiguration(config) ?? image
        configured?.isTemplate = true
        button.image = configured
        
        // Direct click action - no menu
        button.action = #selector(handleClick)
        button.target = self
        
        // Right-click for menu
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleHistory()
            return
        }
        
        if event.type == .rightMouseUp {
            // Show context menu on right click
            showContextMenu()
        } else {
            // Toggle history on left click
            onToggleHistory()
        }
    }
    
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        // Show current shortcut
        let settings = SettingsManager.shared
        let shortcutDisplay = "\(settings.hotkeyModifiers.displayString)\(keyCodeNames[settings.hotkeyKeyCode] ?? "?")"
        let shortcutItem = NSMenuItem(title: "Shortcut: \(shortcutDisplay)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Permissions...", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())
        
        // Pause/Resume
        let pauseTitle = watcher.isPaused ? "Resume Capture" : "Pause Capture"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recently Deleted (5D). Menu-only by design: the trash is a safety
        // net people reach for rarely, and a bin in the history window would
        // cost a permanent slot in a very compact toolbar.
        menu.addItem(recentlyDeletedItem())

        menu.addItem(NSMenuItem.separator())

        // Clear History
        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Klip", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Reset so left click works
    }
    
    // MARK: - Recently Deleted (5D)

    /// How many trashed clips the submenu lists. A menu is not a browser: past
    /// a couple of dozen rows it stops being scannable, and the ones anyone
    /// wants back are the recent ones.
    private static let trashMenuLimit = 25

    private func recentlyDeletedItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Recently Deleted", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let trashed = store.trashedItems
        if trashed.isEmpty {
            let empty = NSMenuItem(title: "No Deleted Clips", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            parent.submenu = submenu
            return parent
        }

        for item in trashed.prefix(Self.trashMenuLimit) {
            let entry = NSMenuItem(title: trashMenuTitle(for: item), action: #selector(restoreClip(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = item.id
            submenu.addItem(entry)
        }
        if trashed.count > Self.trashMenuLimit {
            let more = NSMenuItem(title: "\(trashed.count - Self.trashMenuLimit) more…", action: nil, keyEquivalent: "")
            more.isEnabled = false
            submenu.addItem(more)
        }

        submenu.addItem(NSMenuItem.separator())

        let retention = SettingsManager.shared.trashRetention
        let note = NSMenuItem(
            title: retention.days == nil
                ? "Kept until emptied by hand"
                : "Kept for \(retention.label)",
            action: nil,
            keyEquivalent: ""
        )
        note.isEnabled = false
        submenu.addItem(note)

        let empty = NSMenuItem(title: "Empty Trash…", action: #selector(emptyTrash), keyEquivalent: "")
        empty.target = self
        submenu.addItem(empty)

        parent.submenu = submenu
        return parent
    }

    /// One row's label: a single line of preview, plus how long ago it went.
    private func trashMenuTitle(for item: ClipboardItem) -> String {
        var preview = item.previewText
            .components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? item.previewText
        preview = preview.trimmingCharacters(in: .whitespaces)
        if preview.count > 48 { preview = String(preview.prefix(48)) + "…" }
        if preview.isEmpty { preview = item.type == .image ? "Image" : "Clip" }

        guard let deletedAt = item.deletedAt else { return preview }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "\(preview)  —  \(formatter.localizedString(for: deletedAt, relativeTo: Date()))"
    }

    @objc private func restoreClip(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.restoreFromTrash(ids: [id])
    }

    @objc private func emptyTrash() {
        let count = store.trashedItems.count
        guard count > 0 else { return }

        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = count == 1
            ? "1 deleted clip will be erased permanently. This cannot be undone."
            : "\(count) deleted clips will be erased permanently. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")

        activeAlert = alert
        defer { activeAlert = nil }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.emptyTrash()
    }

    @objc private func checkForUpdates() {
        UpdateService.shared.checkForUpdates(silent: false)
    }

    @objc private func showSettings() {
        if let controller = settingsWindowController, let window = controller.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showPermissions() {
        PermissionsWindowController.shared.showWindow(nil)
    }

    @objc private func togglePause() {
        if watcher.isPaused {
            watcher.resume()
            updateIcon(paused: false)
        } else {
            watcher.pause()
            updateIcon(paused: true)
        }
    }
    
    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let alert = activeAlert else { return }
        if sender.state == .on {
            alert.informativeText = "Clear history? Pinned, favorited, tagged, locked and folder clips are kept."
        } else {
            alert.informativeText = "This will permanently delete every clip except locked ones - a lock always outranks Clear History."
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "Clear history? Pinned, favorited, tagged, locked and folder clips are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        let checkbox = NSButton(checkboxWithTitle: "Keep pinned, favorited, tagged, locked and folder clips", target: self, action: #selector(checkboxToggled(_:)))
        checkbox.state = .on
        checkbox.sizeToFit()
        checkbox.frame = NSRect(x: 0, y: 0, width: max(checkbox.frame.width, 350), height: 24)
        alert.accessoryView = checkbox

        activeAlert = alert

        if alert.runModal() == .alertFirstButtonReturn {
            let keepProtected = checkbox.state == .on
            let result = store.clear(keepProtected: keepProtected)
            // 5A-10: nothing that just went away should keep a cached badge.
            ImageThumbnailCache.evictAll()
            showClearResult(result, keepProtected: keepProtected)
        }

        activeAlert = nil
    }

    /// Reports the outcome of Clear History. The history window may not be
    /// open (no `HistoryViewModel` to hand a toast to from here), so this
    /// always uses a follow-up `NSAlert` - informational, auto-dismissible
    /// with Return/Esc.
    private func showClearResult(_ result: ClipboardStore.DeleteResult, keepProtected: Bool) {
        let alert = NSAlert()
        alert.messageText = "History Cleared"
        alert.informativeText = Self.clearResultMessage(
            deleted: result.deleted,
            kept: result.skippedLocked,
            keepProtected: keepProtected
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Wording of the Clear History result (review-2B low #1), as a pure
    /// function so `Tests/StatusBarCopyTests.swift` can pin it.
    ///
    /// The kept count is deliberately *not* described as "locked": with the
    /// checkbox on, `clear(keepProtected: true)` keeps everything protected —
    /// pinned, favorited, tagged, foldered **and** locked — so calling all of
    /// them locked (the wording the other delete surfaces use, where only
    /// locks can block a delete) would be wrong. With the checkbox off, locks
    /// really are the only thing left standing, and the message says so.
    static func clearResultMessage(deleted: Int, kept: Int, keepProtected: Bool) -> String {
        let clipsWord = deleted == 1 ? "clip" : "clips"
        guard kept > 0 else { return "Cleared \(deleted) \(clipsWord)." }
        let keptWord: String
        if keepProtected {
            keptWord = kept == 1 ? "protected clip" : "protected clips"
        } else {
            keptWord = kept == 1 ? "locked clip" : "locked clips"
        }
        return "Cleared \(deleted) \(clipsWord); \(kept) \(keptWord) kept."
    }

    @objc private func visibilityChanged() {
        if SettingsManager.shared.hideStatusBar {
            removeStatusItem()
        } else if statusItem == nil {
            createStatusItem()
        }
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateIcon(paused: Bool) {
        guard let button = statusItem?.button else { return }
        
        let symbolName = paused ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Klip")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(config)
    }
}
