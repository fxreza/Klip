import Foundation

// Covers the pure/testable parts of Phase 3G's permissions work (see
// docs/plan/briefs/3G-permissions.md): the trusted false->true edge
// detection in PermissionsState (driven deterministically via
// `refresh(trusted:)` rather than the real, environment-dependent
// AXIsProcessTrusted()), the iCloud Drive / launch-at-login wiring, the
// klipPasteNeedsAccessibility notification name, and the
// hasCompletedOnboarding UserDefaults round-trip. The UI (PermissionsView,
// OnboardingView, AccessibilityToast) is verified separately via offscreen
// rendering, not here.

enum PermissionsTests {
    static let tests: [(String, () throws -> Void)] = [
        ("permissionsState_onBecameTrusted_firesOnceOnFalseToTrueEdge", testOnBecameTrustedEdge),
        ("permissionsState_refresh_noFireWhenConstructedTrusted", testRefreshNoRefireWhenUnchanged),
        ("permissionsState_iCloudDriveAvailable_matchesFileManagerCheck", testICloudDriveAvailable),
        ("permissionsState_launchAtLoginEnabled_reflectsSettingsManager", testLaunchAtLoginWiring),
        ("notificationName_klipPasteNeedsAccessibility_rawValueIsStable", testNotificationNameRawValue),
        ("settingsManager_hasCompletedOnboarding_persistsToUserDefaults", testHasCompletedOnboardingPersistence),
    ]

    @MainActor
    static func testOnBecameTrustedEdge() throws {
        let state = PermissionsState(testTrusted: false)
        var fireCount = 0
        state.onBecameTrusted = { fireCount += 1 }

        state.refresh(trusted: false)
        try expectEqual(fireCount, 0, "should not fire while still false")
        try expect(!state.accessibilityTrusted, "should remain untrusted")

        state.refresh(trusted: true)
        try expectEqual(fireCount, 1, "should fire exactly once on the false->true edge")
        try expect(state.accessibilityTrusted, "should now report trusted")

        state.refresh(trusted: true)
        try expectEqual(fireCount, 1, "should not refire while already trusted")
    }

    @MainActor
    static func testRefreshNoRefireWhenUnchanged() throws {
        let state = PermissionsState(testTrusted: true)
        var fireCount = 0
        state.onBecameTrusted = { fireCount += 1 }
        state.refresh(trusted: true)
        try expectEqual(fireCount, 0, "already-trusted construction should not fire onBecameTrusted on a no-op refresh")
    }

    @MainActor
    static func testICloudDriveAvailable() throws {
        let expected = FileManager.default.fileExists(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs").path
        )
        try expectEqual(PermissionsState(testTrusted: false).iCloudDriveAvailable, expected)
    }

    @MainActor
    static func testLaunchAtLoginWiring() throws {
        let state = PermissionsState(testTrusted: false)
        try expectEqual(state.launchAtLoginEnabled, SettingsManager.shared.launchAtLogin)
    }

    static func testNotificationNameRawValue() throws {
        try expectEqual(Notification.Name.klipPasteNeedsAccessibility.rawValue, "klipPasteNeedsAccessibility")
    }

    @MainActor
    static func testHasCompletedOnboardingPersistence() throws {
        let settings = SettingsManager.shared
        let original = settings.hasCompletedOnboarding
        defer { settings.hasCompletedOnboarding = original }

        settings.hasCompletedOnboarding = true
        try expect(KlipDefaults.standard.bool(forKey: "onboarding.completed"), "true should persist to onboarding.completed")

        settings.hasCompletedOnboarding = false
        try expect(!KlipDefaults.standard.bool(forKey: "onboarding.completed"), "false should persist to onboarding.completed")
    }
}
