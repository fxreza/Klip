# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 3.0.x   | :white_check_mark: |
| 2.5.x   | Upstream only      |

## Reporting a Vulnerability

If you discover a security vulnerability in Klip, please **do not** open a public GitHub issue.

Instead, report it privately using GitHub's vulnerability reporting:

1. Go to the **Security** tab of this repository
2. Click **"Report a vulnerability"**
3. Fill in the details and submit

### What to include

- A clear description of the vulnerability
- Steps to reproduce it
- Potential impact
- Any suggested fix (optional)

### Response timeline

- **Acknowledgement**: Within 48 hours
- **Status update**: Within 7 days
- **Fix / patch**: As soon as reasonably possible, depending on severity

## Scope

Klip is a macOS clipboard manager with optional cloud sync. Security considerations most relevant to this project:

- Local privilege escalation
- Unauthorized access to clipboard data stored on disk
- Vulnerabilities in the Accessibility permission flow
- iCloud Drive sync security and privacy

## Data Storage

**By default**, Klip stores all clipboard data locally on your Mac:
- **Location**: `~/Library/Application Support/Klip/`
- **Data**: history.json, folders.json, plus image/text/file/flavor storage
- **Network access**: None (unless iCloud Drive sync is explicitly enabled)
- **Telemetry**: None

**When iCloud Drive sync is enabled** (opt-in, disabled by default):
- Clipboard data is synced to `~/Library/Mobile Documents/com~apple~CloudDocs`
- iCloud is responsible for encryption in transit and at rest
- Sync can be disabled at any time; data remains local-only and does not sync back from iCloud
- Large files (default >50 MB) never sync; they remain stored locally with a reference

## No Telemetry

Klip does not collect any telemetry, usage data, or analytics.

## Update Checking

Klip checks for updates by contacting GitHub releases only:
- Endpoint: https://github.com/fxreza/Klip/releases (your fork)
- Frequency: User-initiated (Settings > Check for Updates)
- Data sent: None
- Data received: Release information only

## Permissions

Klip requests only the permissions it needs:

- **Accessibility** - Required for the global hotkey (⇧⌘V) and auto-paste into the previous app
- **Launch at Login** (optional) - Controlled by user in Settings

No other system permissions are required or requested.

## Disclosure Policy

We follow responsible disclosure. Once a fix is released, we will publicly acknowledge the report (with your permission).
