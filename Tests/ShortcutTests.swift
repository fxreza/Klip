import Foundation
import AppKit

// Custom shortcuts (Phase 3E): `Models/KeyBinding.swift` and
// `Services/ShortcutManager.swift`. Covers the defaults table against
// `docs/analysis/buffer.md` §3 / `Views/History/GlobalKeyMonitor.swift`'s
// hardcoded keycodes, display-string glyph order, exact-match semantics,
// conflict detection, persistence round trip (via an injected
// `UserDefaults(suiteName:)`, never `.standard`) and reset.

enum ShortcutTests {
    static let tests: [(String, () throws -> Void)] = [
        ("defaults_reproduceTodaysHardcodedKeys", testDefaultsMatchGlobalKeyMonitor),
        ("isRebindable_falseOnlyForNavigationPrimitives", testIsRebindableFlags),
        ("display_ordersGlyphsControlOptionShiftCommand", testDisplayGlyphOrder),
        ("display_namesSpecialKeysByGlyphOrWord", testDisplaySpecialKeys),
        ("matches_isExactOnModifiers_commandVsCommandShift", testMatchesExactness),
        ("matches_requiresSameKeyCode", testMatchesKeyCode),
        ("conflict_refusesBindingAlreadyUsedByAnotherAction", testConflictDetection),
        ("conflict_allowsReassigningToItself", testNoConflictWithSelf),
        ("reset_restoresDefaultForOneAction", testResetSingleAction),
        ("resetAll_restoresEveryAction", testResetAll),
        ("persistence_roundTripsThroughInjectedUserDefaults", testPersistenceRoundTrip),
        ("persistence_onlyStoresOverridesNotTheFullTable", testPersistenceStoresOverridesOnly),
        ("action_forEvent_findsFirstMatchingAction", testActionForEvent),
        // 3.0.1 — scope cycling removed, favorite on ⌘F.
        ("scopeCycling_actionsAreGone", testScopeCyclingRemoved),
        ("decoding_ignoresOverridesForRemovedActions", testRemovedOverridesIgnored),
        ("defaults_areAllDistinct", testDefaultsAreDistinct),
        // review-2B test gap #1 — HotkeyRecorder's Esc / modifier gate.
        ("recorder_escapeCancelsRecording", testRecorderEscapeCancels),
        ("recorder_requiresCommandControlOrOption", testRecorderModifierGate),
        ("recorder_recordsTheFullModifierSet", testRecorderRecordsModifiers),
    ]

    // MARK: - Fixtures

    private static func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private static func freshManager() -> ShortcutManager {
        let suiteName = "ShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ShortcutManager(defaults: defaults)
    }

    // MARK: - Defaults table

    static func testDefaultsMatchGlobalKeyMonitor() throws {
        // Views/History/GlobalKeyMonitor.swift's hardcoded switch, reproduced
        // exactly as documented defaults.
        try expectEqual(ShortcutAction.paste.defaultBinding, KeyBinding(keyCode: 36, modifiers: []), "paste = Return")
        try expectEqual(ShortcutAction.pastePlain.defaultBinding, KeyBinding(keyCode: 36, modifiers: [.option]), "pastePlain = Option+Return")
        try expectEqual(ShortcutAction.copy.defaultBinding, KeyBinding(keyCode: 8, modifiers: [.command]), "copy = Cmd+C")
        try expectEqual(ShortcutAction.copyPlain.defaultBinding, KeyBinding(keyCode: 8, modifiers: [.command, .option]), "copyPlain = Cmd+Opt+C")
        try expectEqual(ShortcutAction.delete.defaultBinding, KeyBinding(keyCode: 51, modifiers: [.command]), "delete = Cmd+Backspace")
        try expectEqual(ShortcutAction.pin.defaultBinding, KeyBinding(keyCode: 35, modifiers: [.command]), "pin = Cmd+P")
        // 3.0.1: favorite moved from ⌘B to ⌘F (nothing else uses ⌘F — the
        // search field is focused automatically, so ⌘F has no other job).
        try expectEqual(ShortcutAction.star.defaultBinding, KeyBinding(keyCode: 3, modifiers: [.command]), "favorite = Cmd+F")
        try expectEqual(ShortcutAction.star.label, "Favorite", "user-facing name is Favorite, not Star")
        try expectEqual(ShortcutAction.lock.defaultBinding, KeyBinding(keyCode: 37, modifiers: [.command]), "lock = Cmd+L")
        try expectEqual(ShortcutAction.edit.defaultBinding, KeyBinding(keyCode: 14, modifiers: [.command]), "edit = Cmd+E")
        try expectEqual(ShortcutAction.addTag.defaultBinding, KeyBinding(keyCode: 17, modifiers: [.command]), "addTag = Cmd+T")
        try expectEqual(ShortcutAction.saveToDisk.defaultBinding, KeyBinding(keyCode: 1, modifiers: [.command]), "saveToDisk = Cmd+S")
        try expectEqual(ShortcutAction.clearFilter.defaultBinding, KeyBinding(keyCode: 51, modifiers: []), "clearFilter = bare Backspace")
        try expectEqual(ShortcutAction.newFolder.defaultBinding, KeyBinding(keyCode: 45, modifiers: [.command]), "newFolder = Cmd+N")
        try expectEqual(ShortcutAction.renameFolder.defaultBinding, KeyBinding(keyCode: 15, modifiers: [.command]), "renameFolder = Cmd+R")
        try expectEqual(ShortcutAction.moveToFolder.defaultBinding, KeyBinding(keyCode: 46, modifiers: [.command]), "moveToFolder = Cmd+M")
        try expectEqual(ShortcutAction.toggleSidebar.defaultBinding, KeyBinding(keyCode: 1, modifiers: [.command, .option]), "toggleSidebar = Cmd+Opt+S")
        try expectEqual(ShortcutAction.togglePreview.defaultBinding, KeyBinding(keyCode: 35, modifiers: [.command, .option]), "togglePreview = Cmd+Opt+P")
        try expectEqual(ShortcutAction.moveUp.defaultBinding, KeyBinding(keyCode: 126, modifiers: []), "moveUp = Up")
        try expectEqual(ShortcutAction.moveDown.defaultBinding, KeyBinding(keyCode: 125, modifiers: []), "moveDown = Down")
        try expectEqual(ShortcutAction.extendUp.defaultBinding, KeyBinding(keyCode: 126, modifiers: [.shift]), "extendUp = Shift+Up")
        try expectEqual(ShortcutAction.extendDown.defaultBinding, KeyBinding(keyCode: 125, modifiers: [.shift]), "extendDown = Shift+Down")
        try expectEqual(ShortcutAction.tabComplete.defaultBinding, KeyBinding(keyCode: 48, modifiers: []), "tabComplete = Tab")
        try expectEqual(ShortcutAction.escape.defaultBinding, KeyBinding(keyCode: 53, modifiers: []), "escape = Esc")

        // Every action has a default, and defaultBinding is deterministic.
        try expectEqual(ShortcutAction.allCases.count, ShortcutAction.allCases.map(\.rawValue).count)
    }

    static func testIsRebindableFlags() throws {
        let fixed: Set<ShortcutAction> = [.paste, .pastePlain, .moveUp, .moveDown, .extendUp, .extendDown, .tabComplete, .escape]
        for action in ShortcutAction.allCases {
            try expectEqual(action.isRebindable, !fixed.contains(action), "\(action).isRebindable")
        }
    }

    // MARK: - Display strings

    static func testDisplayGlyphOrder() throws {
        // ⌃⌥⇧⌘ ordering (matches HotkeyModifiers.displayString and the
        // ported Clipfield recorder), e.g. real macOS renders Cmd+Shift+4 as
        // "⇧⌘4", not "⌘⇧4".
        let binding = KeyBinding(keyCode: 9, modifiers: [.command, .shift]) // V
        try expectEqual(binding.display, "⇧⌘V")

        let copyPlain = ShortcutAction.copyPlain.defaultBinding // Cmd+Opt+C
        try expectEqual(copyPlain.display, "⌥⌘C")

        let all = KeyBinding(keyCode: 0, modifiers: [.control, .option, .shift, .command]) // A
        try expectEqual(all.display, "⌃⌥⇧⌘A")
    }

    static func testDisplaySpecialKeys() throws {
        try expectEqual(ShortcutAction.paste.defaultBinding.display, "↩")
        try expectEqual(ShortcutAction.delete.defaultBinding.display, "⌘⌫")
        try expectEqual(ShortcutAction.tabComplete.defaultBinding.display, "⇥")
        try expectEqual(ShortcutAction.escape.defaultBinding.display, "Esc")
        try expectEqual(ShortcutAction.moveUp.defaultBinding.display, "↑")
        try expectEqual(ShortcutAction.extendDown.defaultBinding.display, "⇧↓")
        try expectEqual(KeyBinding.keyName(keyCode: 122), "F1")
        try expectEqual(KeyBinding.keyName(keyCode: 111), "F12")
        try expectEqual(KeyBinding.keyName(keyCode: 49), "Space")
        try expectEqual(KeyBinding.keyName(keyCode: 8), "C")
        try expectEqual(KeyBinding.keyName(keyCode: 18), "1")
    }

    // MARK: - matches(_:) exactness

    static func testMatchesExactness() throws {
        let plainV = KeyBinding(keyCode: 9, modifiers: [.command])
        let shiftV = KeyBinding(keyCode: 9, modifiers: [.command, .shift])

        let cmdShiftVEvent = event(keyCode: 9, modifiers: [.command, .shift])
        try expect(!plainV.matches(cmdShiftVEvent), "⌘V should not match a ⌘⇧V event")
        try expect(shiftV.matches(cmdShiftVEvent), "⌘⇧V should match a ⌘⇧V event")

        let cmdVEvent = event(keyCode: 9, modifiers: [.command])
        try expect(plainV.matches(cmdVEvent), "⌘V should match a ⌘V event")
        try expect(!shiftV.matches(cmdVEvent), "⌘⇧V should not match a plain ⌘V event")
    }

    static func testMatchesKeyCode() throws {
        let cmdC = KeyBinding(keyCode: 8, modifiers: [.command])
        let cmdCEventWrongKey = event(keyCode: 9, modifiers: [.command])
        try expect(!cmdC.matches(cmdCEventWrongKey), "same modifiers but different key code must not match")
    }

    // MARK: - Conflict detection

    static func testConflictDetection() throws {
        let manager = freshManager()
        // .pin defaults to Cmd+P; try to also bind .star (Favorite) to Cmd+P.
        let result = manager.set(ShortcutAction.pin.defaultBinding, for: .star)
        try expectEqual(result, .conflict(.pin))
        // The rejected rebind must not have taken effect.
        try expectEqual(manager.binding(for: .star), ShortcutAction.star.defaultBinding)
    }

    static func testNoConflictWithSelf() throws {
        let manager = freshManager()
        // Rebinding pin to something new, then "reassigning" that exact same
        // binding to pin again, must not be reported as a conflict with itself.
        let newBinding = KeyBinding(keyCode: 9, modifiers: [.command, .shift])
        try expectEqual(manager.set(newBinding, for: .pin), .ok)
        try expectEqual(manager.set(newBinding, for: .pin), .ok)
        try expectEqual(manager.binding(for: .pin), newBinding)
    }

    // MARK: - Reset

    static func testResetSingleAction() throws {
        let manager = freshManager()
        let newBinding = KeyBinding(keyCode: 9, modifiers: [.command, .shift])
        try expectEqual(manager.set(newBinding, for: .pin), .ok)
        try expectEqual(manager.binding(for: .pin), newBinding)

        manager.reset(action: .pin)
        try expectEqual(manager.binding(for: .pin), ShortcutAction.pin.defaultBinding)
        // Other actions are untouched.
        try expectEqual(manager.binding(for: .star), ShortcutAction.star.defaultBinding)
    }

    static func testResetAll() throws {
        let manager = freshManager()
        try expectEqual(manager.set(KeyBinding(keyCode: 9, modifiers: [.command, .shift]), for: .pin), .ok)
        try expectEqual(manager.set(KeyBinding(keyCode: 40, modifiers: [.command, .shift]), for: .star), .ok)

        manager.resetAll()

        for action in ShortcutAction.allCases {
            try expectEqual(manager.binding(for: action), action.defaultBinding, "\(action) after resetAll")
        }
    }

    // MARK: - Persistence

    static func testPersistenceRoundTrip() throws {
        let suiteName = "ShortcutTests-roundtrip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let newBinding = KeyBinding(keyCode: 9, modifiers: [.command, .shift])
        do {
            let manager = ShortcutManager(defaults: defaults)
            try expectEqual(manager.set(newBinding, for: .pin), .ok)
        }

        // A fresh manager instance backed by the same defaults suite should
        // pick up the override.
        let reloaded = ShortcutManager(defaults: defaults)
        try expectEqual(reloaded.binding(for: .pin), newBinding)
        try expectEqual(reloaded.binding(for: .star), ShortcutAction.star.defaultBinding, "untouched actions still resolve to their default")
    }

    static func testPersistenceStoresOverridesOnly() throws {
        let suiteName = "ShortcutTests-overrides-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = ShortcutManager(defaults: defaults)
        try expectNil(defaults.data(forKey: "shortcuts.bindings"), "nothing persisted until something is rebound")

        try expectEqual(manager.set(KeyBinding(keyCode: 9, modifiers: [.command, .shift]), for: .pin), .ok)
        let data = try expectNotNilReturning(defaults.data(forKey: "shortcuts.bindings"), "expected persisted overrides after a rebind")
        let decoded = try JSONDecoder().decode([String: KeyBinding].self, from: data)
        try expectEqual(decoded.count, 1, "only the one rebound action should be persisted, not the whole table")
        try expectNotNil(decoded["pin"])

        // Resetting back to the default should shrink storage to empty (and
        // remove the key entirely, per persist()'s empty-overrides branch).
        manager.reset(action: .pin)
        try expectNil(defaults.data(forKey: "shortcuts.bindings"), "resetting the only override should clear the stored key")
    }

    // MARK: - action(for:)

    static func testActionForEvent() throws {
        let manager = freshManager()
        let cmdPEvent = event(keyCode: 35, modifiers: [.command])
        try expectEqual(manager.action(for: cmdPEvent), .pin)

        let unmatched = event(keyCode: 200, modifiers: [.command, .shift, .option, .control])
        try expectNil(manager.action(for: unmatched))
    }

    // MARK: - 3.0.1 removals / rebinds

    /// ⌘[ / ⌘] are no longer bound to anything, and no action answers to
    /// the old raw values.
    static func testScopeCyclingRemoved() throws {
        try expectNil(ShortcutAction(rawValue: "nextScope"), "nextScope is gone from the action table")
        try expectNil(ShortcutAction(rawValue: "previousScope"), "previousScope is gone from the action table")

        let manager = freshManager()
        try expectNil(manager.action(for: event(keyCode: 30, modifiers: [.command])), "⌘] is unbound")
        try expectNil(manager.action(for: event(keyCode: 33, modifiers: [.command])), "⌘[ is unbound")
        try expectEqual(manager.action(for: event(keyCode: 3, modifiers: [.command])), .star, "⌘F favorites")
    }

    /// A user who rebound scope cycling before 3.0.1 still has that override
    /// on disk. Decoding must skip it and keep every other override.
    static func testRemovedOverridesIgnored() throws {
        let suiteName = "ShortcutTests-removed-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pinOverride = KeyBinding(keyCode: 9, modifiers: [.command, .shift])
        let stored: [String: KeyBinding] = [
            "pin": pinOverride,
            "nextScope": KeyBinding(keyCode: 30, modifiers: [.command, .shift]),
            "previousScope": KeyBinding(keyCode: 33, modifiers: [.command, .shift]),
            "somethingThatNeverExisted": KeyBinding(keyCode: 40, modifiers: [.control]),
        ]
        defaults.set(try JSONEncoder().encode(stored), forKey: "shortcuts.bindings")

        let manager = ShortcutManager(defaults: defaults)
        try expectEqual(manager.binding(for: .pin), pinOverride,
                        "a live override survives alongside unknown keys")
        for action in ShortcutAction.allCases where action != .pin {
            try expectEqual(manager.binding(for: action), action.defaultBinding,
                            "\(action) still resolves to its default")
        }
    }

    /// No two actions may ship with the same default binding — that would be
    /// a permanent conflict the Shortcuts tab refuses to let the user fix.
    /// ⌘F in particular has to be free for favorite.
    static func testDefaultsAreDistinct() throws {
        var seen: [KeyBinding: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            let binding = action.defaultBinding
            if let other = seen[binding] {
                throw TestFailure(
                    message: "\(action) and \(other) share the default \(binding.display)",
                    file: #file, line: #line
                )
            }
            seen[binding] = action
        }
    }

    // MARK: - HotkeyRecorder gate (review-2B test gap #1)
    //
    // `RecorderView.keyDown` was only ever verified by reading it. The rules
    // are pure — Escape cancels (and so can never itself be recorded), and a
    // combination without ⌘/⌃/⌥ is rejected so a rebind cannot swallow
    // ordinary typing — so they are now pinned directly.

    static func testRecorderEscapeCancels() throws {
        try expectEqual(RecorderView.outcome(keyCode: 53, flags: []), .cancel,
                        "Escape cancels recording")
        try expectEqual(RecorderView.outcome(keyCode: 53, flags: [.command]), .cancel,
                        "⌘Escape is still a cancel, never a recordable binding")
    }

    static func testRecorderModifierGate() throws {
        try expectEqual(RecorderView.outcome(keyCode: 35, flags: []), .reject,
                        "a bare key is not a safe shortcut")
        try expectEqual(RecorderView.outcome(keyCode: 35, flags: [.shift]), .reject,
                        "shift alone is not enough")
        try expectEqual(RecorderView.outcome(keyCode: 35, flags: [.capsLock, .function]), .reject,
                        "non-device-independent flags do not count")

        try expectEqual(RecorderView.outcome(keyCode: 35, flags: [.command]),
                        .record(KeyBinding(keyCode: 35, modifiers: [.command])))
        try expectEqual(RecorderView.outcome(keyCode: 35, flags: [.control]),
                        .record(KeyBinding(keyCode: 35, modifiers: [.control])))
        try expectEqual(RecorderView.outcome(keyCode: 35, flags: [.option]),
                        .record(KeyBinding(keyCode: 35, modifiers: [.option])))
    }

    static func testRecorderRecordsModifiers() throws {
        let outcome = RecorderView.outcome(keyCode: 1, flags: [.command, .shift, .option, .capsLock])
        try expectEqual(outcome, .record(KeyBinding(keyCode: 1, modifiers: [.command, .shift, .option])),
                        "caps lock is dropped; the rest of the set is kept")
    }

    // MARK: - Local helpers

    private static func expectNotNilReturning<T>(_ value: T?, _ message: String, file: StaticString = #file, line: UInt = #line) throws -> T {
        guard let value else {
            throw TestFailure(message: message, file: file, line: line)
        }
        return value
    }
}
