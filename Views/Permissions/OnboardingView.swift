// Adapted from Clipfield (MIT, Copyright 2026 Alex Jolley) — UI/Onboarding/OnboardingView.swift

import AppKit
import SwiftUI

/// First-run window: a short welcome plus the Accessibility status card, so a
/// new user either grants access right away or knowingly skips it (Klip
/// still works via manual ⌘V either way). Replaces the old unconditional
/// `AXIsProcessTrustedWithOptions` prompt fired blind on every launch.
struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsState
    var onDone: () -> Void

    private var trusted: Bool { permissions.accessibilityTrusted }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accentGradient)

            VStack(spacing: 6) {
                Text("Welcome to Klip")
                    .font(.title2.bold())
                Text("Press ⇧⌘V anywhere to open your clipboard history, search it, and paste.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            HStack(spacing: 10) {
                Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(trusted ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trusted ? "Accessibility access granted" : "Accessibility access needed")
                        .font(.headline)
                    Text(trusted
                         ? "Selecting an item will paste it straight into the app you're using."
                         : "Needed to paste into the app you were using; without it Klip still copies to the clipboard and you press ⌘V yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            Button {
                if trusted {
                    onDone()
                } else {
                    permissions.requestAccessibility()
                }
            } label: {
                Label(trusted ? "Get Started" : "Grant Accessibility Access",
                      systemImage: trusted ? "checkmark" : "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if !trusted {
                Button("Skip for now") { onDone() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(28)
        .frame(width: 440)
        // Polling start/stop is driven by `OnboardingWindowController`, not
        // view appearance — see the note in `PermissionsView`.
    }
}

// MARK: - Window controller

/// Presents `OnboardingView` as the first-run window. Marks onboarding
/// complete (`SettingsManager.hasCompletedOnboarding`) whenever it finishes —
/// whether the user tapped "Get Started"/"Skip for now", or Accessibility
/// access was granted from System Settings while the window was still open
/// (`onBecameTrusted`, closing the window and revealing history 0.3 s later
/// so the granted state is visible for a beat first).
final class OnboardingWindowController: NSWindowController {
    private let permissions: PermissionsState
    private let onFinished: () -> Void

    init(permissions: PermissionsState? = nil, onFinished: @escaping () -> Void) {
        let permissions = permissions ?? .shared
        self.permissions = permissions
        self.onFinished = onFinished

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        let view = OnboardingView(permissions: permissions, onDone: { [weak self] in
            self?.finish(afterDelay: 0)
        })
        let hostingController = NSHostingController(rootView: view)
        window.contentViewController = hostingController
        // The view's own `.frame(width: 440)` fixes the width; let SwiftUI
        // report the height its content actually needs instead of guessing.
        let fitting = hostingController.view.fittingSize
        window.setContentSize(NSSize(width: 440, height: max(fitting.height, 380)))
        window.center()

        permissions.onBecameTrusted = { [weak self] in
            guard self?.window?.isVisible == true else { return }
            self?.finish(afterDelay: 0.3)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        permissions.startPolling()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(afterDelay delay: TimeInterval) {
        SettingsManager.shared.hasCompletedOnboarding = true
        permissions.onBecameTrusted = nil
        permissions.stopPolling()
        close()
        let callback = onFinished
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            callback()
        }
    }
}
