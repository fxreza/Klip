import AppKit
import SwiftUI
import Quartz
import QuickLookThumbnailing

/// Thumbnail cache + QuickLook preview plumbing for `.file` items (Phase 3F).
///
/// Two different QuickLook APIs, for two different jobs:
/// - `QLThumbnailGenerator` (QuickLookThumbnailing) renders a small static
///   raster thumbnail — cheap enough to ask for on every row in a scrolling
///   list (`ClipRow`'s 38×38 badge) and reused as a nicer stand-in image
///   inside the preview pane's fallback card (240 pt) when a live preview
///   isn't shown.
/// - `QLPreviewView` (Quartz/QuickLookUI, wrapped below as
///   `FileQuickLookView`) renders the real, interactive preview — pdf, csv,
///   txt, code, images and office docs all preview natively — and is what
///   `PreviewPane.fileBody` shows for the first file when it exists on disk.
enum FilePreview {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    /// Plain `String` (Sendable) rather than `NSString` — bridged to `NSString`
    /// only at the point of each cache call, so it can be captured directly
    /// in the `@Sendable` completion handler below without a warning.
    private static func cacheKey(itemID: UUID, size: CGFloat) -> String {
        "\(itemID.uuidString)#\(Int(size))"
    }

    /// Async thumbnail for `url`, cached by item id + size so the same row
    /// never re-renders one twice. Returns `nil` when QuickLook has nothing
    /// to offer for this file type — callers fall back to `fileIcon(store:)`.
    static func thumbnail(for url: URL, itemID: UUID, size: CGFloat) async -> NSImage? {
        let key = cacheKey(itemID: itemID, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let representation else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = representation.nsImage
                cache.setObject(image, forKey: key as NSString)
                continuation.resume(returning: image)
            }
        }
    }
}

/// Live QuickLook preview of a single file — the same rendering QuickLook
/// (space bar in Finder) uses, embedded in the preview pane.
struct FileQuickLookView: NSViewRepresentable {
    let url: URL

    /// `QLPreviewView(frame:style:)` is failable. It does not fail in
    /// practice for `.normal` style, but force-unwrapping it made a preview
    /// of a `.file` clip an unrecoverable crash if it ever did (5A-32), so a
    /// plain `NSView` stands in and the pane simply renders empty.
    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: .zero, style: .normal) else {
            return NSView(frame: .zero)
        }
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let preview = nsView as? QLPreviewView else { return }
        guard preview.previewItem?.previewItemURL != url else { return }
        preview.previewItem = url as QLPreviewItem
    }
}
