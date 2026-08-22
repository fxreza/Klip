import SwiftUI

/// The Paste action button in the action bar (Phase 3D: a split button).
///
/// The main button pastes the focused item in whatever `mode` the caller
/// hands it (`HistoryViewModel.defaultPasteMode`, which honors "Always paste
/// as plain text"). The trailing chevron opens a small menu with the
/// explicit alternate action ("Paste as Plain Text" / "Paste with
/// Formatting", whichever is not the default right now) and the "Always
/// paste as plain text" toggle itself.
struct PasteButton: View {
    /// Pastes with the current default mode.
    let action: () -> Void
    /// Pastes with the alternate (non-default) mode.
    let pasteAlternate: () -> Void

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        HStack(spacing: 1) {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(Theme.icon(11, weight: .medium))

                    Image(systemName: "return")
                        .font(Theme.icon(10, weight: .medium))

                    Text("Paste")
                        .font(.klip(.chip))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .fixedSize()
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help(mainHelp)

            Menu {
                Button(alternateLabel) { pasteAlternate() }

                Divider()

                Toggle("Always Paste as Plain Text", isOn: $settings.alwaysPastePlain)

                Text("Pasting multiple selected items always joins them as plain text.")
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.icon(9, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .help("More paste options")
        }
        .background(Capsule().fill(Theme.accentGradient))
        .foregroundStyle(Color.white)
    }

    private var alternateLabel: String {
        let title = settings.alwaysPastePlain ? "Paste with Formatting" : "Paste as Plain Text"
        return "\(title) (\(shortcuts.displayString(for: .pastePlain)))"
    }

    private var mainHelp: String {
        settings.alwaysPastePlain
            ? "Paste as plain text into the previous app (↩) — Always Paste as Plain Text is on"
            : "Paste into the previous app, keeping formatting (↩)"
    }
}
