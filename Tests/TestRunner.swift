import Foundation

// Minimal dependency-free test framework (no XCTest). See scripts/run_tests.sh
// and docs/analysis/buffer.md section 5.

// MARK: - Failure type

struct TestFailure: Error {
    let message: String
    let file: StaticString
    let line: UInt
}

// MARK: - Expectations
//
// A failed expectation throws a `TestFailure`, which the runner below catches
// per-test — one failure never aborts the remaining tests or suites.

func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) throws {
    if !condition {
        throw TestFailure(message: message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    if a != b {
        let detail = "\(a) != \(b)"
        let full = message.isEmpty ? detail : "\(message) (\(detail))"
        throw TestFailure(message: full, file: file, line: line)
    }
}

func expectNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    if value != nil {
        let full = message.isEmpty ? "expected nil, got \(String(describing: value))" : message
        throw TestFailure(message: full, file: file, line: line)
    }
}

func expectNotNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
    if value == nil {
        let full = message.isEmpty ? "expected non-nil value" : message
        throw TestFailure(message: full, file: file, line: line)
    }
}

// MARK: - Temp directory helper

/// Creates a fresh temp directory under NSTemporaryDirectory(), hands it to
/// `body`, and removes it afterwards (even if `body` throws).
func withTempDir<R>(_ body: (URL) throws -> R) rethrows -> R {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("BufferTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

// MARK: - Registration
//
// Each test file exposes `static let tests: [(String, () throws -> Void)]` on
// an enum (e.g. `ClipboardItemTests.tests`). Register each suite explicitly
// below — keep it obvious, no reflection/magic discovery.

let allSuites: [(String, [(String, () throws -> Void)])] = [
    ("ClipboardItemTests", ClipboardItemTests.tests),
    ("ClipboardStoreTests", ClipboardStoreTests.tests),
    ("FolderTests", FolderTests.tests),
    ("FolderUXTests", FolderUXTests.tests),
    ("FilterStateTests", FilterStateTests.tests),
    ("TagsChipTests", TagsChipTests.tests),
    ("ActionBarLegendTests", ActionBarLegendTests.tests),
    ("SettingsManagerTests", SettingsManagerTests.tests),
    ("ShortcutTests", ShortcutTests.tests),
    ("KeyMonitorTests", KeyMonitorTests.tests),
    ("PermissionsTests", PermissionsTests.tests),
    ("ContentDetectorTests", ContentDetectorTests.tests),
    ("ClipboardWatcherTests", ClipboardWatcherTests.tests),
    ("ImageFormatTests", ImageFormatTests.tests),
    ("LockTests", LockTests.tests),
    ("FileClipTests", FileClipTests.tests),
    ("RichCaptureTests", RichCaptureTests.tests),
    ("SyncMergeTests", SyncMergeTests.tests),
    ("CloudDriveSyncTests", CloudDriveSyncTests.tests),
    ("StoreHardeningTests", StoreHardeningTests.tests),
    ("SyncLockTests", SyncLockTests.tests),
    ("UpdateServiceTests", UpdateServiceTests.tests),
    ("ViewRegressionTests", ViewRegressionTests.tests),
]

// MARK: - Runner

@MainActor
func runAllTests() -> Int32 {
    var passed = 0
    var failed = 0

    for (suiteName, tests) in allSuites {
        for (testName, test) in tests {
            let fullName = "\(suiteName).\(testName)"
            do {
                try test()
                print("PASS \(fullName)")
                passed += 1
            } catch let failure as TestFailure {
                print("FAIL \(fullName): \(failure.message) (\(failure.file):\(failure.line))")
                failed += 1
            } catch {
                print("FAIL \(fullName): \(error)")
                failed += 1
            }
        }
    }

    print("\(passed) passed, \(failed) failed")
    return failed > 0 ? 1 : 0
}

@main
struct TestMain {
    static func main() {
        // The process's entry thread is the main thread, so it is always
        // safe to assume MainActor isolation here. App code uses @MainActor
        // types (e.g. ClipboardStore), so tests that construct them need to
        // run on the main actor too.
        let status = MainActor.assumeIsolated {
            runAllTests()
        }
        exit(status)
    }
}
