import Foundation

/// Classifies clipboard content into a `ContentKind`, ported from Clipfield's
/// `Tagging/SmartTagger.swift` (see `docs/analysis/clipfield.md` §3).
///
/// Pure and fast: no I/O, no shared state, and every entry point is
/// `nonisolated` so it can run off the main actor (at capture time, and in
/// `ClipboardStore.backfillKindsIfNeeded()`'s background batch) despite the
/// project's `-default-isolation MainActor` build flag.
enum ContentDetector {

    /// Classifies a single string. Rules are evaluated, in order, on the
    /// *trimmed* text — the first match wins:
    ///  1. `.link`
    ///  2. `.email`
    ///  3. `.phone`
    ///  4. `.color`
    ///  5. `.code`
    ///  6. `.text` (default)
    nonisolated static func detect(text: String) -> ContentKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }

        if isLink(trimmed) { return .link }
        if isEmail(trimmed) { return .email }
        if isPhone(trimmed) { return .phone }
        if isColor(trimmed) { return .color }
        if isCode(trimmed) { return .code }
        return .text
    }

    /// Classifies a full clipboard item. Image and file items map directly;
    /// text items fall back to `detect(text:)` on `fullText` when given, or
    /// on the item's own stored `textContent` otherwise — for file-backed
    /// large text that stored value is already the 500-char inline preview
    /// (see `ClipboardWatcher.previewLength`), which is good enough for
    /// classification without reading the backing file.
    nonisolated static func detect(for item: ClipboardItem, fullText: String?) -> ContentKind {
        if item.isFile { return .file }
        switch item.type {
        case .image:
            return .image
        case .text:
            let text = fullText ?? item.textContent ?? ""
            return detect(text: text)
        }
    }

    // MARK: - Link

    /// Single line, and either an `NSDataDetector` link match spanning the
    /// *entire* string, or (as a fallback when the detector finds nothing at
    /// all) an explicit `http://`/`https://`/`ftp://`/`www.<dot>` prefix.
    /// `mailto:` is deliberately excluded — it is classified as `.email`
    /// instead (see `isEmail`), matching Clipfield's `SmartTagger`, which
    /// tags a mailto link as `.email` rather than `.link`.
    ///
    /// A detector match that does *not* span the whole string (e.g. a URL
    /// embedded in a sentence, or with trailing sentence punctuation the
    /// detector excludes from the match) means the text is not purely a
    /// link, so it is **not** treated as one — it falls through to the
    /// remaining rules instead.
    private nonisolated static func isLink(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(where: { $0.isNewline }) else { return false }
        let lower = text.lowercased()
        guard !lower.hasPrefix("mailto:") else { return false }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, options: [], range: range) {
                if match.range == range, match.url?.scheme != "mailto" {
                    return true
                }
                return false
            }
        }

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("ftp://") {
            return true
        }
        if lower.hasPrefix("www.") && lower.dropFirst(4).contains(".") {
            return true
        }
        return false
    }

    // MARK: - Email

    private nonisolated static let emailPattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"

    /// The whole string matches a standard email regex, or is a `mailto:`
    /// URI wrapping one (excluded from `.link` above, so it lands here).
    private nonisolated static func isEmail(_ text: String) -> Bool {
        if matchesWhole(text, emailPattern, options: [.caseInsensitive]) { return true }
        if text.lowercased().hasPrefix("mailto:") {
            let remainder = String(text.dropFirst("mailto:".count))
            return matchesWhole(remainder, emailPattern, options: [.caseInsensitive])
        }
        return false
    }

    // MARK: - Phone

    /// An `NSDataDetector` phone-number match spanning the entire string,
    /// whose length falls within 7-20 characters (short numeric fragments
    /// and long prose containing a number are excluded either by length or
    /// because the match cannot span the whole string).
    private nonisolated static func isPhone(_ text: String) -> Bool {
        guard text.count >= 7, text.count <= 20 else { return false }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else { return false }
        return match.range == range
    }

    // MARK: - Color

    private nonisolated static let hexColorPattern = "^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$"
    private nonisolated static let functionalColorPattern = "^(rgb|rgba|hsl|hsla)\\(.+\\)$"

    private nonisolated static func isColor(_ text: String) -> Bool {
        guard text.count <= 64 else { return false }
        return matchesWhole(text, hexColorPattern, options: [.caseInsensitive])
            || matchesWhole(text, functionalColorPattern, options: [.caseInsensitive])
    }

    // MARK: - Code

    /// Ported from Clipfield's `looksLikeCode`. A single short line is never
    /// code unless it looks like a shell command (`$ `, `git `, `npm `,
    /// `brew `, `curl `, `ssh `). Multi-line text needs real structural
    /// evidence — a valid JSON object/array, a `SELECT ... FROM` query, or a
    /// brace/semicolon/arrow-style symbol together with either a language
    /// keyword or two-or-more indented lines — so ordinary prose (which may
    /// happen to contain a word like "class" or "return") is never flagged.
    private nonisolated static func isCode(_ text: String) -> Bool {
        let shellPrefixes = ["$ ", "git ", "npm ", "brew ", "curl ", "ssh "]
        let isMultiline = text.contains("\n")

        guard isMultiline else {
            return shellPrefixes.contains { text.hasPrefix($0) }
        }

        if looksLikeJSON(text) { return true }
        if hasSQLSelectFrom(text) { return true }

        let symbols = ["{", "}", ";", "=>", "->", "::", "()"]
        let keywords = [
            "func ", "def ", "class ", "import ", "return ", "const ", "let ", "var ",
            "public ", "private ", "function ", "#include", "package ", "struct ", "enum "
        ]
        let hasSymbol = symbols.contains { text.contains($0) }
        let hasKeyword = keywords.contains { text.contains($0) }

        let lines = text.components(separatedBy: "\n")
        let indentedLineCount = lines.filter { line in
            guard let first = line.first, first == " " || first == "\t" else { return false }
            return !line.trimmingCharacters(in: .whitespaces).isEmpty
        }.count
        let hasIndentation = indentedLineCount >= 2

        return hasSymbol && (hasKeyword || hasIndentation)
    }

    private nonisolated static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isObject = trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
        let isArray = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        guard isObject || isArray, let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private nonisolated static func hasSQLSelectFrom(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\bSELECT\\b[\\s\\S]*?\\bFROM\\b", options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // MARK: - Regex helper

    private nonisolated static func matchesWhole(
        _ text: String,
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
