import SwiftUI

// MARK: - Inline Markdown

/// Renders one line of inline Markdown (`**bold**`, `` `code` ``, links).
///
/// `AttributedString(markdown:)` on macOS 13 only handles *inline* syntax, and
/// its default options collapse runs of whitespace and strip leading spaces —
/// which mangles a bullet that starts with an indented fragment. The
/// `.inlineOnlyPreservingWhitespace` variant keeps the text as written and
/// leaves any block syntax alone, which is exactly the division of labour we
/// want: `ChangelogService` owns the blocks, this owns the spans.
///
/// A string the parser cannot digest (an unbalanced backtick, a stray `[`)
/// degrades to plain text rather than throwing — a broken changelog must never
/// be the reason the window is empty.
struct MarkdownText: View {
    let source: String

    var body: some View {
        Text(Self.attributed(source))
    }

    static func attributed(_ source: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(source)
        }
    }
}

// MARK: - Blocks

/// Renders the blocks `ChangelogService` produced.
private struct ChangelogBlocksView: View {
    let blocks: [ChangelogBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text):
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)

                case .bullet(let text):
                    // .firstTextBaseline so the dot sits on the first line of a
                    // bullet that wraps to four or five lines, not centred
                    // against the whole paragraph.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        MarkdownText(source: text)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                case .paragraph(let text):
                    MarkdownText(source: text)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .rule:
                    Divider().padding(.vertical, 4)
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - One entry

private struct ChangelogEntryView: View {
    let entry: ChangelogEntry
    /// The entry for the version that is actually running gets the larger,
    /// full-strength heading; older ones are visually demoted so the scroll
    /// reads as "what just changed, then history".
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.version)
                    .font(.system(size: isCurrent ? 20 : 15, weight: .bold))
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Text("Installed")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            ChangelogBlocksView(blocks: entry.blocks)
                .opacity(isCurrent ? 1 : 0.86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Window content

/// The "What's New" window's content.
///
/// Replaces the old behaviour where the post-update toast's "What's New →"
/// button called `NSWorkspace.open` on the GitHub release page: the notes ship
/// inside the bundle now, so reading them does not mean leaving the app (and
/// works offline). The GitHub link survives as a quiet footer escape hatch for
/// anyone who wants the full release page.
struct ChangelogView: View {
    /// Newest first. Empty is a legitimate state (no bundled changelog).
    let entries: [ChangelogEntry]
    /// The running app's `CFBundleShortVersionString`; highlighted and sorted
    /// to the top if it is present in `entries`.
    let currentVersion: String
    /// The release notes GitHub handed us for the version that just installed.
    /// Only used when `entries` has nothing for `currentVersion`.
    let fallbackNotes: String?
    /// Where "View on GitHub" goes.
    let githubURL: URL

    /// The current version's entry hoisted to the front, everything else after
    /// it in file order.
    private var orderedEntries: [ChangelogEntry] {
        guard let current = ChangelogService.entry(for: currentVersion, in: entries) else {
            return entries
        }
        return [current] + entries.filter { $0.version != current.version }
    }

    private var currentEntry: ChangelogEntry? {
        ChangelogService.entry(for: currentVersion, in: entries)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        if currentEntry == nil, let fallback = fallbackNotes, !fallback.isEmpty {
                            fallbackSection(fallback)
                            Divider()
                        }
                        ForEach(Array(orderedEntries.enumerated()), id: \.offset) { index, entry in
                            ChangelogEntryView(
                                entry: entry,
                                isCurrent: entry.version == currentEntry?.version
                            )
                            if index < orderedEntries.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Link("View on GitHub", destination: githubURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// Shown when the running version has no section in the bundled changelog —
    /// an out-of-band build, or a bundle assembled without the copy step. The
    /// notes GitHub returned with the release are the next best thing.
    private func fallbackSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentVersion.isEmpty ? "What's New" : currentVersion)
                    .font(.system(size: 20, weight: .bold))
                Text("release notes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ChangelogBlocksView(blocks: ChangelogService.blocks(fromMarkdown: notes))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentVersion.isEmpty ? "Klip" : "Klip \(currentVersion)")
                .font(.system(size: 20, weight: .bold))
            if let fallback = fallbackNotes, !fallback.isEmpty {
                ChangelogBlocksView(blocks: ChangelogService.blocks(fromMarkdown: fallback))
            } else {
                Text("The release notes for this build were not included in the app. They are on the release page on GitHub.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
