import Foundation
import AppKit

/// The modifier keys a `KeyBinding` can require. Deliberately separate from
/// `HotkeyModifiers` (`Services/SettingsManager.swift`), which is the older
/// bool-quad type the single global open-Klip hotkey still uses; this is the
/// `OptionSet` the per-action shortcut table (`Services/ShortcutManager.swift`)
/// is built on. `RawValue == Int` is `Codable`, so this struct's
/// compiler-synthesized `Codable` conformance round-trips through a plain
/// `{"rawValue": N}` JSON object.
struct KeyModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift   = KeyModifiers(rawValue: 1 << 1)
    static let option  = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)

    /// Builds the set from an `NSEvent`'s modifier flags. Callers that care
    /// about exact-match semantics (see `KeyBinding.matches(_:)`) should
    /// intersect with `.deviceIndependentFlagsMask` first.
    init(eventFlags flags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        self = result
    }
}

/// A single key + modifier combination bound to a `ShortcutAction`.
///
/// Ordering in `display` follows the same `⌃⌥⇧⌘` convention already used by
/// `HotkeyModifiers.displayString` (`Services/SettingsManager.swift`) and by
/// the ported Clipfield recorder, so the Global row and every action row in
/// the Shortcuts tab read consistently (e.g. the paste-as-plain-text default
/// is `⌥⌘C`, matching real macOS menu conventions like `⇧⌘4`).
struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: KeyModifiers

    init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Glyph string for display, e.g. `"⌥⌘C"`, `"⌘⌫"`, `"↩"`, `"⇥"`, `"Esc"`.
    var display: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        out += Self.keyName(keyCode: keyCode)
        return out
    }

    /// Whether `event` triggers this binding — exact match on key code *and*
    /// the device-independent modifier flags, so `⌘V` never matches `⌘⇧V`
    /// (or vice versa).
    func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyModifiers(eventFlags: flags) == modifiers
    }

    /// Display name for a raw key code: letters, digits, punctuation and
    /// space come from the `keyCodeNames` table (`Services/SettingsManager.swift`);
    /// everything else (arrows, return, tab, delete/forward-delete, escape,
    /// F1–F12) is named here.
    static func keyName(keyCode: UInt16) -> String {
        switch keyCode {
        case 36, 76: return "↩"   // Return / keypad enter
        case 48:     return "⇥"   // Tab
        case 51:     return "⌫"   // Delete (backspace)
        case 117:    return "⌦"   // Forward delete
        case 53:     return "Esc" // Escape
        case 123:    return "←"
        case 124:    return "→"
        case 125:    return "↓"
        case 126:    return "↑"
        case 122:    return "F1"
        case 120:    return "F2"
        case 99:     return "F3"
        case 118:    return "F4"
        case 96:     return "F5"
        case 97:     return "F6"
        case 98:     return "F7"
        case 100:    return "F8"
        case 101:    return "F9"
        case 109:    return "F10"
        case 103:    return "F11"
        case 111:    return "F12"
        default:
            return keyCodeNames[keyCode] ?? "Key\(keyCode)"
        }
    }
}
