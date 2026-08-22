import SwiftUI

/// Inline folder prompts rendered inside the panel (never `NSAlert` — see
/// `PromptCard`).
///
/// Only **New Folder** exists in Phase 2A. Phase 3B adds `RenameFolderPrompt`
/// and `DeleteFolderPrompt` here (rename via double-click / context menu;
/// delete with the "move N clips to All" vs "delete N clips (M locked)"
/// choice), reusing `PromptCard` and this file's field styling.
struct NewFolderPrompt: View {
    @ObservedObject var viewModel: HistoryViewModel
    @FocusState.Binding var isFieldFocused: Bool

    var body: some View {
        PromptCard(width: 280, onDismiss: { viewModel.cancelNewFolder() }) {
            Label("New Folder", systemImage: "folder.badge.plus")
                .font(.klip(.sidebarTitle))

            TextField("Folder name", text: $viewModel.newFolderName)
                .textFieldStyle(.plain)
                .font(.klip(.preview))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
                .focused($isFieldFocused)
                .onSubmit { viewModel.confirmNewFolder() }

            HStack(spacing: 10) {
                Spacer()
                PromptButton(title: "Cancel", isProminent: false) {
                    viewModel.cancelNewFolder()
                }
                PromptButton(title: "Create", isProminent: true) {
                    viewModel.confirmNewFolder()
                }
                .disabled(viewModel.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            // One run loop later, so the field is in the hierarchy first.
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }
}

/// Small pill button used inside `PromptCard`s. `.borderedProminent` would pull
/// in the system control background, which reads wrong on the material panel.
struct PromptButton: View {
    let title: String
    var isProminent: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.klip(.chip))
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    if isProminent {
                        Capsule().fill(Theme.accentGradient)
                    } else {
                        Capsule().fill(Theme.chipInactive)
                    }
                }
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
