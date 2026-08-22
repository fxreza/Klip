import SwiftUI

// TEMP-SHIM remove at integration: `Services/SettingsManager.swift`'s
// `HistoryLimit` enum still has today's essential/deep/unlimited(=1000)
// cases. A concurrent worktree is replacing it with the target API from
// docs/plan/briefs/1C-settings-theme.md:
//   enum HistoryLimit: Int, CaseIterable { case k1 = 1000, k5 = 5000, k10 = 10000, unlimited = 0 }
//   static let default, maxItems: Int?, isUnlimited, label, subtitle, static func from(storedRaw:)
// This extension backfills just enough of that API (in terms of *today's*
// cases) so this file can be written directly against the target shape.
// `maxItems` never returns nil today because the old enum has no "unlimited"
// case in the new sense — that's expected of a shim, and the real
// implementation's nil-for-unlimited case is exactly what `isDowngrade(from:to:)`
// below already accounts for.
extension HistoryLimit {
    static var `default`: HistoryLimit { .essential }

    var maxItems: Int? { rawValue }

    var isUnlimited: Bool { false }

    static func from(storedRaw: Int?) -> HistoryLimit {
        guard let raw = storedRaw, let match = HistoryLimit(rawValue: raw) else { return .default }
        return match
    }
}

/// Settings window for Klip preferences. Every control binds directly to
/// `SettingsManager.shared` — there is no separate view-model layer, and
/// every change applies immediately (this matches how native macOS Settings
/// panes behave, and loses nothing versus the old explicit "Save" flow: the
/// only thing that flow ever did was copy a local draft back into
/// `SettingsManager` and call `.save()`, which now happens as soon as you
/// touch a control).
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsTab()
                    .tabItem { Label("General", systemImage: "gearshape") }
                HistorySettingsTab()
                    .tabItem { Label("History", systemImage: "clock") }
                AppearanceSettingsTab()
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
            }

            Divider()
            AboutFooter()
                .padding(.vertical, 10)
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isRecording = false

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text(settings.hotkeyModifiers.displayString)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                        Text(keyCodeNames[settings.hotkeyKeyCode] ?? "?")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )

                    Button(action: { isRecording.toggle() }) {
                        Text(isRecording ? "Cancel" : "Change")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                if isRecording {
                    Text("Press your new shortcut...")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 8) {
                    presetButton(label: "⇧⌘V", mods: HotkeyModifiers(shift: true, command: true), keyCode: 9)
                    presetButton(label: "⌥⌘V", mods: HotkeyModifiers(command: true, option: true), keyCode: 9)
                    presetButton(label: "⌃⇧V", mods: HotkeyModifiers(shift: true, control: true), keyCode: 9)
                    presetButton(label: "⌘B", mods: HotkeyModifiers(command: true), keyCode: 11)
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { SettingsManager.shared.toggleLaunchAtLogin($0) }
                ))
            }

            Section("Updates") {
                Toggle("Include Pre-release Updates", isOn: Binding(
                    get: { settings.includePrereleases },
                    set: { newValue in
                        settings.includePrereleases = newValue
                        if newValue {
                            UpdateService.shared.checkForUpdates(silent: true)
                        }
                    }
                ))

                Button("Check for Updates…") {
                    UpdateService.shared.checkForUpdates(silent: false)
                }
            }

            Section("Menu Bar") {
                Toggle("Hide Menu Bar Icon", isOn: $settings.hideStatusBar)
            }
        }
        .formStyle(.grouped)
        .background(KeyRecorder(isRecording: $isRecording) { keyCode, modifiers in
            settings.hotkeyKeyCode = keyCode
            settings.hotkeyModifiers = modifiers
            isRecording = false
        })
    }

    private func presetButton(label: String, mods: HotkeyModifiers, keyCode: UInt16) -> some View {
        Button(action: {
            settings.hotkeyModifiers = mods
            settings.hotkeyKeyCode = keyCode
        }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - History

private struct HistorySettingsTab: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var pendingTier: HistoryLimit?
    @State private var showingTrimAlert = false

    var body: some View {
        Form {
            Section("History Size") {
                HStack(spacing: 12) {
                    ForEach(HistoryLimit.allCases, id: \.self) { tier in
                        tierButton(tier)
                    }
                }
                Text("Older unpinned, unbookmarked, untagged items are removed once the limit is reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Reduce History Limit?", isPresented: $showingTrimAlert) {
            Button("Cancel", role: .cancel) { pendingTier = nil }
            Button("Reduce & Delete", role: .destructive) {
                if let tier = pendingTier {
                    apply(tier)
                }
                pendingTier = nil
            }
        } message: {
            Text("This will permanently delete your oldest unbookmarked items to fit the new size. This action cannot be undone.")
        }
    }

    private func tierButton(_ tier: HistoryLimit) -> some View {
        let isSelected = settings.historyLimit == tier
        return Button(action: { select(tier) }) {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.3))
                    .font(.system(size: 14))

                Text(tier.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Text(tier.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func select(_ tier: HistoryLimit) {
        if isDowngrade(from: settings.historyLimit, to: tier) {
            pendingTier = tier
            showingTrimAlert = true
        } else {
            apply(tier)
        }
    }

    private func apply(_ tier: HistoryLimit) {
        settings.historyLimit = tier
        settings.save()
        NotificationCenter.default.post(name: .bufferHistoryLimitChanged, object: nil)
    }

    /// True when `new` keeps fewer items than `current` — i.e. items could be
    /// trimmed. `nil` `maxItems` means "unlimited" (see the TEMP-SHIM above).
    private func isDowngrade(from current: HistoryLimit, to new: HistoryLimit) -> Bool {
        switch (current.maxItems, new.maxItems) {
        case (nil, nil): return false
        case (nil, .some): return true
        case (.some, nil): return false
        case let (.some(currentMax), .some(newMax)): return newMax < currentMax
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Theme") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                    accentPicker
                }
                .padding(.vertical, 2)

                Picker("Appearance", selection: $settings.colorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Text Size") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("List text size")
                        Spacer()
                        Text("\(Int(settings.listFontScale * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.listFontScale, in: 0.8...1.6)
                    Text("Sample clipboard item")
                        .font(.klip(.rowTitle))
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Preview text size")
                        Spacer()
                        Text("\(Int(settings.previewFontScale * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.previewFontScale, in: 0.8...1.6)
                    Text("Sample preview text")
                        .font(.klip(.preview))
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                Toggle("Show preview pane", isOn: $settings.showPreviewPane)
            }
        }
        .formStyle(.grouped)
    }

    private var accentPicker: some View {
        HStack(spacing: 10) {
            ForEach(AccentTheme.allCases) { theme in
                let selected = settings.accentTheme == theme
                Button {
                    settings.accentTheme = theme
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme == .system ? AnyShapeStyle(.gray.gradient) : AnyShapeStyle(theme.color.gradient))
                            .frame(width: 22, height: 22)
                        if theme == .system {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                        }
                        if selected {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help(theme.label)
            }
        }
    }
}

// MARK: - About footer

private struct AboutFooter: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Designed to disappear. Built to remember.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
                .italic()

            Text("Klip \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · based on Buffer by @samirpatil2000")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.4))

            HStack(spacing: 8) {
                Link("⭐ Star on GitHub", destination: URL(string: "https://github.com/samirpatil2000/Buffer")!)
                    .font(.system(size: 10, weight: .medium))

                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))

                Link("Report an Issue", destination: URL(string: "https://github.com/samirpatil2000/Buffer/issues/new")!)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

/// Records keyboard shortcuts when active
struct KeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (UInt16, HotkeyModifiers) -> Void

    func makeNSView(context: Context) -> KeyRecorderView {
        let view = KeyRecorderView()
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: KeyRecorderView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class KeyRecorderView: NSView {
    var isRecording = false
    var onRecord: ((UInt16, HotkeyModifiers) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            // Set level to be above other apps but below system items
            window.level = .floating

            // Use a tiny delay to allow the window to be properly added to the window list
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Ignore modifier-only presses
        if event.keyCode == 56 || event.keyCode == 59 || event.keyCode == 58 || event.keyCode == 55 {
            return
        }

        let mods = HotkeyModifiers(
            shift: event.modifierFlags.contains(.shift),
            command: event.modifierFlags.contains(.command),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )

        // Require at least one modifier
        if mods.shift || mods.command || mods.option || mods.control {
            onRecord?(event.keyCode, mods)
        }
    }
}
