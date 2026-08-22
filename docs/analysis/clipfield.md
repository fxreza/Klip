# Clipfield technical report (reference/clipfield, MIT, Copyright 2026 Alex Jolley)

Purpose: replicate Clipfield's UI design/colors/layout in Buffer and borrow code. Produced 2026-08-22 by an analysis subagent.

## 1. BUILD
- Pure SwiftPM (`Package.swift`, tools 6.0), `platforms: [.macOS(.v14)]` -> **min macOS 14**. Swift language mode 5. **No third-party deps.** Frameworks: SwiftUI, AppKit, SwiftData, Carbon.HIToolbox, CryptoKit, Security, NaturalLanguage, ServiceManagement, UniformTypeIdentifiers, ApplicationServices.
- `build_app.sh` assembles .app + Info.plist (LSUIElement), ad-hoc codesign; `package_dmg.sh`.
- Storage: **SwiftData** (`Storage/DataController.swift`): `Schema([ClipItem, Folder, Snippet])`, store at `~/Library/Application Support/Clipfield/history.store`. Schema generation int in UserDefaults; on mismatch the store is **wiped** (no migration).
- `HistoryStore` (`Storage/HistoryStore.swift`): dedup by SHA-256 `contentHash`, retention pruning (default 500, 0 = unlimited, pinned exempt), `clearUnpinned()/clearAll()`, posts `clipHistoryChanged`.
- `CryptoVault.swift`: optional AES-GCM encryption at rest, key in Keychain (device-only). Per-row `encrypted` flag. NSCache for decoded thumbnails.

## 2. THEME / DESIGN SYSTEM
`UI/Theme.swift` (74 lines):
```swift
enum Theme {
    static let panelCornerRadius: CGFloat = 18
    static let rowCornerRadius: CGFloat = 10
    static var accent: Color { AccentTheme.current.color }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let selectionSpring = Animation.spring(response: 0.28, dampingFraction: 0.82)
    static let promptSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
extension ClipKind { var tint: Color {  // text .gray, richText .indigo, link .blue, image .purple, file .gray, color .pink, email .green, phone .teal, code .orange, other .gray
} }
extension Color { init?(hexString: String) }  // #RGB/#RRGGBB/#RRGGBBAA
```
- No hex chrome colors: the palette is **semantic SwiftUI system colors + materials**, auto light/dark.
- `UI/Settings/Appearance.swift`: `AppearanceKeys` (UserDefaults keys: appearance.accent, .colorScheme, .overlaySize, .showPreview, .sidebarCollapsed, .sidebarWidth, .previewWidth, overlay.contentWidth/Height); `AccentTheme` (system, blue, purple, indigo, pink, red, orange, green, teal); `AppColorScheme` (system/light/dark); `OverlaySize` compact 760x480, standard 880x540, large 1000x620.
- Radii: panel 18, row 10, badge/thumbnail 8, prompt cards 16, swatch 14/12.
- Material: `.background(.regularMaterial)` clipped to RoundedRectangle(18) + `.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)`. Prompt sheets same + `.shadow(color: .black.opacity(0.3), radius: 20, y: 8)`. Scrim `Color.black.opacity(0.28)`.
- Selection highlight: `Theme.accentGradient` fill + `matchedGeometryEffect` (sidebar ns / chip ns), `Theme.selectionSpring`. Row hover `Color.primary.opacity(0.06)`. Chip inactive `Color.primary.opacity(0.07)`. Selected row glow `.shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)`.
- Fonts: sidebar title 15 bold; sidebar rows 13 (semibold when active); section header 10 bold `.tertiary`; chip labels 11 medium; row title 13 (12.5 monospaced for code); subtitle `.caption2`; search field NSFont 15.
- Window: NSPanel `backgroundColor = .clear`, `isOpaque=false`, `hasShadow=true`; dark/light via `.preferredColorScheme`.
- Other hardcoded: white.opacity(0.18/0.15/0.25/0.3/0.85/0.1/0.12/0.2), accentColor.opacity(0.16), `.orange` pin icon.

## 3. MAIN OVERLAY LAYOUT
- `OverlayPanel: NSPanel` borderless+resizable, floating, `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient]`, `canBecomeKey/Main = true`, min 560x380 max 1600x1100. Size persisted. Positioned centered on the screen under the mouse, 8% above center. Dismiss on `windowDidResignKey` (0.4s suppression after show). `NSHostingView.sizingOptions = []`.
- **Sidebar** (`OverlayView.swift:366-453`): title "Clipfield"; rows All (`tray.full.fill`), Pinned (`pin.fill`), Snippets (`text.badge.star`, count); "FOLDERS" header; ScrollView of Folder rows (`folder.fill`, count); bottom "New Folder" (`plus.circle.fill`). Row = icon(16) + title + count badge; active = white text + accentGradient + matchedGeometryEffect "sidebarSel". `enum Scope { all, pinned, snippets, folder(id) }`. Folder context menu: Delete Folder. Resizable 120-320 via `PanelResizer`, collapsible. `⌘[`/`⌘]` cycle scopes.
- **Search** (`SearchField.swift`): NSViewRepresentable over `AutoFocusSearchField: NSSearchField`, 15pt, roundedBezel, no focus ring. `doCommandBy` routes: moveUp/Down, insertNewline (paste), insertNewlineIgnoringFieldEditor ⌥↩ (plain paste), insertTab (toggle stack), insertLineBreak ⇧↩ (paste stack), deleteToBeginningOfLine ⌘⌫ (delete when empty), cancelOperation Esc. Auto-refocus on key window.
- **Filter chips** (`chipBar`, `OverlayView.swift:486-521`): horizontal ScrollView of capsules for `chipTags: [SmartTag] = [.link, .image, .email, .phone, .color, .code, .file]` (line 70). `Label(tag.label, systemImage:)`, 11 medium; active = Capsule accentGradient + matchedGeometryEffect "chipSel"; inactive = primary.opacity(0.07). Toggle `activeTag`. Types: `Models/ClipKind.swift` (text, richText, link, image, file, color, email, phone, code, other) and `Models/SmartTag.swift` (link, email, phone, address, date, color, code, number, image, file). `Tagging/SmartTagger.swift` assigns at capture (NSDataDetector + regex + looksLikeCode). `Search/SearchEngine.filter(items, query:, activeTag:)` - typed tokens matching a tag name become required tags; rest substring-match previewText+text+sourceAppName.
- **Rows** (`ClipRowView.swift`): 38x38 badge (thumbnail / color swatch / tinted SF icon), title previewText 2 lines, subtitle app name + relative time + up to 2 tag icons; trailing stack-order number, paste-count pill, pin icon. No app icon image. `LazyVStack(spacing: 3)` in ScrollView padding 8, auto-scroll to selection. `.onDrag`, **single click = paste immediately** (NOTE: Buffer must keep its own "click does not paste/close" behavior), `.onHover`, `.contextMenu`.
- **Preview pane** (`ClipPreviewPane.swift`): resizable 200-440. Header kind icon + label (+ open button for link). Body: image fit max 240 r12; color swatch 130 tall + hex; else scrollable selectable Text (mono for code). Footer: tag chips, Copied date, From app, Pasted count, Folder. Empty state `doc.text.magnifyingglass`.
- Keys: ↑↓, ↩ paste, ⌥↩ plain, ⇥ stack, ⇧↩ paste stack, ⌘E edit, ⌘P pin, ⌘⌫ delete, ⌘1-9 quick paste, ⌘[ ⌘], Esc. Implemented as hidden `Button("").keyboardShortcut(...)` in `shortcutButtons` (`OverlayView.swift:829-865`).
- Context menu: Paste, Paste as Plain Text, Copy, Edit & Paste, Add/Remove Paste Stack, Open Link, Reveal in Finder, Transform & Paste submenu, Pin/Unpin, Move to Folder submenu, Delete.

## 4. SNIPPETS / FOLDERS
- `Models/Folder.swift`: `@Model` id, name, createdAt, sortIndex, `@Relationship(deleteRule: .nullify, inverse: \ClipItem.folder) items`. Flat, one level. `ClipItem.folder: Folder?`.
- Create: inline prompt (not NSAlert - an alert would dismiss the borderless panel). **Rename: not implemented.** Delete: `deleteFolder` resets scope, deletes folder, items nullified (not deleted).
- Assign: context menu "Move to Folder" -> `move(item:to:)`; "Remove from Folder".
- `Models/Snippet.swift`: `{{placeholder}}` templating (`placeholders(in:)`, `filled(with:)`), usage count. Snippets not in folders.
- Drag: `.onDrag` only (file URL provider for files, PNG file-promise for images, RTF/URL/text fallbacks) (`OverlayView.swift:564`). **No `onDrop` anywhere.**

## 5. SETTINGS (`SettingsView.swift`, TabView 520x430, 5 tabs)
General (HotkeyRecorder + launch at login via SMAppService), Appearance (accent swatches, scheme, overlay size, show preview), History (retention stepper 50-5000, clear unpinned/all), Privacy (excluded bundle IDs via NSOpenPanel), Security (encryption toggle).
- `HotkeyRecorder.swift` (~135 lines): NSViewRepresentable over custom `RecorderView: NSView`; click to record, requires ⌘/⌃/⌥, Escape cancels, converts to Carbon modifiers + glyph string, `onRecord(keyCode, carbonModifiers, glyphs)`. **Portable verbatim.**
- `HotkeyStore.swift`: UserDefaults keys hotkeyKeyCode/hotkeyModifiers/hotkeyDisplay, default ⇧⌘V.
- `HotKeyManager.swift`: Carbon `RegisterEventHotKey` + `InstallEventHandler` (no Accessibility needed). Single hotkey, signature 'CLIP'.

## 6. CLIPBOARD
- `PasteboardReader.swift`: honors `org.nspasteboard.ConcealedType/TransientType/AutoGeneratedType`; priority image (png/tiff->PNG, cap 4096px, 96px thumb) > file URLs (multi, kind .file) > text (+RTF/HTML -> .richText). Also stores **rawFlavors** (all pasteboard bytes, binary plist, cap 16MB) via `PasteboardFlavors.swift` for byte-perfect replay. SHA-256 hash. Source app from `NSWorkspace.frontmostApplication`.
- `ClipboardWriter.swift`: `write(item:)` prefers rawFlavors replay, else curated by kind; `writePlain(item:)` plain string only (= paste as plain text); `writeString`.
- `Paster.swift`: write -> recordPaste -> reactivate previousApp -> `ensureAccessibilityPermission()` -> 0.12s delay -> CGEvent ⌘V (`kVK_ANSI_V`, `.maskCommand`, `.cgAnnotatedSessionEventTap`).
- `ClipboardMonitor.swift`: polls changeCount every 0.4s.
- `ImageProcessing.swift`: maxStoredDimension 4096, thumbnail 96.

## 7. PERMISSIONS / ONBOARDING
Only **Accessibility** (for synthesized ⌘V). `PermissionsState` polls `AXIsProcessTrusted()` every 1s, `onBecameTrusted` once. `requestAccessibility()` = `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` + opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. `OnboardingView` 440 wide, status card, button, skip. Reachable from status-bar menu "Permissions & Welcome...".

## 8. BORROWABLE CODE
| Area | File | Copy |
|---|---|---|
| Theme tokens | `Sources/Clipfield/UI/Theme.swift` | whole |
| Appearance model | `UI/Settings/Appearance.swift` | whole |
| Sidebar | `UI/Overlay/OverlayView.swift:366-453` | `sidebar`, `sidebarRow` |
| Filter chips | `UI/Overlay/OverlayView.swift:486-521` | `chipBar`, `chip` |
| Search filter | `Search/SearchEngine.swift` | `filter` |
| Smart tagging | `Tagging/SmartTagger.swift` | `analyze` etc. |
| Hotkey recorder | `UI/Settings/HotkeyRecorder.swift` | whole |
| Hotkey store/manager | `Hotkeys/HotkeyStore.swift`, `Hotkeys/HotKeyManager.swift` | whole |
| Preview pane | `UI/Overlay/ClipPreviewPane.swift` | whole |
| Row | `UI/Overlay/ClipRowView.swift` | whole |
| Search field | `UI/Overlay/SearchField.swift` | whole |
| Panel | `UI/Overlay/OverlayPanel.swift`, `OverlayController.swift` | position/show/animateOut |
| Resizer | `UI/Overlay/PanelResizer.swift` | whole |
| Pasteboard | `Clipboard/PasteboardReader.swift`, `PasteboardFlavors.swift`, `ClipboardWriter.swift`, `Paster.swift` | capture/replay/plain paste |
| Permissions | `App/PermissionsState.swift`, `UI/Onboarding/OnboardingView.swift` | whole |
| Text transforms | `Tagging/TextTransforms.swift` | whole |
| Encryption | `Storage/CryptoVault.swift` | whole (optional) |

## Compatibility notes for porting into Buffer
- Buffer targets macOS 13; Clipfield APIs used for UI (materials, matchedGeometryEffect, Capsule, preferredColorScheme) all exist on 13. SwiftData does NOT (14+) - do not port storage.
- Clipfield single-click pastes; Buffer must keep its click-does-not-paste behavior.
- Clipfield has no folder rename and no onDrop; both must be written new.
