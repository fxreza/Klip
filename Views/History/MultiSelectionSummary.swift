import SwiftUI

/// Detail-pane content shown when more than one item is selected:
/// counts, total size, type breakdown, Download All, first-item preview and
/// the inline delete confirmation.
struct MultiSelectionSummary: View {
    @ObservedObject var viewModel: HistoryViewModel

    @State private var isDeleteHovered = false

    var body: some View {
        let selectionCount = viewModel.selectionCount
        let selectedItems = viewModel.selectedItems

        VStack(alignment: .leading, spacing: 12) {
            // Count breakdown
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Items")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("\(selectionCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(viewModel.formattedByteCount(viewModel.selectedItemsTotalSize))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }

                Spacer()
            }

            Divider()

            // Type breakdown
            let textCount = selectedItems.filter { $0.type == .text }.count
            let imageCount = selectedItems.filter { $0.type == .image }.count

            VStack(alignment: .leading, spacing: 8) {
                if textCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text("\(textCount) text \(textCount == 1 ? "item" : "items")")
                            .font(.system(size: 12))
                    }
                }

                if imageCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text("\(imageCount) image \(imageCount == 1 ? "item" : "items")")
                            .font(.system(size: 12))
                    }
                }
            }

            Divider()

            // Download All Images button (only show if all selected items are images)
            if textCount == 0 && imageCount > 0 {
                Button(action: { viewModel.downloadAllImages() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download All (\(imageCount))")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider()
            }

            // First selected item preview (optional)
            if let firstItem = selectedItems.first, firstItem.type == .text {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First item preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))

                    let preview = (firstItem.textContent ?? "").prefix(200)
                    Text(String(preview))
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(4)
                        .truncationMode(.tail)
                }
            }

            Divider()

            if viewModel.showDeleteConfirmation {
                // Inline confirmation — avoids NSPanel key-resign issue with .alert
                VStack(spacing: 8) {
                    Text("Delete \(selectionCount) items permanently?")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))

                    HStack(spacing: 10) {
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                viewModel.showDeleteConfirmation = false
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)

                        Button(action: {
                            viewModel.deleteSelectedItems()
                            viewModel.showDeleteConfirmation = false
                        }) {
                            Text("Delete")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.red.opacity(0.85))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        viewModel.showDeleteConfirmation = true
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Delete \(selectionCount) Items...")
                    }
                    .foregroundColor(isDeleteHovered ? .red : .secondary.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .onHover { hovering in
                    isDeleteHovered = hovering
                }
                .transition(.opacity)
            }
        }
    }
}
