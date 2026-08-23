import Foundation

// Covers `Services/ChangelogService.swift` — the pure Markdown parsing behind
// the in-app changelog window (3.1.0).
//
// Two kinds of test here. Most feed the parser a literal string, so they pin
// the block grammar without depending on the real file. The last two read the
// repo's actual `CHANGELOG.md` and `Info.plist`: the window is only useful if
// the shipped file parses and if the *running* version actually has a section
// in it. A release that bumps `CFBundleShortVersionString` and forgets the
// changelog entry would otherwise ship a "What's New" window with nothing to
// say about the version the user just installed — silent, and exactly the kind
// of thing a test should catch instead of a user.

enum ChangelogServiceTests {
    static let tests: [(String, () throws -> Void)] = [
        ("parse_splitsVersionSectionsAndKeepsNewestFirst", testParseSections),
        ("parse_readsVersionAndSubtitleFromTheHeading", testHeadingSplit),
        ("parse_foldsWrappedBulletContinuationLines", testWrappedBullets),
        ("parse_recognisesHeadingsBulletsParagraphsAndRules", testBlockKinds),
        ("parse_toleratesEmptyAndMalformedInput", testMalformed),
        ("entryLookup_acceptsBareAndTagPrefixedVersions", testVersionLookup),
        ("realChangelogFile_parsesIntoEntries", testRealFileParses),
        ("realChangelogFile_hasASectionForTheShippingVersion", testShippingVersionHasNotes),
    ]

    // MARK: - Fixtures

    private static let sample = """
    # Changelog

    Some preamble that belongs to no version.

    ---

    ## 3.1.0 (2026-08-23)

    ### Added

    - **A thing** - with a description that runs on
      across a second physical line and even
      a third.
    - A second, shorter bullet.

    ### Removed

    - Something that is gone.

    ---

    ## 3.0.4 (2026-08-22)

    ### Fixed

    - An older fix.
    """

    // MARK: - Tests

    private static func testParseSections() throws {
        let entries = ChangelogService.parse(sample)
        try expectEqual(entries.count, 2, "two ## sections")
        try expectEqual(entries[0].version, "3.1.0", "newest first, in file order")
        try expectEqual(entries[1].version, "3.0.4")
    }

    private static func testHeadingSplit() throws {
        let entries = ChangelogService.parse(sample)
        try expectEqual(entries[0].version, "3.1.0")
        try expectEqual(entries[0].subtitle, "2026-08-23", "the parenthesised date becomes the subtitle")
    }

    /// A bullet wrapped over several physical lines is one logical bullet. The
    /// real file wraps long entries, so getting this wrong would render every
    /// continuation line as its own stray bullet.
    private static func testWrappedBullets() throws {
        let entries = ChangelogService.parse(sample)
        let bullets = entries[0].blocks.compactMap { block -> String? in
            if case .bullet(let text) = block { return text }
            return nil
        }
        try expectEqual(bullets.count, 3, "two bullets under Added, one under Removed")
        try expect(
            bullets[0].contains("across a second physical line") && bullets[0].contains("a third"),
            "continuation lines folded into the first bullet, got: \(bullets[0])"
        )
        try expect(!bullets[1].contains("third"), "the short bullet did not absorb the previous one")
    }

    private static func testBlockKinds() throws {
        let entries = ChangelogService.parse(sample)
        let headings = entries[0].blocks.compactMap { block -> String? in
            if case .heading(let text) = block { return text }
            return nil
        }
        try expectEqual(headings, ["Added", "Removed"], "### subsection headings")

        // The trailing `---` separating entries belongs to neither section's
        // rendered body — it is a file-format separator, not content.
        let older = entries[1].blocks
        try expect(
            !older.contains(.rule) || older.last != .rule,
            "an entry should not end on a bare separator rule"
        )
    }

    private static func testMalformed() throws {
        try expectEqual(ChangelogService.parse("").count, 0, "empty input yields no entries")
        try expectEqual(
            ChangelogService.parse("no headings here, just prose").count, 0,
            "content with no ## section yields no entries"
        )
        // Must not crash or hang on a heading with nothing under it.
        let bare = ChangelogService.parse("## 9.9.9 (2030-01-01)\n")
        try expectEqual(bare.count, 1)
        try expectEqual(bare[0].version, "9.9.9")
    }

    /// Release tags in this repo have been `v3.0.3`, `klip-v3.0.4` and bare
    /// `3.0.2` at different points, so lookup normalises the prefix.
    private static func testVersionLookup() throws {
        let entries = ChangelogService.parse(sample)
        try expectNotNil(ChangelogService.entry(for: "3.1.0", in: entries), "bare version")
        try expectNotNil(ChangelogService.entry(for: "v3.1.0", in: entries), "v-prefixed tag")
        try expectNotNil(ChangelogService.entry(for: "klip-v3.1.0", in: entries), "klip-v tag")
        try expectNil(ChangelogService.entry(for: "0.0.1", in: entries), "unknown version")
    }

    // MARK: - The real files
    //
    // `scripts/run_tests.sh` cds to the repo root, so these are plain relative
    // reads. Bundle.main is the test binary here, not Klip.app, which is why
    // they do not go through `ChangelogService.bundledMarkdown()`.

    private static func testRealFileParses() throws {
        guard let markdown = try? String(contentsOfFile: "CHANGELOG.md", encoding: .utf8) else {
            throw TestFailure(message: "CHANGELOG.md not readable from the repo root", file: #file, line: #line)
        }
        let entries = ChangelogService.parse(markdown)
        try expect(entries.count >= 5, "the real changelog has several releases, got \(entries.count)")
        try expect(
            entries.allSatisfy { !$0.version.isEmpty && !$0.blocks.isEmpty },
            "every parsed entry has a version and a non-empty body"
        )
    }

    private static func testShippingVersionHasNotes() throws {
        guard let plist = NSDictionary(contentsOfFile: "Info.plist"),
              let version = plist["CFBundleShortVersionString"] as? String else {
            throw TestFailure(message: "could not read CFBundleShortVersionString", file: #file, line: #line)
        }
        guard let markdown = try? String(contentsOfFile: "CHANGELOG.md", encoding: .utf8) else {
            throw TestFailure(message: "CHANGELOG.md not readable from the repo root", file: #file, line: #line)
        }
        let entry = ChangelogService.entry(for: version, in: ChangelogService.parse(markdown))
        try expectNotNil(
            entry,
            "Info.plist ships \(version) but CHANGELOG.md has no '## \(version)' section — "
                + "the What's New window would open empty for anyone installing this build"
        )
    }
}
