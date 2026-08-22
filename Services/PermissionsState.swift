// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) — App/PermissionsState.swift

import AppKit
import ApplicationServices

/// Posted by `PasteController` when a paste falls back to clipboard-only
/// because Klip lacks Accessibility access. `AppDelegate` observes this to
/// show `AccessibilityToast`. Load-bearing string — do not rename.
extension Notification.Name {
    static let klipPasteNeedsAccessibility = Notification.Name("klipPasteNeedsAccessibility")
}

/// Tracks whether the app has Accessibility permission (needed to synthesize
/// ⌘V for auto-paste), polling so the UI can reflect a grant made in System
/// Settings without a relaunch. Also surfaces the other bits of state the
/// Permissions/Onboarding UI needs: Launch at Login and iCloud Drive
/// availability (the latter is a Phase 4 sync hook).
@MainActor
final class PermissionsState: ObservableObject {
    static let shared = PermissionsState()

    @Published private(set) var accessibilityTrusted: Bool

    /// Called once when access transitions from not-granted to granted.
    var onBecameTrusted: (() -> Void)?

    private var timer: Timer?

    /// `testTrusted` lets an offscreen-rendering harness (or a unit test)
    /// construct a `PermissionsState` in a known state instead of reading
    /// the real, environment-dependent `AXIsProcessTrusted()`.
    init(testTrusted: Bool? = nil) {
        self.accessibilityTrusted = testTrusted ?? AXIsProcessTrusted()
    }

    /// Starts a 1 s poll of `AXIsProcessTrusted()`. Callers should pair this
    /// with `stopPolling()` (e.g. view `onAppear`/`onDisappear`) — this only
    /// needs to run while a permissions/onboarding window is visible, not
    /// for the app's whole lifetime.
    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-reads accessibility trust and fires `onBecameTrusted` on the
    /// false->true edge. `overrideTrusted` bypasses the real system call —
    /// used by tests to drive the edge-detection logic deterministically.
    func refresh(trusted overrideTrusted: Bool? = nil) {
        let trusted = overrideTrusted ?? AXIsProcessTrusted()
        guard trusted != accessibilityTrusted else { return }
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = trusted
        if trusted && !wasTrusted { onBecameTrusted?() }
    }

    /// Triggers the system Accessibility prompt (adds Klip to the list) and
    /// opens System Settings → Privacy & Security → Accessibility.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    /// Opens System Settings → Privacy & Security → Accessibility without
    /// re-triggering the system prompt (for when Klip is already listed but
    /// unchecked).
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether Klip is registered to launch at login (`SMAppService`, via
    /// `SettingsManager`).
    var launchAtLoginEnabled: Bool {
        SettingsManager.shared.launchAtLogin
    }

    /// Whether the user has iCloud Drive available for this Mac — checked by
    /// looking for the standard iCloud Drive container directory. Used by
    /// the Permissions screen today (informational) and by Phase 4 sync.
    var iCloudDriveAvailable: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: path.path)
    }
}
