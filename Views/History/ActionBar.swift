import SwiftUI

/// Bottom bar: up/down navigation buttons, the static shortcut legend and the
/// Paste button.
struct ActionBar: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Navigate buttons - minimal, elegant
            HStack(spacing: 6) {
                Button(action: { viewModel.navigateDown() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.navigateUp() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }

            if viewModel.isEditing {
                Text("Editing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)

                Color.primary.opacity(0.1)
                    .frame(width: 2, height: 14)

                HStack(spacing: 4) {
                    Text("Esc")
                        .font(.system(size: 10))
                    Text("exit")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary.opacity(0.6))

                HStack(spacing: 4) {
                    Text("⌘E")
                        .font(.system(size: 10))
                    Text("save")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.leading, 4)
            } else {
                Text("Navigate")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.8))

                Color.primary.opacity(0.1)
                    .frame(width: 2, height: 14)

                HStack(spacing: 4) {
                    Text("⌘↑↓")
                        .font(.system(size: 10))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                    Text("multi-select")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                HStack(spacing: 4) {
                    Text("⌘P")
                        .font(.system(size: 10))
                    Text("pin")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.leading, 8)

                HStack(spacing: 4) {
                    Text("⌘B")
                        .font(.system(size: 10))
                    Text("save")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.leading, 4)

                if let item = viewModel.selectedItem, item.isEditable {
                    HStack(spacing: 4) {
                        Text("⌘E")
                            .font(.system(size: 10))
                        Text("edit")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 4)
                }

                if viewModel.selectedItem?.type == .image {
                    HStack(spacing: 4) {
                        Text("⌘S")
                            .font(.system(size: 10))
                        Text("save")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 4)
                }
            }

            Spacer()

            PasteButton(action: { if let item = viewModel.selectedItem { viewModel.onPaste(item) } })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color.primary.opacity(0.15)),
                    alignment: .top
                )
        )
    }
}
