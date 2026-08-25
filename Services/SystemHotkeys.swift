import Foundation
import AppKit

/// Answers "is this key combination already owned by macOS itself?" by
/// reading the same preferences System Settings > Keyboard > Keyboard
/// Shortcuts writes: the `com.apple.symbolichotkeys` domain.
///
/// `HotkeyManager` needs this because `RegisterEventHotKey` only ever reports
/// `eventHotKeyExistsErr` — it never says *who* holds the combination. Naming
/// the culprit is the difference between a dead recorder and an actionable
/// message ("Already used by macOS (Spotlight)").
///
/// The matcher is pure: it takes the already-decoded `AppleSymbolicHotKeys`
/// dictionary, so `Tests/SystemHotkeysTests.swift` can exercise it against
/// hand-built fixtures without touching the filesystem or the user's real
/// preferences. `systemMatch(keyCode:modifiers:)` is the only part that reads
/// the live domain.
nonisolated enum SystemHotkeys {
    /// The preferences domain and the one key inside it that matters.
    /// Read through `UserDefaults(suiteName:)` rather than by opening
    /// `~/Library/Preferences/com.apple.symbolichotkeys.plist` directly: the
    /// file is cfprefsd's to write, and a plist read can see a stale or
    /// half-written copy.
    static let domain = "com.apple.symbolichotkeys"
    static let rootKey = "AppleSymbolicHotKeys"

    /// A symbolic hotkey whose key + modifiers equal the combination asked
    /// about. `name` is nil when the id is not in `names` below — macOS keeps
    /// adding ids, and an unnamed match is still worth reporting as "macOS".
    struct Match: Equatable {
        let id: Int
        let name: String?
    }

    /// Only these four count when comparing. macOS stores the mask as
    /// `NSEvent.ModifierFlags` raw values, and arrow-key entries (space
    /// switching) additionally carry `.function` because arrow keys always
    /// set it — comparing the full mask would make those never match.
    static let comparableModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Short user-facing names, not Apple's full sentences ("Show Spotlight
    /// search"), because they are read inside "Already used by macOS (…)".
    ///
    /// Ids and their meanings come from
    /// `KeyboardSettings.appex/Contents/Resources/en.lproj/DefaultShortcutsTable.xml`,
    /// which is System Settings' own table. Two exceptions are not listed
    /// there and come from community documentation, so they are the entries
    /// most likely to drift across macOS versions: 91 (Help menu) and 50
    /// (Character Viewer). 164 is the Dictation entry (Apple ships it with a
    /// nonsense modifier mask, so in practice it simply never matches).
    static let names: [Int: String] = [
        // Focus / full keyboard access.
        7: "Keyboard navigation", 8: "Keyboard navigation", 9: "Keyboard navigation",
        10: "Keyboard navigation", 11: "Keyboard navigation", 12: "Keyboard navigation",
        13: "Keyboard navigation", 27: "Keyboard navigation", 57: "Keyboard navigation",
        // Screenshots (28-31 are the four ⇧⌘3/4/5 family members).
        28: "Screenshot", 29: "Screenshot", 30: "Screenshot", 31: "Screenshot",
        184: "Screenshot",
        // Mission Control. The "slow" ids (34/35/37) are the same shortcut
        // held down, and System Settings shows them on the same row.
        32: "Mission Control", 34: "Mission Control",
        33: "App Windows", 35: "App Windows",
        36: "Show Desktop", 37: "Show Desktop",
        // Spaces: ⌃← / ⌃→ and ⌃1…⌃9.
        79: "Switch Spaces", 80: "Switch Spaces", 81: "Switch Spaces", 82: "Switch Spaces",
        118: "Switch Spaces", 119: "Switch Spaces", 120: "Switch Spaces",
        121: "Switch Spaces", 122: "Switch Spaces", 123: "Switch Spaces",
        124: "Switch Spaces", 125: "Switch Spaces", 126: "Switch Spaces",
        // Dock, menus, input.
        50: "Character Viewer",
        52: "Dock Hiding",
        60: "Input Sources", 61: "Input Sources",
        64: "Spotlight", 65: "Spotlight",
        91: "Help Menu",
        160: "Launchpad",
        163: "Notification Center",
        164: "Dictation",
        175: "Do Not Disturb",
        190: "Quick Note",
        222: "Stage Manager",
    ]

    // MARK: - Pure matcher

    /// The enabled symbolic hotkey bound to `keyCode` + `modifiers`, if any.
    ///
    /// `symbolicHotKeys` is the decoded `AppleSymbolicHotKeys` dictionary:
    /// numeric-string ids mapped to `{ enabled, value: { parameters: [ascii,
    /// keyCode, modifierMask] } }`. Everything about it is defensive — real
    /// plists contain entries with no `value` at all, entries with two
    /// parameters instead of three, and a `keyCode` of 65535 meaning "this
    /// shortcut has no key" — so anything that does not parse is skipped
    /// rather than assumed.
    static func match(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in symbolicHotKeys: [String: Any]) -> Match? {
        let wanted = modifiers.intersection(comparableModifiers)

        for (key, entry) in symbolicHotKeys {
            guard let id = Int(key),
                  let entry = entry as? [String: Any],
                  let enabled = entry["enabled"] as? Bool, enabled,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let entryKeyCode = (parameters[1] as? NSNumber)?.intValue,
                  let mask = (parameters[2] as? NSNumber)?.uintValue
            else { continue }

            // 65535 is macOS's "unset" key code (the shortcut is bound to a
            // hardware key or to nothing), and never equals a real one.
            guard entryKeyCode == Int(keyCode) else { continue }

            let entryModifiers = NSEvent.ModifierFlags(rawValue: UInt(mask)).intersection(comparableModifiers)
            guard entryModifiers == wanted else { continue }

            return Match(id: id, name: names[id])
        }
        return nil
    }

    /// Convenience over `match`: just the human name, nil when nothing
    /// matched *or* when the matching id has no name yet. Callers that need
    /// to tell those two apart use `match` directly.
    static func name(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, in symbolicHotKeys: [String: Any]) -> String? {
        match(keyCode: keyCode, modifiers: modifiers, in: symbolicHotKeys)?.name
    }

    // MARK: - Live lookup

    /// `match` against this Mac's real symbolic hotkeys. The thin,
    /// untestable half — everything it knows is in `match`.
    static func systemMatch(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Match? {
        guard let defaults = UserDefaults(suiteName: domain),
              let hotkeys = defaults.dictionary(forKey: rootKey)
        else { return nil }
        return match(keyCode: keyCode, modifiers: modifiers, in: hotkeys)
    }

    // MARK: - Message

    /// What Settings > Shortcuts shows in red under the Global section after
    /// `RegisterEventHotKey` refused the combination. `nil` means the
    /// symbolic hotkeys knew nothing about it, which leaves "some other app"
    /// as the only remaining explanation — and that one the user has to fix
    /// outside Klip.
    static func message(for match: Match?) -> String {
        guard let match else {
            return "Already used by another app. Change it in System Settings > Keyboard > Keyboard Shortcuts, or pick a different combination."
        }
        guard let name = match.name else { return "Already used by macOS" }
        return "Already used by macOS (\(name))"
    }
}
