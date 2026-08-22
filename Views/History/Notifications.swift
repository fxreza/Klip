import Foundation

// Notification names used across the app. Names are load-bearing (they are
// posted and observed from AppDelegate, StatusBarController, SettingsView and
// the clipboard watcher) — do not rename the string values.
extension Notification.Name {
    static let bufferIgnoreNextChange = Notification.Name("bufferIgnoreNextChange")
    static let bufferHotkeyChanged = Notification.Name("bufferHotkeyChanged")
    static let bufferWindowDidOpen = Notification.Name("bufferWindowDidOpen")
    static let bufferHistoryLimitChanged = Notification.Name("bufferHistoryLimitChanged")
    static let bufferStatusBarVisibilityChanged = Notification.Name("bufferStatusBarVisibilityChanged")
}
