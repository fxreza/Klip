# macOS status item never laid out, keyed to one bundle identifier

Investigation record, 2026-08-25. RESOLVED same day: root cause found and fixed, see Resolution at the end.

## Summary

On this Mac, any application whose `CFBundleIdentifier` is **`com.fxreza.klip`**
creates an `NSStatusItem` that macOS registers but never places in the menu bar.
The item exists, is reachable through the accessibility API, and still responds
to clicks — it is simply never drawn. The identical binary under **any other**
bundle identifier places its icon immediately.

The affected app is Klip, a menu bar clipboard manager. The workaround was to
change its identifier to `com.fxreza.klip.app`, which works. The underlying
state was never located, and `com.fxreza.klip` is still broken on this machine
as of the last test.

## Environment

| | |
|---|---|
| macOS | 26.6.2 (25G83), Darwin 25.6.0 |
| Hardware | Apple Silicon, built-in Liquid Retina XDR, notch |
| Display | one display, 3456×2234 native, **2056×1329 points** |
| App | Klip 3.2.0 (build 14) |
| Lifecycle | SwiftUI `App` + `@NSApplicationDelegateAdaptor` |
| Info.plist | `LSUIElement = true` |
| Sandbox | disabled (`com.apple.security.app-sandbox = false`) |
| Signature | self-signed, authority `QTranslate Dev` |

Status item creation, unchanged from the last known-good release:

```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
guard let button = statusItem?.button else { return }
let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Klip")
image?.isTemplate = true
button.image = image?.withSymbolConfiguration(config)
button.action = #selector(handleClick)
button.target = self
button.sendAction(on: [.leftMouseUp, .rightMouseUp])
```

Called from `applicationDidFinishLaunching`, after `NSApp.setActivationPolicy(.accessory)`.

## Symptom

Nothing is visible in the menu bar. The item is nonetheless present:

```
$ osascript -e 'tell application "System Events" to tell process "Klip" \
    to get position of every menu bar item of menu bar 2'
2025, -1
```

- The process reports **2 menu bars**; menu bar 2 contains **exactly 1 item**, size 24×24.
- Its origin is **(2025, −1)** on a 2056-point-wide screen — past the clock, off the end.
- A working status item on the same Mac, same moment, reports **y = 7** (observed
  x values 1256, 1294, 1332).
- The item still works: driving it with
  `click menu bar item 1 of menu bar 2 of process "Klip"` toggled the app's window,
  which is what a left click on that button does.
- Once, after `killall ControlCenter` followed by relaunching the app, the origin
  changed to **(1617, −1)** — a plausible x, still y = −1, still invisible.

`y = -1` versus `y = 7` is the cleanest signal available: it distinguishes
"registered but never laid out" from "placed in the bar".

## Isolation

A 30-line test app was built to vary one factor at a time. All results are from
the same machine within the same hour.

| Test app | Bundle identifier | Result |
|---|---|---|
| Plain AppKit, unbundled binary | `com.fxreza.bartest` | **visible**, y = 7 |
| Same, in a `.app` with `LSUIElement`, ad-hoc signed | `com.fxreza.bartest` | **visible**, (1332, 7) |
| SwiftUI `App` + delegate adaptor + `Settings` scene | `com.fxreza.swiftuitest` | **visible**, (1332, 7) |
| **Same bundle, identifier changed only** | **`com.fxreza.klip`** | **broken**, (2025, −1) |
| Klip, pristine v3.2.0 source, all local edits stashed | `com.fxreza.klip` | **broken**, (2025, −1) |
| Klip, rebuilt with new identifier | `com.fxreza.klip.app` | **visible**, (1332, 7) |

The fourth row is the decisive one: one binary, one signature, one bundle
layout, and the only difference is the identifier string.

The fifth row rules out the application's own code, including every change made
in the session where the problem appeared.

## Ruled out

- **App source changes.** A build from pristine `HEAD` reproduces it.
- **The icon image.** `NSImage(systemSymbolName: "doc.on.clipboard")` loads
  (16×18), and `withSymbolConfiguration` returns non-nil. A test app rendering
  the same symbol the same way — including the original code's ordering bug,
  where `isTemplate` is set before `withSymbolConfiguration` and lost by the
  copy — is visible.
- **SwiftUI lifecycle, `LSUIElement`, bundling, signature type.** All varied,
  all irrelevant.
- **The app's own setting.** `hideStatusBar` is unset in defaults.
- **Menu bar space.** The user freed slots and entered menu bar edit mode;
  nothing appeared. Test items claim positions in that same bar instantly.
- **Menu bar manager apps.** None installed or running (no Bartender, Ice,
  Hidden Bar, Dozer, Vanilla).
- **Saved item position.** `NSStatusItem Preferred Position Item-0` was 708;
  deleting it, and separately forcing it to 500, changed nothing.
- **LaunchServices duplicates.** 28 bundles were registered under the
  identifier, 11 pointing at paths that no longer existed, mostly
  `~/.Trash/Klip <time>.app` copies left by repeated installs. All dead
  registrations were unregistered, the user emptied the Trash, and two
  `Klip.app` bundles stored inside Klip's own clipboard payload directory
  (`Application Support/Klip/files/<uuid>/Klip.app`) were unregistered without
  being deleted. Down to a single registration. Still broken.
- **LaunchServices rebuild.** `lsregister -r -domain local -domain system
  -domain user`. Note `-kill` was removed in this macOS version and now prints
  *"The -kill option has been removed because it was dangerous and no longer
  useful."*
- **`killall ControlCenter`.** Moved the reported x, never fixed visibility.
- **Logout and login.** No change.
- **Saved application state.** `~/Library/Saved Application State/com.fxreza.klip.savedState`
  does not exist.

## Where the state was looked for, and not found

- `~/Library/Preferences/com.fxreza.klip.plist` — contains only app settings
  plus `NSStatusItem Preferred Position Item-0`. **No `NSStatusItem Visible`
  key**, which is what a user-hidden item normally gets.
- `defaults -currentHost read com.fxreza.klip` — no ByHost domain exists.
- `~/Library/Preferences/com.apple.controlcenter.plist` — only
  `NSStatusItem VisibleCC …` entries for Apple's own items (Battery, Bluetooth,
  Clock, WiFi, BentoBox).
- `~/Library/Preferences/ByHost/com.apple.controlcenter.*.plist` — Apple module
  states only.
- `~/Library/Preferences/ByHost/com.apple.controlcenter.displayablemenuextras.*.plist`
  — the `displayablesInfo` blob decodes to JSON listing only Stage Manager.
- `~/Library/Application Support/com.apple.controlcenter/` — only a TipKit database.
- `~/Library/Preferences/com.apple.systemuiserver.plist` — nothing relevant.
- A recursive content search for the string `fxreza` across `~/Library/Preferences`,
  `~/Library/Application Support/com.apple*` and `~/Library/Caches/com.apple.*`
  returned no hits.
- No container (`~/Library/Containers`) and no application scripts directory.

## Suspected trigger, unproven

The user reports the icon worked normally until 2026-08-25, ~10:05 local. At
that moment they ran, at my instruction:

```bash
scripts/build_local.sh && scripts/run_app.sh
```

which launched a **second live copy of `com.fxreza.klip`** from
`build.noindex/Klip.app` while `/Applications/Klip.app` was installed under the
same identifier. Every measurement after that point shows the broken frame; there
is no measurement of the working state from before it. So this is a timeline
correlation, not a demonstrated mechanism.

A guard was added to `scripts/run_app.sh` refusing to launch a local build whose
identifier matches the installed app.

## Not yet tried

Roughly in order of expected value:

1. **Console logs at the moment of creation.** `log stream` / `log show`
   filtered on `ControlCenter`, `WindowServer` and the app, around the
   `statusItem(withLength:)` call. Nothing has been read from the system log at
   all — this is the largest untouched source of evidence.
2. **Deleting `~/Library/Preferences/com.fxreza.klip.plist` outright.** Only
   individual keys were removed. Settings have already been copied to the new
   domain, so the file is now a backup and can be moved aside rather than deleted.
3. **A fresh macOS user account.** Determines whether the state is user-level
   (in some part of `~/Library` not yet found) or system/daemon-level. This is
   the cheapest way to halve the search space.
4. **Safe Mode boot**, which clears several system caches.
5. **cfprefsd and LaunchServices caches** under `/private/var/folders/*/*/C/`.
6. **System-level databases** keyed by bundle identifier: TCC, the Control
   Center / menu bar layout store wherever macOS 26 keeps it, `/private/var/db`.

## Current state

- `/Applications/Klip.app` ran as `com.fxreza.klip.app` while the workaround
  was in place. 3.3.0 ships the original `com.fxreza.klip` again — see
  "Resolution" below.
- Preferences were migrated copy-only from the old domain by
  `AppDelegate.migrateUserDefaultsFromOldKlipIdentifierIfNeeded()`. The old
  domain is untouched. One value did not carry (`historyLimit`), because
  `SettingsManager` is constructed during `AppDelegate`'s stored-property
  initialisation, before `applicationDidFinishLaunching` runs the migration.
- Clipboard history, folders and trash are unaffected — they live in
  `~/Library/Application Support/Klip`, keyed by path, not identifier.
- iCloud sync is unaffected — it uses
  `~/Library/Mobile Documents/com~apple~CloudDocs/Klip/`, a fixed path.
- `UpdateService.expectedBundleIdentifier` is `"com.fxreza.klip"` and would
  have **rejected** an update carrying the workaround identifier. Reverting the
  identifier in 3.3.0 is what resolves that; no release ever shipped
  `com.fxreza.klip.app`.

## Verification command

The single check that answers "is it fixed":

```bash
osascript -e 'tell application "System Events" to tell process "Klip" \
    to get position of every menu bar item of menu bar 2'
```

`y = 7` (or any small positive y) means placed. `y = -1` means the bug is present.

## Resolution (2026-08-25, later the same day)

Root cause found via the system log (untried item 1) and fixed. The item was on
ControlCenter's per-app blocked list, the macOS 26 "Allow in the Menu Bar"
feature (System Settings > Menu Bar). Every launch logged, in category
`com.apple.controlcenter:appStatusItems`, about 15 ms after host creation:

```
Moving host to blocked list; (bid:com.fxreza.klip-Item-0-<pid>)
```

(Note: `log` is a zsh builtin; use `/usr/bin/log`.)

### The state

Per-user store, TCC-protected (Full Disk Access required to read):

```
~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist
```

Key `trackedApplications` holds a nested binary plist: a flat array of
[location, TrackedApplication] pairs, where a location is
`{bundle: {_0: "<bundle id>"}}` or `{adhocBinary: {_0: {relative: "<file URL>"}}}`
and a TrackedApplication is `{location, menuItemLocations: [location...], isAllowed}`.
This is `SystemItemMenuBarPreferences` in the private ControlCenter.framework.
This is why every earlier search missed it: the record searched
`~/Library/Preferences`, `Application Support` and `Caches`, never
`Group Containers`, and the folder is unreadable without FDA anyway.

### Root cause

ControlCenter attributes a status item to the RESPONSIBLE app that launched it.
Because Klip builds had been launched from Claude Code sessions and Terminal,
`bundle: com.fxreza.klip` was recorded inside the `menuItemLocations` of three
foreign entries: `com.anthropic.claudefordesktop` (with `isAllowed: false`,
because the user had hidden Claude Desktop's menu bar icon),
`com.anthropic.claude-code`, and `com.apple.Terminal`. Any status item with
bundle id `com.fxreza.klip` matched the not-allowed claudefordesktop entry and
was registered but never laid out. The suspected trigger was therefore right:
the 10:05 `scripts/build_local.sh && scripts/run_app.sh` launch from a Claude
Code session is what planted the attribution.

Klip's own entry was `isAllowed: true` the whole time, which is why the
Settings pane showed Klip's toggle ON and toggling it did nothing. A control
test proved the toggle pipeline itself worked: toggling MEGAsync's row made
ControlCenter log block/unblock instantly, keyed by bundle id.

### The fix

1. Back up the plist.
2. Decode `trackedApplications`, remove `{bundle: {_0: "com.fxreza.klip"}}`
   from the `menuItemLocations` of the three foreign entries only. Leave Klip's
   own entry, and every `isAllowed` flag, untouched.
3. Write the file back between `killall cfprefsd` and `killall ControlCenter`
   (kill cfprefsd first so a cached copy is not flushed over the edit).

Verified: a test app under `com.fxreza.klip` now places at y = 7 and survives
relaunch; ControlCenter logs plain "Starting to track host" with no block. The
installed Klip.app and the deliberately hidden items (Claude, Bitwarden,
Chrome) were unaffected. Pre-fix backup:
`~/Desktop/group.com.apple.controlcenter.backup-2026-08-25.plist`.

### Prevention

- Never run two live copies of the same bundle identifier at once (the
  `run_app.sh` guard stays).
- Launch dev builds of status-bar apps with `open` on an LS-registered bundle,
  never by executing the binary directly, and expect that the launcher app
  (Claude Desktop, Terminal) may be recorded as responsible for the item. If
  the launcher's own menu bar icon is hidden, the built app's icon can vanish
  system-wide exactly as documented above.
- Cross-project note for future sessions lives in `/Users/sam/Claude/CLAUDE.md`.
### Reverted in 3.3.0

The `com.fxreza.klip.app` workaround is gone: `Klip.xcodeproj/project.pbxproj`,
`build_dmg.sh` and `scripts/build_local.sh` build `com.fxreza.klip` again, which
is what `UpdateService.expectedBundleIdentifier` has expected all along, so the
in-app updater accepts its own builds. No released version ever carried the
workaround identifier.

`AppDelegate.migrateUserDefaultsFromWorkaroundIdentifierIfNeeded()` copies any
settings written while the workaround was installed back into the real domain
(copy-only, missing keys only, `NSStatusItem` positions skipped). On any Mac
that never ran a workaround build the domain does not exist and it does
nothing.

The `scripts/run_app.sh` guard against two live copies of one identifier
stays.
