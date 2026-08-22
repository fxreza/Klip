import Foundation
import AppKit

/// Represents a single item in the clipboard history
///
/// Every field added after v2.5.0 is optional or defaulted and decoded with
/// `decodeIfPresent`, so an existing `history.json` loads unchanged. Unknown
/// keys are ignored by `JSONDecoder`, so removed fields (`isTruncated`,
/// `originalSizeBytes`) do not break old files either.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceApp: String?

    // For text items — inline content (nil for file-backed large text)
    var textContent: String?

    // For large text items — filename reference (stored separately, like images)
    let textFilename: String?

    // For image items — filename reference (stored separately)
    let imageFilename: String?

    // Pin state (protected + floats to top)
    var isPinned: Bool = false

    // Bookmark state (protected, stays in chronological position)
    var isBookmarked: Bool = false

    // User-defined tags
    var tags: [String] = []

    // Extracted OCR text (persisted after first extraction)
    var ocrText: String?

    /// Lock state — a locked item can never be deleted or evicted.
    var isLocked: Bool = false

    /// Folder membership, `nil` when the item is loose in the history.
    var folderID: UUID? = nil

    /// Detected semantic kind. `nil` means "not yet detected" (detection is
    /// Phase 3C), not "plain text".
    var kind: ContentKind? = nil

    /// File payload, when this item came from copied files.
    var fileAttachment: FileAttachment? = nil

    /// Filename of the RTF flavor under `texts/` (reserved for Phase 3D).
    var rtfFilename: String? = nil

    /// Filename of the archived pasteboard flavors under `flavors/`
    /// (reserved for Phase 3D).
    var flavorsFilename: String? = nil

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        textContent: String? = nil,
        textFilename: String? = nil,
        imageFilename: String? = nil,
        isPinned: Bool = false,
        isBookmarked: Bool = false,
        tags: [String] = [],
        ocrText: String? = nil,
        isLocked: Bool = false,
        folderID: UUID? = nil,
        kind: ContentKind? = nil,
        fileAttachment: FileAttachment? = nil,
        rtfFilename: String? = nil,
        flavorsFilename: String? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.textContent = textContent
        self.textFilename = textFilename
        self.imageFilename = imageFilename
        self.isPinned = isPinned
        self.isBookmarked = isBookmarked
        self.tags = tags
        self.ocrText = ocrText
        self.isLocked = isLocked
        self.folderID = folderID
        self.kind = kind
        self.fileAttachment = fileAttachment
        self.rtfFilename = rtfFilename
        self.flavorsFilename = flavorsFilename
    }

    enum CodingKeys: String, CodingKey {
        case id, type, timestamp, sourceApp, textContent, textFilename, imageFilename
        case isPinned, isBookmarked, tags, ocrText
        case isLocked, folderID, kind, fileAttachment, rtfFilename, flavorsFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.type = try container.decode(ClipboardItemType.self, forKey: .type)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.textContent = try container.decodeIfPresent(String.self, forKey: .textContent)
        self.textFilename = try container.decodeIfPresent(String.self, forKey: .textFilename)
        self.imageFilename = try container.decodeIfPresent(String.self, forKey: .imageFilename)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isBookmarked = try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        self.kind = try container.decodeIfPresent(ContentKind.self, forKey: .kind)
        self.fileAttachment = try container.decodeIfPresent(FileAttachment.self, forKey: .fileAttachment)
        self.rtfFilename = try container.decodeIfPresent(String.self, forKey: .rtfFilename)
        self.flavorsFilename = try container.decodeIfPresent(String.self, forKey: .flavorsFilename)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(textFilename, forKey: .textFilename)
        try container.encodeIfPresent(imageFilename, forKey: .imageFilename)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isBookmarked, forKey: .isBookmarked)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(folderID, forKey: .folderID)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(fileAttachment, forKey: .fileAttachment)
        try container.encodeIfPresent(rtfFilename, forKey: .rtfFilename)
        try container.encodeIfPresent(flavorsFilename, forKey: .flavorsFilename)
    }

    /// Create a text clipboard item
    static func text(_ content: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: content
        )
    }

    /// Create an image clipboard item
    static func image(filename: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .image,
            sourceApp: sourceApp,
            imageFilename: filename
        )
    }

    /// Create a file clipboard item. Capture of files is Phase 3F; this factory
    /// exists so the `.file` case has a canonical construction path.
    static func file(attachment: FileAttachment, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .file,
            sourceApp: sourceApp,
            kind: .file,
            fileAttachment: attachment
        )
    }

    /// Create a large text clipboard item (file-backed with inline preview)
    static func largeText(preview: String, filename: String, sourceApp: String? = nil) -> ClipboardItem {
        ClipboardItem(
            type: .text,
            sourceApp: sourceApp,
            textContent: preview,
            textFilename: filename
        )
    }

    /// Whether this item's full text is stored in a separate file
    var isFileBacked: Bool {
        textFilename != nil
    }

    /// Whether this item carries a file payload.
    ///
    /// `ClipboardItemType.file` is deliberately not added yet — it would break
    /// exhaustive switches in the view files currently being split. The enum
    /// case arrives at integration; until then this is the check to use.
    var isFile: Bool {
        fileAttachment != nil
    }

    /// Protected from **eviction** (the history-limit trim). Deletion is a
    /// separate, stricter rule: only `isLocked` blocks an explicit delete.
    var isProtected: Bool {
        isPinned || isBookmarked || !tags.isEmpty || isLocked || folderID != nil
    }

    /// Whether this item is editable inline
    var isEditable: Bool {
        type == .text && !isFileBacked && !isFile && (textContent?.count ?? 0) <= 5000
    }

    /// Preview text for display (truncated for long content)
    var previewText: String {
        if let attachment = fileAttachment {
            let extra = attachment.additionalNames.count
            return extra > 0 ? "\(attachment.originalName) +\(extra)" : attachment.originalName
        }
        switch type {
        case .text:
            let text = textContent ?? ""
            if text.count > 200 {
                return String(text.prefix(200)) + "…"
            }
            return text
        case .image:
            return "Image"
        case .file:
            return fileAttachment?.originalName ?? "File"
        }
    }

    /// Content hash for duplicate detection
    var contentHash: Int {
        if let attachment = fileAttachment {
            return (attachment.storedRelativePath ?? attachment.referencePath ?? attachment.originalName).hashValue
        }
        switch type {
        case .text:
            return textContent?.hashValue ?? 0
        case .image:
            return imageFilename?.hashValue ?? 0
        case .file:
            return fileAttachment?.originalName.hashValue ?? 0
        }
    }


}

enum ClipboardItemType: String, Codable {
    case text
    case image
    /// One or more files copied from Finder. The payload lives in
    /// `ClipboardItem.fileAttachment`; capture is Phase 3F.
    case file
}
