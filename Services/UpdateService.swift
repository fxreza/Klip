import Foundation
import AppKit

class UpdateService {
    static let shared = UpdateService()
    private init() {}

    private let releasesURL = URL(string: "https://api.github.com/repos/fxreza/Klip/releases")!
    private let lastCheckKey = "lastUpdateCheckDate"
    private let repoBaseURL = "https://github.com/fxreza/Klip"
    private var progressWindow: NSWindow?
    private var toastWindow: NSWindow?
    private var pendingReleaseURL: URL?

    func checkOnLaunchIfNeeded() {
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86400 {
            let hoursAgo = Date().timeIntervalSince(lastCheck) / 3600
            print("[UpdateService] Skipping launch check — last checked \(String(format: "%.1f", hoursAgo))h ago")
            return
        }
        print("[UpdateService] Running launch check")
        checkForUpdates(silent: true)
    }

    func checkForUpdates(silent: Bool) {
        print("[UpdateService] checkForUpdates(silent: \(silent))")
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                print("[UpdateService] Network error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse {
                print("[UpdateService] GitHub API responded: HTTP \(http.statusCode)")
            }
            guard let self,
                  let data,
                  let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("[UpdateService] Failed to parse releases JSON")
                return
            }
            print("[UpdateService] Fetched \(releases.count) release(s)")
            self.handleReleases(releases, silent: silent)
        }.resume()
    }

    private func handleReleases(_ releases: [[String: Any]], silent: Bool) {
        let includePrereleases = UserDefaults.standard.bool(forKey: "includePrereleases")
        let sorted = releases
            .filter { includePrereleases || ($0["prerelease"] as? Bool) != true }
            .sorted { (($0["published_at"] as? String) ?? "") > (($1["published_at"] as? String) ?? "") }

        #if arch(arm64)
        let archKeyword = "Silicon"
        #else
        let archKeyword = "Intel"
        #endif

        var latestTag: String?
        var latestZipURL: String?
        for release in sorted {
            guard let tag = release["tag_name"] as? String,
                  let assets = release["assets"] as? [[String: Any]] else { continue }
            let archZip = assets.first(where: {
                guard let name = $0["name"] as? String else { return false }
                return name.hasSuffix(".zip") && name.contains(archKeyword)
            })
            let anyZip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })
            if let zip = archZip ?? anyZip,
               let url = zip["browser_download_url"] as? String {
                latestTag = tag
                latestZipURL = url
                print("[UpdateService] Selected asset: \(zip["name"] as? String ?? "?") (\(archKeyword) preferred)")
                break
            }
        }

        guard let tag = latestTag, let zipURL = latestZipURL else {
            print("[UpdateService] No release with a .zip asset found")
            return
        }

        let latest = stripTagPrefix(tag)
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        print("[UpdateService] Latest: \(latest)  Current: \(current)  ZipURL: \(zipURL)")

        DispatchQueue.main.async {
            if self.versionIsNewer(latest, than: current) {
                print("[UpdateService] Update available — showing alert")
                self.showUpdateAlert(version: latest, tag: tag, downloadURL: zipURL)
            } else {
                print("[UpdateService] Already up to date (silent: \(silent))")
                if !silent { self.showUpToDateAlert() }
            }
        }
    }

    private func stripTagPrefix(_ tag: String) -> String {
        var v = tag
        let lower = v.lowercased()
        if lower.hasPrefix("klip-v") {
            v = String(v.dropFirst("klip-v".count))
        } else if lower.hasPrefix("buffer-v") {
            v = String(v.dropFirst("buffer-v".count))
        } else if lower.hasPrefix("v") {
            v = String(v.dropFirst(1))
        }
        return v
    }

    private func versionIsNewer(_ latest: String, than current: String) -> Bool {
        let lp = latest.split(separator: ".").compactMap { Int($0) }
        let cp = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(lp.count, cp.count) {
            let l = i < lp.count ? lp[i] : 0
            let c = i < cp.count ? cp[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, tag: String, downloadURL: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Klip \(version) is available"
        alert.informativeText = "A new version of Klip is ready to download and install."
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        print("[UpdateService] Update alert response: \(response == .alertFirstButtonReturn ? "Update Now" : "Later")")
        if response == .alertFirstButtonReturn {
            downloadAndInstall(url: downloadURL, tag: tag)
        }
    }

    private func showUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "You're up to date"
        alert.informativeText = "Klip is already on the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func checkIfJustUpdated() {
        guard UserDefaults.standard.bool(forKey: "bufferJustUpdated") else { return }
        UserDefaults.standard.removeObject(forKey: "bufferJustUpdated")
        let tag = UserDefaults.standard.string(forKey: "bufferUpdateTag") ?? ""
        UserDefaults.standard.removeObject(forKey: "bufferUpdateTag")
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        print("[UpdateService] Detected post-update launch, version: \(version), tag: \(tag)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.showSuccessToast(version: version, tag: tag)
        }
    }

    private func showSuccessToast(version: String, tag: String) {
        let w: CGFloat = 270
        let h: CGFloat = 190

        // NSPanel with .nonactivatingPanel never touches app activation state
        // so closing it cannot trigger AppKit's "accessory app with no windows" termination
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.alphaValue = 0
        toastWindow = window

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        window.contentView = blur

        // Checkmark icon
        let iconSize: CGFloat = 48
        let iconConfig = NSImage.SymbolConfiguration(pointSize: iconSize * 0.8, weight: .medium)
            .applying(.init(paletteColors: [.white, NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)]))
        let iconView = NSImageView(frame: NSRect(x: (w - iconSize) / 2, y: 124, width: iconSize, height: iconSize))
        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        blur.addSubview(iconView)

        let titleString = version.isEmpty ? "Klip" : "Klip \(version)"
        let title = NSTextField(labelWithString: titleString)
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 98, width: w, height: 20)
        blur.addSubview(title)

        let subtitle = NSTextField(labelWithString: "The best Klip yet.")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.55)
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 0, y: 78, width: w, height: 16)
        blur.addSubview(subtitle)

        // What's New button
        let releaseURLString = tag.isEmpty
            ? "\(repoBaseURL)/releases"
            : "\(repoBaseURL)/releases/tag/\(tag)"
        pendingReleaseURL = URL(string: releaseURLString)

        let btn = NSButton(title: "What's New →", target: self, action: #selector(whatsNewButtonTapped))
        btn.bezelStyle = .rounded
        btn.font = .boldSystemFont(ofSize: 12)
        let btnW: CGFloat = 150
        btn.frame = NSRect(x: (w - btnW) / 2, y: 18, width: btnW, height: 30)
        blur.addSubview(btn)

        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after 8 s (enough time to read and click)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.dismissToast()
        }
    }

    @objc private func whatsNewButtonTapped() {
        if let url = pendingReleaseURL {
            NSWorkspace.shared.open(url)
        }
        dismissToast()
    }

    private func dismissToast() {
        guard let window = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    private func downloadAndInstall(url: String, tag: String) {
        guard let downloadURL = URL(string: url) else {
            print("[UpdateService] Invalid download URL: \(url)")
            return
        }
        print("[UpdateService] Starting download: \(url)")
        showProgressWindow()

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] localURL, _, error in
            guard let self else { return }

            func fail(_ reason: String) {
                print("[UpdateService] \(reason)")
                DispatchQueue.main.async { self.hideProgressWindow() }
            }

            if let error {
                return fail("Download error: \(error.localizedDescription)")
            }
            guard let localURL else {
                return fail("Download returned no file")
            }
            print("[UpdateService] Download complete: \(localURL.path)")

            // 1. UUID-based temp dir — not guessable by other processes
            let fm = FileManager.default
            let tmpBase = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("KlipUpdate_\(UUID().uuidString)")
            let zipURL    = tmpBase.appendingPathComponent("update.zip")
            let extractURL = tmpBase.appendingPathComponent("extracted")
            let newAppURL  = extractURL.appendingPathComponent("Klip.app")
            let scriptURL  = tmpBase.appendingPathComponent("install.sh")

            do {
                try fm.createDirectory(at: tmpBase, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.moveItem(at: localURL, to: zipURL)
                print("[UpdateService] Zip at: \(zipURL.path)")
            } catch {
                return fail("Failed to prepare temp dir: \(error)")
            }

            // Sanity-check the payload before handing it to ditto: an error
            // page or a truncated download is not worth extracting.
            let zipSize = ((try? fm.attributesOfItem(atPath: zipURL.path))?[.size] as? NSNumber)?.intValue ?? 0
            guard zipSize > 100_000, zipSize < 500_000_000 else {
                return fail("Downloaded asset has an implausible size (\(zipSize) bytes)")
            }

            // 2. Extract zip in Swift so we can inspect it before touching /Applications
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", zipURL.path, extractURL.path]
            do {
                try ditto.run(); ditto.waitUntilExit()
                guard ditto.terminationStatus == 0 else {
                    return fail("ditto extraction failed (exit \(ditto.terminationStatus))")
                }
                print("[UpdateService] Extraction OK")
            } catch {
                return fail("Failed to run ditto: \(error)")
            }

            // 3. Confirm Klip.app is actually present after extraction
            guard fm.fileExists(atPath: newAppURL.path) else {
                return fail("Klip.app not found in extracted zip at \(newAppURL.path)")
            }

            // 4. Verify the signature *and* who signed it, before replacing
            //    anything. `--verify` alone only proves the signature is
            //    internally consistent — any ad-hoc or self-signed bundle
            //    passes it, so it could not tell a genuine Klip build from
            //    anything else that ended up at the download URL (5A-12).
            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--verify", "--strict", newAppURL.path]
            do {
                try codesign.run(); codesign.waitUntilExit()
                guard codesign.terminationStatus == 0 else {
                    return fail("Code signature verification failed (exit \(codesign.terminationStatus))")
                }
                print("[UpdateService] Code signature verified OK")
            } catch {
                return fail("Failed to run codesign: \(error)")
            }

            // 4b. The downloaded bundle must carry the same signing identity
            //     as the app that is running, and our bundle identifier. A
            //     self-signed identity cannot be pinned with a designated
            //     requirement, so the running app is the reference.
            guard let candidate = Self.signingInfo(at: newAppURL.path) else {
                Self.showIdentityRefusedAlert(reason: "the downloaded app's signature could not be read")
                return fail("Could not read the downloaded bundle's signing info")
            }
            guard let running = Self.signingInfo(at: Bundle.main.bundlePath) else {
                Self.showIdentityRefusedAlert(reason: "this app's own signature could not be read")
                return fail("Could not read the running bundle's signing info")
            }
            if let reason = Self.identityMismatchReason(candidate: candidate, running: running) {
                Self.showIdentityRefusedAlert(reason: reason)
                return fail("Refusing to install: \(reason)")
            }
            print("[UpdateService] Signing identity matches the running app")

            // 5. Write install script — extraction already done, the script
            //    only stages, swaps and opens. Paths are passed as positional
            //    arguments rather than interpolated into the script text
            //    (5A-25).
            let script = Self.installScript()
            do {
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                print("[UpdateService] Install script written to: \(scriptURL.path)")
            } catch {
                return fail("Failed to write install script: \(error)")
            }

            // 6. chmod 755
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", scriptURL.path]
            do {
                try chmod.run(); chmod.waitUntilExit()
            } catch {
                return fail("Failed to chmod script: \(error)")
            }

            // 7. Launch script detached via nohup so it survives the app
            //    quitting. `sh -c '…' arg0 arg1 arg2` binds $0/$1/$2, so no
            //    path is ever interpolated into shell text (5A-25).
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = [
                "-c",
                "nohup /bin/bash \"$0\" \"$1\" \"$2\" >/dev/null 2>&1 &",
                scriptURL.path,
                newAppURL.path,
                Self.installDestination,
            ]
            do {
                try launcher.run()
                launcher.waitUntilExit() // wait for fork to complete before we exit
                print("[UpdateService] Install script detached, terminating app")
            } catch {
                return fail("Failed to launch install script: \(error)")
            }

            // Pass info to the new app so it can show the success toast
            UserDefaults.standard.set(true, forKey: "bufferJustUpdated")
            UserDefaults.standard.set(tag, forKey: "bufferUpdateTag")
            UserDefaults.standard.set(Date(), forKey: self.lastCheckKey) // suppress launch check in new app
            UserDefaults.standard.synchronize() // flush to disk before process exits

            DispatchQueue.main.async {
                self.hideProgressWindow()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }.resume()
    }

    // MARK: - Install script (5A-11 / 5A-25)

    /// Where an update is installed.
    static let installDestination = "/Applications/Klip.app"

    /// The bundle identifier an update must carry to be installed.
    static let expectedBundleIdentifier = "com.fxreza.klip"

    /// The installer, as a standalone bash script.
    ///
    /// Arguments: `$1` = the extracted new bundle, `$2` = the destination.
    /// `$3`/`$4` exist only so a test can run this for real without waiting
    /// two seconds and without launching anything; the app passes neither, so
    /// production behaviour is the defaults.
    ///
    /// The old version did `rm -rf "$2"` and *then* `cp -R`. If the copy
    /// failed — disk full, the extracted bundle moved, permissions — the user
    /// was left with no app at all (5A-11); and `rm -rf` returns 0 for a
    /// missing path, so the `$?` check caught almost nothing. This one stages
    /// the new bundle next to the destination first, moves the old one aside,
    /// swaps, and only then deletes the old copy — restoring it if any step
    /// fails. Every path is quoted.
    static func installScript() -> String {
        """
        #!/bin/bash
        # Klip updater. $1 = new bundle, $2 = destination,
        # $3 = seconds to wait first (default 2), $4 = relaunch? 1/0 (default 1).
        set -u

        NEW_APP="$1"
        TARGET="$2"
        WAIT="${3:-2}"
        RELAUNCH="${4:-1}"
        STAGE="${TARGET}.new"
        OLD="${TARGET}.old"

        fail() {
            osascript -e "display alert \\"Klip Update Failed\\" message \\"$1 Try updating manually.\\"" >/dev/null 2>&1
            exit 1
        }

        sleep "$WAIT"

        # Stage beside the destination, on the same volume, so the swap below
        # is an atomic rename rather than a copy.
        rm -rf "$STAGE"
        if ! cp -R "$NEW_APP" "$STAGE"; then
            rm -rf "$STAGE"
            fail "Could not stage the new app."
        fi
        xattr -cr "$STAGE" >/dev/null 2>&1

        rm -rf "$OLD"
        if [ -e "$TARGET" ]; then
            if ! mv "$TARGET" "$OLD"; then
                rm -rf "$STAGE"
                fail "Could not move the old app aside."
            fi
        fi

        if ! mv "$STAGE" "$TARGET"; then
            # Put the old app back before giving up.
            if [ -e "$OLD" ]; then mv "$OLD" "$TARGET"; fi
            rm -rf "$STAGE"
            fail "Could not install the new app."
        fi

        rm -rf "$OLD"

        if [ "$RELAUNCH" = "1" ]; then
            sleep 1
            /bin/launchctl asuser $(id -u) /usr/bin/open "$TARGET"
        fi
        """
    }

    // MARK: - Signing identity (5A-12)

    /// What `codesign -dvv` reports about a bundle.
    struct SigningInfo: Equatable {
        var identifier: String?
        /// The `Authority=` chain, leaf first. Empty for an ad-hoc signature.
        var authorities: [String]
    }

    /// Parses `codesign -dvv` output (which goes to stderr).
    static func parseSigningInfo(_ output: String) -> SigningInfo {
        var identifier: String?
        var authorities: [String] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Identifier="), identifier == nil {
                identifier = String(trimmed.dropFirst("Identifier=".count))
            } else if trimmed.hasPrefix("Authority=") {
                authorities.append(String(trimmed.dropFirst("Authority=".count)))
            }
        }
        return SigningInfo(identifier: identifier, authorities: authorities)
    }

    /// Why `candidate` must not be installed over `running`, or nil if it may.
    ///
    /// A self-signed identity cannot be expressed as an anchored designated
    /// requirement, so the rule is "the update must be signed by exactly the
    /// same chain as the app asking for it, and must be Klip". That refuses a
    /// differently-signed bundle at the download URL, which
    /// `codesign --verify` on its own happily accepted.
    static func identityMismatchReason(candidate: SigningInfo, running: SigningInfo) -> String? {
        guard candidate.identifier == expectedBundleIdentifier else {
            return "the downloaded app identifies itself as \"\(candidate.identifier ?? "nothing")\", not \(expectedBundleIdentifier)"
        }
        guard candidate.authorities == running.authorities else {
            let signer = candidate.authorities.first ?? "no signing authority"
            let expected = running.authorities.first ?? "no signing authority"
            return "the downloaded app is signed by \(signer), but this copy of Klip is signed by \(expected)"
        }
        return nil
    }

    /// Reads a bundle's signing info via `codesign -dvv`.
    static func signingInfo(at path: String) -> SigningInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvv", path]
        let pipe = Pipe()
        // codesign writes its display output to stderr.
        process.standardError = pipe
        process.standardOutput = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parseSigningInfo(String(decoding: data, as: UTF8.self))
        } catch {
            print("[UpdateService] Failed to run codesign -dvv: \(error)")
            return nil
        }
    }

    private static func showIdentityRefusedAlert(reason: String) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = "Update Refused"
            alert.informativeText = """
            Klip did not install this update because \(reason).

            Nothing has been changed. Download the update yourself from \
            github.com/fxreza/Klip/releases if you were expecting one.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func showProgressWindow() {
        DispatchQueue.main.async {
            let w: CGFloat = 260
            let h: CGFloat = 168

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.center()

            // Blurred HUD background with rounded corners
            let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            blur.blendingMode = .behindWindow
            blur.material = .hudWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 18
            blur.layer?.masksToBounds = true
            window.contentView = blur

            // App icon
            let iconSize: CGFloat = 52
            let iconView = NSImageView(frame: NSRect(x: (w - iconSize) / 2, y: 100, width: iconSize, height: iconSize))
            iconView.image = NSApp.applicationIconImage
            iconView.imageScaling = .scaleProportionallyDown
            blur.addSubview(iconView)

            // Title
            let title = NSTextField(labelWithString: "Updating Klip...")
            title.font = .boldSystemFont(ofSize: 13)
            title.textColor = .white
            title.alignment = .center
            title.frame = NSRect(x: 0, y: 72, width: w, height: 20)
            blur.addSubview(title)

            // Subtitle
            let subtitle = NSTextField(labelWithString: "Downloading, please wait...")
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = NSColor.white.withAlphaComponent(0.55)
            subtitle.alignment = .center
            subtitle.frame = NSRect(x: 0, y: 52, width: w, height: 16)
            blur.addSubview(subtitle)

            // Spinner
            let spinner = NSProgressIndicator(frame: NSRect(x: (w - 20) / 2, y: 20, width: 20, height: 20))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            blur.addSubview(spinner)

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.progressWindow = window
            print("[UpdateService] Progress window shown")
        }
    }

    private func hideProgressWindow() {
        DispatchQueue.main.async {
            self.progressWindow?.close()
            self.progressWindow = nil
            print("[UpdateService] Progress window hidden")
        }
    }
}
