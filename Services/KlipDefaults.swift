import Foundation

/// The preferences store for this process.
///
/// Test instances launched with `KLIP_DATA_DIR` (see `scripts/run_app.sh`) share the
/// production bundle identifier, so `UserDefaults.standard` would read and write the
/// same domain as the installed app. They get their own suite instead, so a harness
/// toggling settings can never change the user's real preferences.
nonisolated enum KlipDefaults {
    static let testSuiteName = "com.fxreza.klip.test"

    static var isTestInstance: Bool {
        ProcessInfo.processInfo.environment["KLIP_DATA_DIR"] != nil
    }

    static let standard: UserDefaults = {
        if isTestInstance, let suite = UserDefaults(suiteName: testSuiteName) { return suite }
        return .standard
    }()
}
