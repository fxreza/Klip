import AppKit
import SwiftUI

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

    /// Icon for a `.file` item, taken from Launch Services when the payload is
    /// reachable on disk. `nil` → the caller draws the generic `doc` glyph.
    func fileIcon(store: ClipboardStore) -> NSImage? {
        guard type == .file || isFile else { return nil }
        guard let url = store.fileURLs(for: self).first else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
