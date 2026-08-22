import Foundation

// Ported from BufferTests/ClipboardItemTests.swift (the Xcode XCTest target,
// left untouched) plus new coverage for the JSON forward-compat contract
// described in docs/analysis/buffer.md section 2.

enum ClipboardItemTests {
    static let tests: [(String, () throws -> Void)] = [
        ("equatable_onOcrText_isPinned_isBookmarked_tags", testEquatable),
        ("jsonRoundTrip_textItem_preservesAllFields", testJSONRoundTripText),
        ("jsonRoundTrip_imageItem_preservesAllFields", testJSONRoundTripImage),
        ("decode_missingOptionalFields_usesDefaults", testDecodeMissingOptionalFields),
        ("previewText_capsAt200Chars", testPreviewTextCap),
        ("isEditable_falseAbove5000Chars", testIsEditableLimit),
    ]

    // MARK: - Ported from BufferTests

    static func testEquatable() throws {
        let id = UUID()
        let timestamp = Date()

        let item1 = ClipboardItem(
            id: id, type: .image, timestamp: timestamp,
            isPinned: false, isBookmarked: false, tags: [], ocrText: nil
        )

        // Item with updated OCR text
        let itemWithOCR = ClipboardItem(
            id: id, type: .image, timestamp: timestamp,
            isPinned: false, isBookmarked: false, tags: [], ocrText: "extracted text"
        )

        // Item with updated pin state
        let itemPinned = ClipboardItem(
            id: id, type: .image, timestamp: timestamp,
            isPinned: true, isBookmarked: false, tags: [], ocrText: nil
        )

        // Item with updated bookmark state
        let itemBookmarked = ClipboardItem(
            id: id, type: .image, timestamp: timestamp,
            isPinned: false, isBookmarked: true, tags: [], ocrText: nil
        )

        // Item with updated tags
        let itemWithTags = ClipboardItem(
            id: id, type: .image, timestamp: timestamp,
            isPinned: false, isBookmarked: false, tags: ["tag1"], ocrText: nil
        )

        try expect(item1 != itemWithOCR, "items with different ocrText should not be equal")
        try expect(item1 != itemPinned, "items with different isPinned should not be equal")
        try expect(item1 != itemBookmarked, "items with different isBookmarked should not be equal")
        try expect(item1 != itemWithTags, "items with different tags should not be equal")
        try expectEqual(item1, item1, "identical items should be equal")
    }

    // MARK: - JSON round-trip

    static func testJSONRoundTripText() throws {
        let original = ClipboardItem(
            id: UUID(),
            type: .text,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceApp: "TextEdit",
            textContent: "hello world",
            textFilename: "texts/abc.txt",
            imageFilename: nil,
            isPinned: true,
            isBookmarked: true,
            tags: ["work", "urgent"],
            ocrText: "hello ocr",
            isTruncated: false,
            originalSizeBytes: 12345
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        try expectEqual(decoded, original, "decoded .text item should equal the original")
        try expectEqual(decoded.sourceApp, original.sourceApp, "sourceApp should round-trip")
        try expectEqual(decoded.textContent, original.textContent, "textContent should round-trip")
        try expectEqual(decoded.textFilename, original.textFilename, "textFilename should round-trip")
        try expectEqual(decoded.imageFilename, original.imageFilename, "imageFilename should round-trip")
        try expectEqual(decoded.isTruncated, original.isTruncated, "isTruncated should round-trip")
        try expectEqual(decoded.originalSizeBytes, original.originalSizeBytes, "originalSizeBytes should round-trip")
        try expectEqual(decoded.timestamp, original.timestamp, "timestamp should round-trip")
    }

    static func testJSONRoundTripImage() throws {
        let original = ClipboardItem(
            id: UUID(),
            type: .image,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500),
            sourceApp: "Preview",
            textContent: nil,
            textFilename: nil,
            imageFilename: "images/def.png",
            isPinned: false,
            isBookmarked: true,
            tags: ["screenshot"],
            ocrText: nil,
            isTruncated: false,
            originalSizeBytes: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        try expectEqual(decoded, original, "decoded .image item should equal the original")
        try expectEqual(decoded.imageFilename, original.imageFilename, "imageFilename should round-trip")
        try expectEqual(decoded.tags, original.tags, "tags should round-trip")
        try expectNil(decoded.textContent, "textContent should stay nil for an image item")
        try expectNil(decoded.originalSizeBytes, "originalSizeBytes should stay nil when absent")
    }

    // MARK: - Forward-compat contract (buffer.md section 2)

    static func testDecodeMissingOptionalFields() throws {
        let id = UUID()
        // Simulates a history.json entry written before isPinned/isBookmarked/
        // tags/ocrText existed. Decoding must succeed and fall back to defaults
        // rather than throwing or discarding the whole history file.
        let json = """
        {
            "id": "\(id.uuidString)",
            "type": "text",
            "timestamp": 1700000000,
            "textContent": "legacy item with no optional fields"
        }
        """
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: Data(json.utf8))

        try expectEqual(decoded.id, id, "id should decode correctly")
        try expectEqual(decoded.textContent, "legacy item with no optional fields", "textContent should decode correctly")
        try expectEqual(decoded.isPinned, false, "missing isPinned should default to false")
        try expectEqual(decoded.isBookmarked, false, "missing isBookmarked should default to false")
        try expectEqual(decoded.tags, [], "missing tags should default to an empty array")
        try expectNil(decoded.ocrText, "missing ocrText should default to nil")
    }

    // MARK: - Computed properties

    static func testPreviewTextCap() throws {
        let longText = String(repeating: "a", count: 250)
        let item = ClipboardItem.text(longText)

        try expectEqual(item.previewText.count, 201, "previewText should cap at 200 chars plus an ellipsis")
        try expect(item.previewText.hasSuffix("\u{2026}"), "previewText over 200 chars should end with an ellipsis")
        try expectEqual(String(item.previewText.dropLast()), String(longText.prefix(200)), "previewText body should be the first 200 chars")

        let shortText = String(repeating: "b", count: 50)
        let shortItem = ClipboardItem.text(shortText)
        try expectEqual(shortItem.previewText, shortText, "previewText should not truncate text under the cap")
    }

    static func testIsEditableLimit() throws {
        let overLimit = ClipboardItem.text(String(repeating: "x", count: 5001))
        try expect(!overLimit.isEditable, "text item over 5000 chars should not be editable")

        let atLimit = ClipboardItem.text(String(repeating: "x", count: 5000))
        try expect(atLimit.isEditable, "text item at exactly 5000 chars should be editable")

        let shortItem = ClipboardItem.text("short")
        try expect(shortItem.isEditable, "short text item should be editable")
    }
}
