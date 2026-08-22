import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// UI-side view of a clipboard item's semantic kind.
///
/// `ClipboardItem.kind` is `nil` for everything captured before Phase 3C's
/// detector exists, so the whole UI reads `displayKind` instead: it falls back
/// to the storage `type`, plus the one classification the list has always been
/// able to make locally (a pure CSS colour literal). Once 3C backfills `kind`,
/// this simply starts returning the stored value.
extension ClipboardItem {
    var displayKind: ContentKind {
        if let kind = kind { return kind }
        switch type {
        case .image: return .image
        case .file:  return .file
        case .text:
            return ColorSwatchParser.swatch(for: self) != nil ? .color : .text
        }
    }

    /// The colour swatch to draw for a `.color` item, if it parses.
    var swatchColor: Color? {
        ColorSwatchParser.swatch(for: self)
    }

    /// Icon for a `.file` item. Prefers Launch Services' icon for the actual
    /// file when the payload is reachable on disk; if it went missing (moved
    /// or deleted) this falls back to the generic icon for its extension/UTI,
    /// so a missing "Report.pdf" still reads as a pdf rather than a blank
    /// `doc`. `nil` only when there is no file information at all.
    func fileIcon(store: ClipboardStore) -> NSImage? {
        guard type == .file || isFile else { return nil }

        if let url = store.fileURLs(for: self).first, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        // Missing on disk — fall back to a generic icon from the UTI/extension.
        if let uti = fileAttachment?.uti, let type = UTType(uti) {
            return NSWorkspace.shared.icon(for: type)
        }
        let ext = (fileAttachment?.originalName as NSString?)?.pathExtension ?? ""
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: type)
        }
        return nil
    }
}
