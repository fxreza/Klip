import Foundation
import AppKit
import Combine

/// Every rebindable (or fixed-but-shown) in-window action, reproducing
/// today's hardcoded `Views/History/GlobalKeyMonitor.swift` switch exactly as
/// the default table. Phase 3E part 2 makes the monitor table-driven against
/// `ShortcutManager`; this enum plus the manager below are the model half.
enum ShortcutAction: String, CaseIterable, Codable {
    // Clipboard
    case paste, pastePlain, copy, copyPlain, delete, pin, star, lock, edit, addTag, saveToDisk
    case clearFilter
    /// Name (or rename) the focused clip. Unlike `edit` this works on every
    /// kind — an image or a file has no editable body but can still be named.
    case renameClip

    // Organize
    case newFolder, renameFolder, moveToFolder

    // Window
    case toggleSidebar, togglePreview

    // Navigation
    //
    // 3.0.1 removed `nextScope` / `previousScope` (⌘[ / ⌘]). The sidebar is
    // the only way to change scope now; a stored override for either key is
    // simply ignored when the table is decoded (see `init`).
    case moveUp, moveDown, extendUp, extendDown, tabComplete, escape

    enum Group: String, CaseIterable {
        case navigation = "Navigation"
        case clipboard = "Clipboard"
        case organize = "Organize"
        case window = "Window"
    }

    var group: Group {
        switch self {
        case .paste, .pastePlain, .copy, .copyPlain, .delete, .pin, .star, .lock, .edit,
             .addTag, .saveToDisk, .clearFilter, .renameClip:
            return .clipboard
        case .newFolder, .renameFolder, .moveToFolder:
            return .organize
        case .toggleSidebar, .togglePreview:
            return .window
        case .moveUp, .moveDown, .extendUp, .extendDown, .tabComplete, .escape:
            return .navigation
        }
    }

    var label: String {
        switch self {
        case .paste: return "Paste"
        case .pastePlain: return "Paste as Plain Text"
        case .copy: return "Copy"
        case .copyPlain: return "Copy as Plain Text"
        case .delete: return "Delete"
        case .pin: return "Pin"
        case .star: return "Favorite"
        case .lock: return "Lock"
        case .edit: return "Edit"
        case .addTag: return "Add Tag"
        case .saveToDisk: return "Save to Disk"
        case .clearFilter: return "Clear Tag Filter"
        case .renameClip: return "Rename Clip"
        case .newFolder: return "New Folder"
        case .renameFolder: return "Rename Folder"
        case .moveToFolder: return "Move to Folder"
        case .toggleSidebar: return "Toggle Sidebar"
        case .togglePreview: return "Toggle Preview Pane"
        case .moveUp: return "Move Selection Up"
        case .moveDown: return "Move Selection Down"
        case .extendUp: return "Extend Selection Up"
        case .extendDown: return "Extend Selection Down"
        case .tabComplete: return "Tab-Complete Tag Filter"
        case .escape: return "Escape / Deselect"
        }
    }

    /// `false` for the handful of keys that are structural to list navigation
    /// (arrows, return, escape, tab) — the Shortcuts tab shows these rows
    /// greyed out with no recorder rather than letting them be rebound.
    var isRebindable: Bool {
        switch self {
        case .paste, .pastePlain, .moveUp, .moveDown, .extendUp, .extendDown, .tabComplete, .escape:
            return false
        default:
            return true
        }
    }

    /// Reproduces today's hardcoded keys exactly (see
    /// `Views/History/GlobalKeyMonitor.swift` and `docs/analysis/buffer.md` §3).
    var defaultBinding: KeyBinding {
        switch self {
        case .paste:          return KeyBinding(keyCode: 36, modifiers: [])            // ↩
        case .pastePlain:     return KeyBinding(keyCode: 36, modifiers: [.option])     // ⌥↩
        case .copy:           return KeyBinding(keyCode: 8,  modifiers: [.command])    // ⌘C
        case .copyPlain:      return KeyBinding(keyCode: 8,  modifiers: [.command, .option]) // ⌥⌘C
        case .delete:         return KeyBinding(keyCode: 51, modifiers: [.command])    // ⌘⌫
        case .pin:            return KeyBinding(keyCode: 35, modifiers: [.command])    // ⌘P
        case .star:           return KeyBinding(keyCode: 3,  modifiers: [.command])    // ⌘F (was ⌘B before 3.0.1)
        case .lock:           return KeyBinding(keyCode: 37, modifiers: [.command])    // ⌘L
        case .edit:           return KeyBinding(keyCode: 14, modifiers: [.command])    // ⌘E
        case .addTag:         return KeyBinding(keyCode: 17, modifiers: [.command])    // ⌘T
        case .saveToDisk:     return KeyBinding(keyCode: 1,  modifiers: [.command])    // ⌘S
        case .clearFilter:    return KeyBinding(keyCode: 51, modifiers: [])            // ⌫ (only when search is empty)
        case .renameClip:     return KeyBinding(keyCode: 120, modifiers: [])           // F2 (Finder / Ditto convention)
        case .newFolder:      return KeyBinding(keyCode: 45, modifiers: [.command])    // ⌘N
        case .renameFolder:   return KeyBinding(keyCode: 15, modifiers: [.command])    // ⌘R
        case .moveToFolder:   return KeyBinding(keyCode: 46, modifiers: [.command])    // ⌘M
        case .toggleSidebar:  return KeyBinding(keyCode: 1,  modifiers: [.command, .option]) // ⌥⌘S
        case .togglePreview:  return KeyBinding(keyCode: 35, modifiers: [.command, .option]) // ⌥⌘P
        case .moveUp:         return KeyBinding(keyCode: 126, modifiers: [])           // ↑
        case .moveDown:       return KeyBinding(keyCode: 125, modifiers: [])           // ↓
        case .extendUp:       return KeyBinding(keyCode: 126, modifiers: [.shift])     // ⇧↑
        case .extendDown:     return KeyBinding(keyCode: 125, modifiers: [.shift])     // ⇧↓
        case .tabComplete:    return KeyBinding(keyCode: 48, modifiers: [])            // ⇥
        case .escape:         return KeyBinding(keyCode: 53, modifiers: [])            // Esc
        }
    }
}

/// Owns the per-action key bindings: resolves each action's effective
/// `KeyBinding` (a stored override, or its default), persists only the
/// overrides, and detects conflicts before accepting a rebind.
///
/// The global open-Klip hotkey is *not* managed here — it stays in
/// `SettingsManager`/`HotkeyManager` unchanged; the Shortcuts tab just shows
/// it as the first row, reusing `HotkeyRecorder`.
@MainActor
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()

    enum ConflictResult: Equatable {
        case ok
        case conflict(ShortcutAction)
    }

    private static let storageKey = "shortcuts.bindings"
    private let defaults: UserDefaults

    /// Every action resolved to its effective binding: a stored override
    /// where one exists, `defaultBinding` otherwise. UserDefaults only ever
    /// stores the overrides (see `persist()`), so a future change to a
    /// default automatically applies to anyone who never rebound that action.
    @Published var bindings: [ShortcutAction: KeyBinding]

    init(defaults: UserDefaults = KlipDefaults.standard) {
        self.defaults = defaults
        var resolved: [ShortcutAction: KeyBinding] = [:]
        for action in ShortcutAction.allCases {
            resolved[action] = action.defaultBinding
        }
        if let data = defaults.data(forKey: Self.storageKey),
           let overrides = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            for (rawKey, binding) in overrides {
                // Unknown keys are skipped rather than treated as corruption,
                // so an override stored for an action that no longer exists
                // (`nextScope` / `previousScope`, removed in 3.0.1) does not
                // throw away the rest of the user's rebinds.
                if let action = ShortcutAction(rawValue: rawKey) {
                    resolved[action] = binding
                }
            }
        }
        self.bindings = resolved
    }

    func binding(for action: ShortcutAction) -> KeyBinding {
        bindings[action] ?? action.defaultBinding
    }

    func displayString(for action: ShortcutAction) -> String {
        binding(for: action).display
    }

    /// Attempts to bind `binding` to `action`. Refused (with the conflicting
    /// action returned) when another action already uses the identical key +
    /// modifier combination.
    @discardableResult
    func set(_ binding: KeyBinding, for action: ShortcutAction) -> ConflictResult {
        if let conflict = ShortcutAction.allCases.first(where: { $0 != action && self.binding(for: $0) == binding }) {
            return .conflict(conflict)
        }
        bindings[action] = binding
        persist()
        return .ok
    }

    func reset(action: ShortcutAction) {
        bindings[action] = action.defaultBinding
        persist()
    }

    func resetAll() {
        for action in ShortcutAction.allCases {
            bindings[action] = action.defaultBinding
        }
        persist()
    }

    /// First action whose binding matches `event`, in `ShortcutAction.allCases`
    /// order. The monitor (part 2) will call this instead of its hardcoded
    /// keycode switch.
    func action(for event: NSEvent) -> ShortcutAction? {
        ShortcutAction.allCases.first { binding(for: $0).matches(event) }
    }

    private func persist() {
        var overrides: [String: KeyBinding] = [:]
        for action in ShortcutAction.allCases {
            let current = bindings[action] ?? action.defaultBinding
            if current != action.defaultBinding {
                overrides[action.rawValue] = current
            }
        }
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
