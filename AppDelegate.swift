import Cocoa
import SwiftUI
import Carbon.HIToolbox
import Darwin

// `notify_register_dispatch` (from <notify.h>) is part of libSystem but its header
// is not exposed through the macOS SDK's Darwin module map, so we bind the symbol
// directly. It is always present at runtime — it backs `notifyutil`/`notify_post`.
@_silgen_name("notify_register_dispatch")
func klip_notify_register_dispatch(
    _ name: UnsafePointer<CChar>?,
    _ outToken: UnsafeMutablePointer<Int32>?,
    _ queue: DispatchQueue,
    _ handler: @convention(block) @escaping (Int32) -> Void
) -> UInt32

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var clipboardWatcher: ClipboardWatcher?
    private var historyWindowController: HistoryWindowController?
    private var hotkeyManager: HotkeyManager?
    private var debugNotifyTokens: [Int32] = []
    private var onboardingWindowController: OnboardingWindowController?
    private var lastAccessibilityToastAt: Date?

    let clipboardStore = ClipboardStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate UserDefaults from the old "Buffer" app domain before anything
        // (including SettingsManager.shared, a lazy singleton) reads/writes defaults.
        migrateUserDefaultsFromBufferIfNeeded()

        let isDebug = ProcessInfo.processInfo.environment["KLIP_DEBUG"] == "1"

        // Hide dock icon - we're menu bar only
        NSApp.setActivationPolicy(.accessory)

        let defaults = KlipDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            // Give it a tiny delay to ensure everything is loaded before registering SMAppService
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsManager.shared.toggleLaunchAtLogin(true)
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }

        // First-run onboarding replaces the old unconditional Accessibility
        // prompt: if access isn't trusted yet and onboarding was never
        // completed, show it (after a short delay so the rest of launch
        // finishes first); otherwise never prompt automatically — the user
        // reaches Permissions… from the status-bar menu.
        // Skipped under KLIP_DEBUG so test instances never pop system dialogs
        // or windows.
        if isDebug {
            print("[AppDelegate] KLIP_DEBUG=1: skipping Accessibility prompt/onboarding")
        } else {
            if !AXIsProcessTrusted() && !SettingsManager.shared.hasCompletedOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.showOnboarding()
                }
            }

            NotificationCenter.default.addObserver(
                forName: .klipPasteNeedsAccessibility,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handlePasteNeedsAccessibility()
            }
        }

        // Phase 4A: iCloud Drive sync. Attaching wires the store's mutation /
        // delete hooks; `startIfEnabled` starts watching only when the user
        // turned sync on and iCloud Drive is actually there, and keeps
        // listening for that setting changing.
        CloudDriveSync.shared.attach(store: clipboardStore)
        CloudDriveSync.shared.startIfEnabled()

        // Initialize clipboard watcher
        clipboardWatcher = ClipboardWatcher(store: clipboardStore)
        clipboardWatcher?.startWatching()

        // Initialize status bar
        statusBarController = StatusBarController(
            store: clipboardStore,
            watcher: clipboardWatcher!,
            onShowHistory: { [weak self] in
                self?.showHistoryWindow()
            }
        )

        // Initialize history window controller
        historyWindowController = HistoryWindowController(store: clipboardStore)

        // Setup global hotkey (Shift + Command + V)
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleHistoryWindow()
        }
        hotkeyManager?.register()

        NotificationCenter.default.addObserver(forName: .bufferHotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.hotkeyManager?.reregister()
        }

        if isDebug {
            print("[AppDelegate] KLIP_DEBUG=1: skipping update checks")
            setupDebugHooks()
        } else {
            UpdateService.shared.checkIfJustUpdated()

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                UpdateService.shared.checkOnLaunchIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardWatcher?.stopWatching()
        hotkeyManager?.unregister()
        clipboardStore.flushPendingSave()
        // Phase 4A: stop watching, then get this session's clips into iCloud
        // Drive before the process goes away (the 2 s push debounce may not
        // have fired yet).
        //
        // 5A-16: bounded to 3 s in total. `pushSynchronously` runs on the main
        // thread and its per-file copy timeout is 20 s, so an unbounded quit
        // push could beachball for minutes (and be SIGKILLed anyway) when
        // iCloud has not materialised the assets. Anything that does not fit
        // in the budget is left for the next launch — the metadata write still
        // happens, and assets are write-once so the retry is free.
        if CloudDriveSync.shared.isActive {
            CloudDriveSync.shared.stop()
            CloudDriveSync.shared.pushSynchronously(budget: 3.0)
        }
        print("[AppDelegate] applicationWillTerminate — call stack:")
        Thread.callStackSymbols.forEach { print($0) }
    }

    private func toggleHistoryWindow() {
        print("[AppDelegate] toggleHistoryWindow called")
        if let window = historyWindowController?.window, window.isVisible {
            // Keep Open leaves the window on screen after a paste, with the
            // keyboard back in the app that was pasted into. In that state the
            // hotkey means "give Klip the keyboard again", not "close" —
            // closing a window the user can see, and asked to keep, is never
            // what they meant by summoning it. Once it *is* the key window the
            // hotkey closes it as usual.
            if !window.isKeyWindow, SettingsManager.shared.keepWindowOpen {
                print("[AppDelegate] Window is visible but not key, refocusing...")
                historyWindowController?.refocus()
                return
            }
            print("[AppDelegate] Window is visible, closing...")
            historyWindowController?.close()
        } else {
            print("[AppDelegate] Window is hidden, showing...")
            showHistoryWindow()
        }
    }

    private func showHistoryWindow() {
        historyWindowController?.showWindow(nil)
    }

    private func showOnboarding() {
        guard onboardingWindowController == nil else { return }
        let controller = OnboardingWindowController { [weak self] in
            self?.onboardingWindowController = nil
            self?.showHistoryWindow()
        }
        onboardingWindowController = controller
        controller.showWindow(nil)
    }

    /// Rate-limited (once per 60 s) so repeated paste attempts without
    /// Accessibility access don't stack HUDs on screen.
    private func handlePasteNeedsAccessibility() {
        if let last = lastAccessibilityToastAt, Date().timeIntervalSince(last) < 60 {
            return
        }
        lastAccessibilityToastAt = Date()
        AccessibilityToast.shared.show {
            PermissionsWindowController.shared.showWindow(nil)
        }
    }

    /// One-time migration of UserDefaults from the old "com.samirpatil.Buffer" bundle
    /// domain into this app's standard defaults. Only fills in keys that are not
    /// already present, and only runs once (guarded by "klip.migratedDefaults").
    /// Skipped entirely when KLIP_DATA_DIR is set, so test runs never inherit the
    /// user's real hotkey/history-limit settings.
    private func migrateUserDefaultsFromBufferIfNeeded() {
        guard ProcessInfo.processInfo.environment["KLIP_DATA_DIR"] == nil else { return }

        let defaults = KlipDefaults.standard
        guard !defaults.bool(forKey: "klip.migratedDefaults") else { return }

        if let bufferDefaults = defaults.persistentDomain(forName: "com.samirpatil.Buffer") {
            for (key, value) in bufferDefaults where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            print("[AppDelegate] Migrated \(bufferDefaults.count) UserDefaults key(s) from com.samirpatil.Buffer")
        }

        defaults.set(true, forKey: "klip.migratedDefaults")

        migrateUserDefaultsFromWorkaroundIdentifierIfNeeded()
    }

    /// Copy-only migration from `com.fxreza.klip.app`, the identifier a
    /// handful of local builds carried between 3.2.0 and 3.3.0.
    ///
    /// That identifier was a workaround: macOS refused to lay out the status
    /// item for `com.fxreza.klip`, and rebuilding under any other identifier
    /// placed the icon immediately. The cause turned out to be ControlCenter's
    /// per-app "Allow in the Menu Bar" store, not the identifier itself (see
    /// `docs/analysis/menubar-status-item-not-laid-out.md`), so 3.3.0 ships
    /// the original identifier again and this carries any settings changed
    /// while the workaround was installed back to it.
    ///
    /// Settings live in the preferences domain, which is keyed by bundle
    /// identifier, so they need copying across. The clipboard history, folders
    /// and trash do not: they live in `Application Support/Klip`, keyed by
    /// folder name, and every build reads exactly the same files.
    ///
    /// No released version ever carried `com.fxreza.klip.app`, so on any other
    /// Mac the domain simply does not exist and this does nothing. The
    /// workaround domain is read, never written or deleted.
    private func migrateUserDefaultsFromWorkaroundIdentifierIfNeeded() {
        guard ProcessInfo.processInfo.environment["KLIP_DATA_DIR"] == nil else { return }

        let defaults = KlipDefaults.standard
        guard !defaults.bool(forKey: "klip.migratedFromWorkaroundIdentifier") else { return }

        if let previous = defaults.persistentDomain(forName: "com.fxreza.klip.app") {
            var copied = 0
            for (key, value) in previous where defaults.object(forKey: key) == nil {
                // The saved status item position is deliberately NOT carried
                // over — this domain's copy was written while the item was
                // never being laid out, so it is not a position worth keeping.
                guard !key.hasPrefix("NSStatusItem ") else { continue }
                defaults.set(value, forKey: key)
                copied += 1
            }
            print("[AppDelegate] Migrated \(copied) UserDefaults key(s) from com.fxreza.klip.app")
        }

        defaults.set(true, forKey: "klip.migratedFromWorkaroundIdentifier")
    }

    /// Darwin notification hooks for driving the app from test scripts, active only
    /// under KLIP_DEBUG=1. Never registered in normal user runs.
    private func setupDebugHooks() {
        func register(_ name: String, _ handler: @escaping () -> Void) {
            var token: Int32 = 0
            name.withCString { cName in
                _ = klip_notify_register_dispatch(cName, &token, DispatchQueue.main) { _ in
                    handler()
                }
            }
            debugNotifyTokens.append(token)
        }

        register("com.fxreza.klip.debug.show") { [weak self] in
            self?.showHistoryWindow()
        }
        register("com.fxreza.klip.debug.hide") { [weak self] in
            self?.historyWindowController?.close()
        }
        register("com.fxreza.klip.debug.toggle") { [weak self] in
            self?.toggleHistoryWindow()
        }
        register("com.fxreza.klip.debug.quit") {
            NSApp.terminate(nil)
        }
        // Layout toggles, so screenshots of the collapsed-sidebar / hidden-preview
        // states can be taken without driving the UI with synthetic clicks.
        register("com.fxreza.klip.debug.toggleSidebar") { [weak self] in
            self?.historyWindowController?.viewModel.toggleSidebar()
        }
        register("com.fxreza.klip.debug.togglePreview") { [weak self] in
            self?.historyWindowController?.viewModel.togglePreviewPane()
        }
        // Move the selection without a key event. The history panel is
        // non-activating and closes when it loses key focus, so anything that
        // drives it from outside — System Events, a synthetic key — takes the
        // focus away and shuts the window in the same breath. These are how a
        // screenshot of "the preview pane on the next clip" gets taken at all.
        register("com.fxreza.klip.debug.selectNext") { [weak self] in
            self?.historyWindowController?.viewModel.keyDown()
        }
        register("com.fxreza.klip.debug.selectPrevious") { [weak self] in
            self?.historyWindowController?.viewModel.keyUp()
        }

        print("[AppDelegate] Debug notification hooks registered")
    }
}
