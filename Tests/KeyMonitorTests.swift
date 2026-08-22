import Foundation
import AppKit

// Phase 3E part 2: the table-driven `Views/History/GlobalKeyMonitor.swift`.
//
// GlobalKeyMonitor itself needs a real NSWindow / first responder to drive
// end-to-end (that is exercised instead by the offscreen render harness —
// see docs/plan/briefs/3E2-shortcuts-wiring.md's Verify section), but
// everything the monitor's dispatch depends on is unit-testable directly:
// `ShortcutManager.action(for:)` resolving a synthetic NSEvent to the right
// `ShortcutAction`, and that resolution changing after a rebind. This
// complements Tests/ShortcutTests.swift (which covers the manager's model
// half in isolation) by exercising *every* default binding — not just a
// couple of spot checks — plus the modifier-exactness cases the old
// hardcoded keycode switch used to special-case by hand (e.g. ⌘C vs ⌥⌘C).
enum KeyMonitorTests {
    static let tests: [(String, () throws -> Void)] = [
        ("resolution_everyDefaultBindingMapsToItsOwnAction", testEveryDefaultResolves),
        ("resolution_rebindingCmdPToCmdShiftPChangesWhichEventMatches", testRebindChangesResolution),
        ("resolution_modifierExactness_cmdCVsOptionCmdC", testModifierExactnessCopyVsCopyPlain),
        ("resolution_modifierExactness_pinVsTogglePreviewShareKeycode35", testModifierExactnessPinVsTogglePreview),
        ("resolution_unboundEventResolvesToNil", testUnboundEventIsNil),
        ("resolution_fixedKeysResolveWithExpectedModifiers", testFixedKeysResolve),
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
        let suiteName = "KeyMonitorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ShortcutManager(defaults: defaults)
    }

    private static func eventFlags(for modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    // MARK: - Every default binding resolves to its own action

    /// GlobalKeyMonitor's dispatch is only as correct as this resolution: a
    /// synthetic NSEvent built from each action's own `defaultBinding` must
    /// resolve back to that exact action, for every action (all 33 of
    /// them), not just the handful ShortcutTests spot-checks.
    static func testEveryDefaultResolves() throws {
        let manager = freshManager()
        for action in ShortcutAction.allCases {
            let binding = action.defaultBinding
            let syntheticEvent = event(keyCode: binding.keyCode, modifiers: eventFlags(for: binding.modifiers))
            try expectEqual(manager.action(for: syntheticEvent), action, "\(action) defaultBinding should resolve to itself")
        }
    }

    // MARK: - Rebinding changes resolution

    static func testRebindChangesResolution() throws {
        let manager = freshManager()
        let plainCmdP = event(keyCode: 35, modifiers: [.command])
        try expectEqual(manager.action(for: plainCmdP), .pin, "Cmd+P should resolve to pin before rebinding")

        let newBinding = KeyBinding(keyCode: 35, modifiers: [.command, .shift])
        try expectEqual(manager.set(newBinding, for: .pin), .ok)

        // The old Cmd+P event no longer matches anything: nothing else
        // defaults to keycode 35 with a bare Cmd modifier.
        try expectNil(manager.action(for: plainCmdP), "plain Cmd+P should no longer resolve once pin is rebound away from it")

        // The new Cmd+Shift+P event now resolves to pin.
        let cmdShiftP = event(keyCode: 35, modifiers: [.command, .shift])
        try expectEqual(manager.action(for: cmdShiftP), .pin, "Cmd+Shift+P should resolve to pin after rebinding")
    }

    // MARK: - Modifier exactness

    /// `.copy` (⌘C) and `.copyPlain` (⌥⌘C) share a keycode; only the exact
    /// modifier set distinguishes them, exactly like GlobalKeyMonitor's old
    /// hardcoded `case 8` used to lump both under `contains(.command)`
    /// before 3E gave copyPlain its own action.
    static func testModifierExactnessCopyVsCopyPlain() throws {
        let manager = freshManager()
        let cmdC = event(keyCode: 8, modifiers: [.command])
        let cmdOptC = event(keyCode: 8, modifiers: [.command, .option])

        try expectEqual(manager.action(for: cmdC), .copy)
        try expectEqual(manager.action(for: cmdOptC), .copyPlain)
    }

    /// `.pin` (⌘P) and `.togglePreview` (⌥⌘P) also share a keycode (35).
    static func testModifierExactnessPinVsTogglePreview() throws {
        let manager = freshManager()
        let cmdP = event(keyCode: 35, modifiers: [.command])
        let cmdOptP = event(keyCode: 35, modifiers: [.command, .option])

        try expectEqual(manager.action(for: cmdP), .pin)
        try expectEqual(manager.action(for: cmdOptP), .togglePreview)
    }

    // MARK: - Unbound events fall through

    static func testUnboundEventIsNil() throws {
        let manager = freshManager()
        // Plain "C" with no modifiers is not any action's default binding —
        // GlobalKeyMonitor must let it fall through untouched (`return
        // event`) so typing in the search field is unaffected.
        let plainC = event(keyCode: 8, modifiers: [])
        try expectNil(manager.action(for: plainC))

        // An exotic combination on a keycode nothing binds to.
        let unmatched = event(keyCode: 200, modifiers: [.command, .shift, .option, .control])
        try expectNil(manager.action(for: unmatched))
    }

    // MARK: - Fixed keys (arrows, Return, Tab, Esc) resolve as documented

    static func testFixedKeysResolve() throws {
        let manager = freshManager()
        try expectEqual(manager.action(for: event(keyCode: 126, modifiers: [])), .moveUp)
        try expectEqual(manager.action(for: event(keyCode: 125, modifiers: [])), .moveDown)
        try expectEqual(manager.action(for: event(keyCode: 126, modifiers: [.shift])), .extendUp)
        try expectEqual(manager.action(for: event(keyCode: 125, modifiers: [.shift])), .extendDown)
        try expectEqual(manager.action(for: event(keyCode: 53, modifiers: [])), .escape)
        try expectEqual(manager.action(for: event(keyCode: 48, modifiers: [])), .tabComplete)
        try expectEqual(manager.action(for: event(keyCode: 36, modifiers: [])), .paste)
        try expectEqual(manager.action(for: event(keyCode: 36, modifiers: [.option])), .pastePlain)
        // Bare Backspace (clearFilter) vs Cmd+Backspace (delete) — same
        // keycode, distinguished only by the Cmd modifier.
        try expectEqual(manager.action(for: event(keyCode: 51, modifiers: [])), .clearFilter)
        try expectEqual(manager.action(for: event(keyCode: 51, modifiers: [.command])), .delete)
    }
}
