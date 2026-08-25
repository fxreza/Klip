import Foundation
import AppKit

// `Services/SystemHotkeys.swift` — the lookup behind Settings > Shortcuts'
// "Already used by macOS (…)" message. Only the pure matcher is covered: it
// takes a decoded `AppleSymbolicHotKeys` dictionary, so every case here is a
// hand-built fixture and nothing reads the user's real preferences.
//
// The fixtures reproduce shapes seen in a real
// ~/Library/Preferences/com.apple.symbolichotkeys.plist, including the messy
// ones: entries with no `value`, entries with two parameters instead of
// three, 65535 as "no key", and arrow-key entries whose mask carries
// `.function` on top of the real modifiers.

enum SystemHotkeysTests {
    static let tests: [(String, () throws -> Void)] = [
        ("match_findsSpotlightOnCommandSpace", testSpotlightMatch),
        ("match_ignoresDisabledEntries", testDisabledEntryIgnored),
        ("match_requiresTheSameModifiers", testModifiersMustMatch),
        ("match_requiresTheSameKeyCode", testKeyCodeMustMatch),
        ("match_ignoresTheFunctionFlagOnArrowKeyEntries", testFunctionFlagIgnored),
        ("match_survivesMalformedEntries", testMalformedEntriesSkipped),
        ("match_reportsUnknownIdsWithoutAName", testUnknownIdHasNoName),
        ("names_coverTheCommonSystemShortcuts", testNamesTable),
        ("message_namesTheSystemShortcut", testMessageWithName),
        ("message_fallsBackToPlainMacOSForUnknownIds", testMessageWithoutName),
        ("message_pointsAtSystemSettingsWhenNothingMatched", testMessageNoMatch),
    ]

    // MARK: - Fixtures

    /// One `AppleSymbolicHotKeys` entry in macOS's own shape.
    private static func entry(enabled: Bool, ascii: Int, keyCode: Int, mask: UInt) -> [String: Any] {
        [
            "enabled": enabled,
            "value": [
                "parameters": [ascii, keyCode, mask],
                "type": "standard",
            ] as [String: Any],
        ]
    }

    private static let command = UInt(NSEvent.ModifierFlags.command.rawValue)
    private static let control = UInt(NSEvent.ModifierFlags.control.rawValue)
    private static let shift = UInt(NSEvent.ModifierFlags.shift.rawValue)
    private static let function = UInt(NSEvent.ModifierFlags.function.rawValue)

    /// 64 = Spotlight on ⌘Space, 30 = ⇧⌘4, 79 = ⌃← (space switching).
    private static var standardFixture: [String: Any] {
        [
            "64": entry(enabled: true, ascii: 32, keyCode: 49, mask: command),
            "30": entry(enabled: true, ascii: 52, keyCode: 21, mask: shift | command),
            "79": entry(enabled: true, ascii: 65535, keyCode: 123, mask: control | function),
        ]
    }

    // MARK: - Matching

    static func testSpotlightMatch() throws {
        let match = SystemHotkeys.match(keyCode: 49, modifiers: [.command], in: standardFixture)
        try expectEqual(match, SystemHotkeys.Match(id: 64, name: "Spotlight"))
    }

    static func testDisabledEntryIgnored() throws {
        // The user turned ⌘Space off, so Klip may have it.
        let fixture: [String: Any] = [
            "64": entry(enabled: false, ascii: 32, keyCode: 49, mask: command),
        ]
        try expectNil(SystemHotkeys.match(keyCode: 49, modifiers: [.command], in: fixture))
    }

    static func testModifiersMustMatch() throws {
        // ⌥Space is free even though ⌘Space is Spotlight, and ⌘4 is free
        // even though ⇧⌘4 is a screenshot — the comparison is exact, like
        // KeyBinding.matches(_:).
        try expectNil(SystemHotkeys.match(keyCode: 49, modifiers: [.option], in: standardFixture))
        try expectNil(SystemHotkeys.match(keyCode: 21, modifiers: [.command], in: standardFixture))
        try expectEqual(SystemHotkeys.match(keyCode: 21, modifiers: [.command, .shift], in: standardFixture),
                        SystemHotkeys.Match(id: 30, name: "Screenshot"))
    }

    static func testKeyCodeMustMatch() throws {
        try expectNil(SystemHotkeys.match(keyCode: 9, modifiers: [.command], in: standardFixture),
                      "⌘V is not a system shortcut in this fixture")
    }

    static func testFunctionFlagIgnored() throws {
        // Arrow keys always carry .function, so macOS stores ⌃← with it in
        // the mask while the recorder never records it. Comparing the raw
        // masks would make space switching invisible.
        try expectEqual(SystemHotkeys.match(keyCode: 123, modifiers: [.control], in: standardFixture),
                        SystemHotkeys.Match(id: 79, name: "Switch Spaces"))
        try expectEqual(SystemHotkeys.match(keyCode: 123, modifiers: [.control, .function], in: standardFixture),
                        SystemHotkeys.Match(id: 79, name: "Switch Spaces"),
                        ".function on the query side is dropped too")
    }

    static func testMalformedEntriesSkipped() throws {
        var fixture = standardFixture
        fixture["15"] = ["enabled": true]                                  // no value at all
        fixture["164"] = ["enabled": true, "value": ["parameters": [8388608, 4286578687]]]  // two parameters
        fixture["notANumber"] = entry(enabled: true, ascii: 32, keyCode: 49, mask: command)
        fixture["12"] = "garbage"

        // The good entry is still found, and nothing threw or crashed.
        try expectEqual(SystemHotkeys.match(keyCode: 49, modifiers: [.command], in: fixture),
                        SystemHotkeys.Match(id: 64, name: "Spotlight"))
        try expectNil(SystemHotkeys.match(keyCode: 200, modifiers: [.control], in: fixture))
    }

    static func testUnknownIdHasNoName() throws {
        // macOS keeps adding ids. An unrecognised one still has to be
        // reported — as "macOS", just without a name in parentheses.
        let fixture: [String: Any] = [
            "9999": entry(enabled: true, ascii: 32, keyCode: 49, mask: command),
        ]
        let match = SystemHotkeys.match(keyCode: 49, modifiers: [.command], in: fixture)
        try expectEqual(match, SystemHotkeys.Match(id: 9999, name: nil))
        try expectNil(SystemHotkeys.name(keyCode: 49, modifiers: [.command], in: fixture))
        try expectEqual(SystemHotkeys.message(for: match), "Already used by macOS")
    }

    static func testNamesTable() throws {
        // The ids the task list calls out, so a careless edit to the table
        // cannot silently drop one.
        try expectEqual(SystemHotkeys.names[64], "Spotlight")
        try expectEqual(SystemHotkeys.names[65], "Spotlight")
        try expectEqual(SystemHotkeys.names[32], "Mission Control")
        try expectEqual(SystemHotkeys.names[34], "Mission Control")
        try expectEqual(SystemHotkeys.names[33], "App Windows")
        try expectEqual(SystemHotkeys.names[35], "App Windows")
        try expectEqual(SystemHotkeys.names[36], "Show Desktop")
        try expectEqual(SystemHotkeys.names[37], "Show Desktop")
        try expectEqual(SystemHotkeys.names[52], "Dock Hiding")
        try expectEqual(SystemHotkeys.names[60], "Input Sources")
        try expectEqual(SystemHotkeys.names[61], "Input Sources")
        try expectEqual(SystemHotkeys.names[91], "Help Menu")
        try expectEqual(SystemHotkeys.names[160], "Launchpad")
        try expectEqual(SystemHotkeys.names[163], "Notification Center")
        try expectEqual(SystemHotkeys.names[164], "Dictation")
        try expectEqual(SystemHotkeys.names[175], "Do Not Disturb")
        try expectEqual(SystemHotkeys.names[50], "Character Viewer")
        for id in 28...31 {
            try expectEqual(SystemHotkeys.names[id], "Screenshot", "screenshot id \(id)")
        }
        for id in [7, 8, 9, 10, 11, 12, 27] {
            try expectEqual(SystemHotkeys.names[id], "Keyboard navigation", "focus id \(id)")
        }
    }

    // MARK: - Message

    static func testMessageWithName() throws {
        try expectEqual(SystemHotkeys.message(for: SystemHotkeys.Match(id: 64, name: "Spotlight")),
                        "Already used by macOS (Spotlight)")
    }

    static func testMessageWithoutName() throws {
        try expectEqual(SystemHotkeys.message(for: SystemHotkeys.Match(id: 9999, name: nil)),
                        "Already used by macOS")
    }

    static func testMessageNoMatch() throws {
        try expectEqual(SystemHotkeys.message(for: nil),
                        "Already used by another app. Change it in System Settings > Keyboard > Keyboard Shortcuts, or pick a different combination.")
    }
}
