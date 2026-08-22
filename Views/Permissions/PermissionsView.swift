// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) — App/PermissionsState.swift

import AppKit
import SwiftUI

/// Lists every permission Klip cares about (today: Accessibility, Launch at
/// Login, iCloud Drive) with a status pill, an explanation, and the actions
/// to fix it. Reused both inside its own window (`PermissionsWindowController`,
/// opened from the status-bar menu) and embedded, chrome-free, as a Settings
/// tab (`Views/SettingsView.swift`).
struct PermissionsView: View {
    @ObservedObject var permissions: PermissionsState
    @ObservedObject private var settings = SettingsManager.shared

    init(permissions: PermissionsState? = nil) {
        self.permissions = permissions ?? .shared
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.klip(.sidebarTitle).bold())

                accessibilityRow
                launchAtLoginRow
                iCloudRow

                Text("Klip needs no other permissions — no screen recording, and no network access beyond checking for app updates.")
                    .font(.klip(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        // Polling start/stop is driven by whichever window controller is
        // presenting this view (`PermissionsWindowController`,
        // `OnboardingWindowController`) rather than by view appearance —
        // `.onAppear`/`.onDisappear` fire during any SwiftUI layout pass,
        // including an offscreen `NSHostingView` render used for
        // verification, which would otherwise clobber an injected
        // `PermissionsState(testTrusted:)` with the live system value.
    }

    // MARK: - Accessibility

    private var accessibilityRow: some View {
        PermissionRow(
            icon: "accessibility",
            title: "Accessibility",
            status: permissions.accessibilityTrusted ? .granted : .needed,
            explanation: permissions.accessibilityTrusted
                ? "Klip can paste directly into the app you were using."
                : "Needed to paste into the app you were using; without it Klip still copies to the clipboard and you press ⌘V yourself."
        ) {
            if !permissions.accessibilityTrusted {
                HStack(spacing: 8) {
                    Button("Grant…") { permissions.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings…") { permissions.openAccessibilitySettings() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Launch at Login

    private var launchAtLoginRow: some View {
        PermissionRow(
            icon: "power",
            title: "Launch at Login",
            status: settings.launchAtLogin ? .granted : .needed,
            explanation: "Starts Klip automatically when you sign in, so your clipboard history is always ready."
        ) {
            Toggle("", isOn: Binding(
                get: { settings.launchAtLogin },
                set: { SettingsManager.shared.toggleLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    // MARK: - iCloud Drive

    private var iCloudRow: some View {
        PermissionRow(
            icon: "icloud",
            title: "iCloud Drive",
            status: permissions.iCloudDriveAvailable ? .granted : .unavailable,
            explanation: permissions.iCloudDriveAvailable
                ? "Available for syncing your clipboard history across devices."
                : "Sign in to iCloud and turn on iCloud Drive to sync your clipboard history across devices."
        ) {
            EmptyView()
        }
    }
}

// MARK: - Row

private struct PermissionRow<Actions: View>: View {
    let icon: String
    let title: String
    let status: PermissionStatus
    let explanation: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)

                Text(title)
                    .font(.klip(.rowTitle).weight(.semibold))

                Spacer()

                StatusPill(status: status)
            }

            Text(explanation)
                .font(.klip(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Status pill

enum PermissionStatus {
    case granted, needed, unavailable

    var label: String {
        switch self {
        case .granted: return "Granted"
        case .needed: return "Needed"
        case .unavailable: return "Not available"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .needed: return .orange
        case .unavailable: return .gray
        }
    }
}

private struct StatusPill: View {
    let status: PermissionStatus

    var body: some View {
        Text(status.label)
            .font(.klip(.badge).weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.color.opacity(0.15)))
            .foregroundStyle(status.color)
    }
}

// MARK: - Window controller

/// Presents `PermissionsView` in its own titled window (~480x420), reused
/// across shows the way `StatusBarController.showSettings` reuses its
/// settings window. Shared so both the status-bar menu item and the
/// accessibility toast's "Open Permissions…" button can bring it forward.
final class PermissionsWindowController: NSWindowController {
    static let shared = PermissionsWindowController()

    private init() {
        let hostingController = NSHostingController(rootView: PermissionsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Permissions"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 420))
        super.init(window: window)
        window.center()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        PermissionsState.shared.startPolling()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        PermissionsState.shared.stopPolling()
    }
}
