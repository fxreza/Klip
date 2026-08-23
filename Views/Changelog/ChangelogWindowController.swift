import Cocoa
import SwiftUI

/// Presents `ChangelogView` in its own ordinary window.
///
/// Deliberately an `NSWindow` with `[.titled, .closable, .resizable]` and *not*
/// an `NSPanel`: the history window is a `.nonactivatingPanel` that closes as
/// soon as you click outside it, which is right for a paste picker and wrong
/// for something you sit and read. Inheriting that behaviour here would make
/// the notes vanish the moment you clicked another app to check something.
///
/// A singleton for the same reason `PermissionsWindowController` is one —
/// clicking "What's New" on the toast and then "Changelog" in Settings should
/// bring the same window forward, not stack a second copy behind the first.
final class ChangelogWindowController: NSWindowController {
    static let shared = ChangelogWindowController()

    private static let defaultSize = NSSize(width: 460, height: 560)
    private static let minSize = NSSize(width: 380, height: 320)

    /// Fallback when no release URL is known (opened from Settings rather than
    /// after an update).
    private static let releasesIndexURL = URL(string: "https://github.com/fxreza/Klip/releases")!

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New"
        window.minSize = Self.minSize
        // The app is an accessory (LSUIElement) with no main window, so AppKit
        // would otherwise deallocate this on close and leave `shared` holding a
        // zombie.
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Builds the content from the bundled changelog and brings the window up.
    ///
    /// - Parameters:
    ///   - releaseURL: the GitHub page for the release that just installed, if
    ///     we have one; the footer link falls back to the releases index.
    ///   - fallbackNotes: the GitHub release `body`, used only when the running
    ///     version has no section in the bundled `CHANGELOG.md`.
    func show(releaseURL: URL? = nil, fallbackNotes: String? = nil) {
        guard let window else { return }

        let entries = ChangelogService.allEntries()
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        print("[Changelog] Showing changelog window — \(entries.count) entry(ies), running \(version.isEmpty ? "?" : version)")

        window.title = version.isEmpty ? "What's New in Klip" : "What's New in Klip \(version)"
        window.contentView = NSHostingView(
            rootView: ChangelogView(
                entries: entries,
                currentVersion: version,
                fallbackNotes: fallbackNotes,
                githubURL: releaseURL ?? Self.releasesIndexURL
            )
        )
        // Re-applied after swapping the content view: NSHostingView reports its
        // own fitting size and can shrink the frame out from under minSize.
        window.minSize = Self.minSize
        if window.frame.size.width < Self.minSize.width || window.frame.size.height < Self.minSize.height {
            window.setContentSize(Self.defaultSize)
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        // An accessory app is never frontmost on its own; without this the
        // window opens behind whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
    }
}
