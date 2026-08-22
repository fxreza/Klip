import Cocoa
import UniformTypeIdentifiers

/// Handles pasting content into the frontmost application
class PasteController {
    
    /// Get or create temp directory for paste operations
    private static func getTempDirectory() -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("BufferPaste")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    /// Save image with proper filename and return file URL
    private static func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        guard let tempDir = getTempDirectory() else { return nil }
        
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
            return fileURL
        }
        return nil
    }
    
    /// Copy item content back to system clipboard
    static func copyToClipboard(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            // Use full text from file if file-backed, otherwise use inline content
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        case .file:
            writeFileURLs(for: [item], store: store, to: pasteboard)
        }
    }

    /// Write file items' payloads onto the pasteboard as file URLs, so the
    /// receiving app copies/attaches the files. Phase 3F refines this (file
    /// promises, security-scoped bookmarks, per-file stored paths).
    @discardableResult
    private static func writeFileURLs(for items: [ClipboardItem], store: ClipboardStore, to pasteboard: NSPasteboard) -> Bool {
        let urls = items.flatMap { store.fileURLs(for: $0) }
        guard !urls.isEmpty else { return false }
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        return true
    }
    
    /// Paste item into the frontmost application
    static func paste(_ item: ClipboardItem, store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item) {
                // Save image to temp with proper name
                if let fileURL = saveImageToTemp(image, fileName: "image-0001.png") {
                    pasteboard.writeObjects([fileURL as NSPasteboardWriting])
                } else {
                    // Fallback to TIFF if file save fails
                    if let tiffData = image.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                }
            }
        case .file:
            writeFileURLs(for: [item], store: store, to: pasteboard)
        }

        // Reactivate previous app, then simulate paste after it has focus
        previousApp?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Post ignore notification right before paste
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            simulatePaste()
        }
    }
    
    /// Paste multiple items into the frontmost application
    /// Text items are joined with newlines; images and files go out together as
    /// file URLs (like a Finder multi-select).
    static func pasteMultiple(_ items: [ClipboardItem], store: ClipboardStore, previousApp: NSRunningApplication? = nil) {
        guard !items.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // Separate items by type
        let textItems = items.filter { $0.type == .text }
        let imageItems = items.filter { $0.type == .image }
        let fileItems = items.filter { $0.type == .file }
        let hasURLItems = !imageItems.isEmpty || !fileItems.isEmpty

        /// Writes every image (as a PNG in the temp dir) and every file payload
        /// onto the pasteboard as one batch of file URLs, then pastes.
        func writeURLBatchAndPaste() {
            pasteboard.clearContents()

            var urls: [URL] = []
            for (index, imageItem) in imageItems.enumerated() {
                if let image = store.image(for: imageItem) {
                    let paddedNumber = String(format: "%04d", index + 1)
                    let fileName = "image-\(paddedNumber).png"
                    if let fileURL = saveImageToTemp(image, fileName: fileName) {
                        urls.append(fileURL)
                    }
                }
            }
            urls.append(contentsOf: fileItems.flatMap { store.fileURLs(for: $0) })

            if !urls.isEmpty {
                pasteboard.writeObjects(urls.map { $0 as NSURL })
                simulatePasteWithCustomDelay(0.05)
            }
        }

        // If we have text items, paste them first
        if !textItems.isEmpty {
            pasteboard.clearContents()
            let joinedText = textItems.compactMap { store.fullText(for: $0) }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)

            // If all items are text, paste once and done
            if !hasURLItems {
                previousApp?.activate(options: .activateIgnoringOtherApps)
                simulatePasteWithCustomDelay(0.1)
                return
            }

            // Paste text first, then images/files together after
            previousApp?.activate(options: .activateIgnoringOtherApps)
            simulatePasteWithCustomDelay(0.1)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                writeURLBatchAndPaste()
            }
        } else if hasURLItems {
            // Images/files only - paste all together at once (like Finder multi-select)
            previousApp?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                writeURLBatchAndPaste()
            }
        }
    }
    
    /// Simulate Command + V keystroke
    private static func simulatePaste() {
        // Content is already on the pasteboard by the time this runs (today's
        // behavior, unchanged) — without Accessibility access the synthesized
        // ⌘V below won't reach the frontmost app, so let the UI know it still
        // needs a manual ⌘V.
        if !AXIsProcessTrusted() {
            NotificationCenter.default.post(name: .klipPasteNeedsAccessibility, object: nil)
        }

        let source = CGEventSource(stateID: .hidSystemState)
        
        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        
        // Add Command modifier
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        // Post the events
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
    
    /// Simulate Command + V keystroke with custom delay
    private static func simulatePasteWithCustomDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Post ignore notification right before paste
            NotificationCenter.default.post(name: .bufferIgnoreNextChange, object: nil)
            simulatePaste()
        }
    }
    
    /// Save an image to disk using NSSavePanel
    static func saveImageToDisk(_ image: NSImage) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            
            panel.nameFieldStringValue = "Image-\(timestamp)"
            panel.canCreateDirectories = true
            
            if panel.runModal() == .OK, let url = panel.url {
                guard let tiffData = image.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                    print("[Buffer] Failed to create PNG data from image")
                    return
                }
                
                do {
                    try pngData.write(to: url)
                } catch {
                    print("[Buffer] Failed to save image to disk: \(error)")
                }
            }
        }
    }
}
