import SwiftUI

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
                ShortcutsTab()
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                SyncTab()
                    .tabItem { Label("Sync", systemImage: "icloud") }
                PermissionsView()
                    .tabItem { Label("Permissions", systemImage: "lock.shield") }
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

    var body: some View {
        Form {
            Section("Global Shortcut") {
                Text("Open Klip: \(settings.hotkeyModifiers.displayString)\(keyCodeNames[settings.hotkeyKeyCode] ?? "?") - change in Shortcuts")
                    .foregroundStyle(.secondary)
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

            Section("Lock / Protect") {
                Text("Locked clips can't be deleted until you unlock them. Clips inside folders are locked automatically. Pinned, starred, tagged, locked and folder clips never count toward the history limit.")
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
                    .font(.body)

                Text(tier.label)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Text(tier.subtitle)
                    .font(.caption2)
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
        NotificationCenter.default.post(name: .bufferHistoryLimitChanged, object: nil)
    }

    /// True when `new` keeps fewer items than `current` — i.e. items could be
    /// trimmed. `nil` `maxItems` means "unlimited".
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
                                .font(.caption)
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
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary.opacity(0.5))
                .italic()

            Text("Klip \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · based on Buffer by @samirpatil2000")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))

            HStack(spacing: 8) {
                Link("⭐ Star on GitHub", destination: URL(string: "https://github.com/samirpatil2000/Buffer")!)
                    .font(.caption2.weight(.medium))

                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.4))

                Link("Report an Issue", destination: URL(string: "https://github.com/samirpatil2000/Buffer/issues/new")!)
                    .font(.caption2.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}
