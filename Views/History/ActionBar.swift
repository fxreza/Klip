import SwiftUI

/// Bottom bar: layout toggles on the left, the shortcut legend in the middle,
/// the Paste button on the right.
///
/// The legend text is still hardcoded — Phase 3E makes it read the user's key
/// bindings.
struct ActionBar: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager

    var body: some View {
        HStack(spacing: 12) {
            toggles

            Divider()
                .frame(height: 14)

            // Scrolls rather than pushing the Paste button off a narrow window.
            ScrollView(.horizontal, showsIndicators: false) {
                legend
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)
                .frame(maxWidth: 8)

            // Unchanged: the button pastes the focused item (Enter is what
            // pastes a whole multi-selection).
            PasteButton(action: {
                if let item = viewModel.selectedItem { viewModel.onPaste(item) }
            })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.barBackground)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Theme.separator),
            alignment: .top
        )
    }

    // MARK: - Left: layout toggles

    private var toggles: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(Theme.selectionSpring) { viewModel.toggleSidebar() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(Theme.icon(13))
                    .foregroundStyle(settings.sidebarCollapsed ? Color.secondary : Theme.accent)
            }
            .buttonStyle(.plain)
            .help(settings.sidebarCollapsed ? "Show sidebar" : "Hide sidebar")

            Button {
                withAnimation(Theme.selectionSpring) { viewModel.togglePreviewPane() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(Theme.icon(13))
                    .foregroundStyle(settings.showPreviewPane ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(settings.showPreviewPane ? "Hide preview" : "Show preview")
        }
    }

    // MARK: - Middle: shortcut legend

    @ViewBuilder
    private var legend: some View {
        if viewModel.isEditing {
            HStack(spacing: 10) {
                Text("Editing")
                    .font(.klip(.caption))
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                legendItem("Esc", "exit")
                legendItem("⌘E", "save")
            }
        } else {
            HStack(spacing: 10) {
                legendItem("↑↓", "navigate")
                legendItem("⌘↑↓", "multi-select")
                legendItem("⌘P", "pin")
                legendItem("⌘B", "star")
                if let item = viewModel.selectedItem, item.isEditable {
                    legendItem("⌘E", "edit")
                }
                if viewModel.selectedItem != nil {
                    legendItem("⌘S", "save to disk")
                }
                legendItem("⌘[ ]", "scope")
            }
            .lineLimit(1)
        }
    }

    private func legendItem(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.klip(.caption))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                )
            Text(label)
                .font(.klip(.caption))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
