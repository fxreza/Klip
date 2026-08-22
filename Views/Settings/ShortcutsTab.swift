import SwiftUI
import AppKit

/// Settings > Shortcuts: the global open-Klip hotkey (still backed by
/// `SettingsManager`/`HotkeyManager`, unchanged) followed by every in-window
/// `ShortcutAction`, grouped the same way `ShortcutAction.Group` orders them.
/// Wired into the `TabView` in `Views/SettingsView.swift`; the old General
/// tab recorder/presets moved here (General keeps a one-line summary).
struct ShortcutsTab: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        Form {
            Section("Global") {
                globalHotkeyRow
                if let conflict = globalHotkeyConflict {
                    Text("Also bound in-window to \(conflict.label) — while Klip is the frontmost app, whichever handler runs first wins.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Opens or hides the Klip window from anywhere, even while another app is focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ShortcutAction.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(actions(in: group), id: \.self) { action in
                        ShortcutRow(action: action)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        shortcuts.resetAll()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func actions(in group: ShortcutAction.Group) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.group == group }
    }

    private var globalHotkeyRow: some View {
        HStack(spacing: 12) {
            Text("Open Klip")
            Spacer()
            HotkeyRecorder(display: globalDisplay) { binding in
                settings.hotkeyKeyCode = binding.keyCode
                settings.hotkeyModifiers = HotkeyModifiers(
                    shift: binding.modifiers.contains(.shift),
                    command: binding.modifiers.contains(.command),
                    option: binding.modifiers.contains(.option),
                    control: binding.modifiers.contains(.control)
                )
            }
            .frame(width: 120, height: 24)
        }
    }

    private var globalDisplay: String {
        settings.hotkeyModifiers.displayString + (keyCodeNames[settings.hotkeyKeyCode] ?? "?")
    }

    /// The in-window action, if any, that currently shares the global
    /// open-Klip hotkey's exact key + modifier combination. The global
    /// hotkey is a system-wide `HotkeyManager` registration, so a collision
    /// does not stop either handler from firing — this is purely an
    /// informational note in the tab, not an enforced conflict like
    /// `ShortcutManager.set(_:for:)`'s in-window check.
    private var globalHotkeyConflict: ShortcutAction? {
        var modifiers: KeyModifiers = []
        if settings.hotkeyModifiers.command { modifiers.insert(.command) }
        if settings.hotkeyModifiers.shift { modifiers.insert(.shift) }
        if settings.hotkeyModifiers.option { modifiers.insert(.option) }
        if settings.hotkeyModifiers.control { modifiers.insert(.control) }
        let globalBinding = KeyBinding(keyCode: settings.hotkeyKeyCode, modifiers: modifiers)
        return ShortcutAction.allCases.first { shortcuts.binding(for: $0) == globalBinding }
    }
}

/// One rebindable-or-fixed action row: label, recorder, conflict note, Reset.
private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @State private var conflict: ShortcutAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(action.label)
                    .foregroundStyle(action.isRebindable ? .primary : .secondary)
                Spacer()
                if isNonDefault {
                    Button("Reset") {
                        shortcuts.reset(action: action)
                        conflict = nil
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                HotkeyRecorder(
                    display: shortcuts.displayString(for: action),
                    isRebindable: action.isRebindable
                ) { binding in
                    record(binding)
                }
                .frame(width: 120, height: 24)
            }

            if let conflict {
                Text("Already used by \(conflict.label)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var isNonDefault: Bool {
        action.isRebindable && shortcuts.binding(for: action) != action.defaultBinding
    }

    private func record(_ binding: KeyBinding) {
        switch shortcuts.set(binding, for: action) {
        case .ok:
            conflict = nil
        case .conflict(let other):
            conflict = other
        }
    }
}
