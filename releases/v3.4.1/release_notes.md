# Klip v3.4.1

### Fixed

- **Upside-down text in the clip list on macOS 26** - On macOS 26 (Tahoe), rows in the history list could render every letter flipped upside-down in place until the row was hovered or selected, making English clips look like a foreign script and Persian clips look like garbage. This is a macOS 26 rendering bug that hit other clipboard managers the same way; Klip now renders row titles and subtitles through an offscreen pass that sidesteps it. The clips themselves were never affected - only how the list drew them.
- **The "updated" toast can be closed** - The little panel that appears after an update ("Klip 3.4.1 - What's New") only went away on its own after 8 seconds. It now has a ✕ in the corner so you can dismiss it yourself.

### Installing

Klip is signed with a self-signed certificate, not an Apple Developer ID, so macOS Gatekeeper will not open it on first launch. Unzip it into `/Applications`, then right-click the app and choose **Open**, and confirm once. After that it launches normally. Updating from an earlier Klip through the in-app updater needs no such step.
