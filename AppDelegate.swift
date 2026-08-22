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

    let clipboardStore = ClipboardStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate UserDefaults from the old "Buffer" app domain before anything
        // (including SettingsManager.shared, a lazy singleton) reads/writes defaults.
        migrateUserDefaultsFromBufferIfNeeded()

        let isDebug = ProcessInfo.processInfo.environment["KLIP_DEBUG"] == "1"

        // Hide dock icon - we're menu bar only
        NSApp.setActivationPolicy(.accessory)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            // Give it a tiny delay to ensure everything is loaded before registering SMAppService
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SettingsManager.shared.toggleLaunchAtLogin(true)
                defaults.set(true, forKey: "hasLaunchedBefore")
            }
        }

        // Request Accessibility permissions for global hotkeys.
        // Skipped under KLIP_DEBUG so test instances never pop system dialogs.
        if isDebug {
            print("[AppDelegate] KLIP_DEBUG=1: skipping Accessibility prompt")
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

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
        print("[AppDelegate] applicationWillTerminate — call stack:")
        Thread.callStackSymbols.forEach { print($0) }
    }

    private func toggleHistoryWindow() {
        print("[AppDelegate] toggleHistoryWindow called")
        if let window = historyWindowController?.window, window.isVisible {
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

    /// One-time migration of UserDefaults from the old "com.samirpatil.Buffer" bundle
    /// domain into this app's standard defaults. Only fills in keys that are not
    /// already present, and only runs once (guarded by "klip.migratedDefaults").
    /// Skipped entirely when KLIP_DATA_DIR is set, so test runs never inherit the
    /// user's real hotkey/history-limit settings.
    private func migrateUserDefaultsFromBufferIfNeeded() {
        guard ProcessInfo.processInfo.environment["KLIP_DATA_DIR"] == nil else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "klip.migratedDefaults") else { return }

        if let bufferDefaults = defaults.persistentDomain(forName: "com.samirpatil.Buffer") {
            for (key, value) in bufferDefaults where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            print("[AppDelegate] Migrated \(bufferDefaults.count) UserDefaults key(s) from com.samirpatil.Buffer")
        }

        defaults.set(true, forKey: "klip.migratedDefaults")
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

        print("[AppDelegate] Debug notification hooks registered")
    }
}
