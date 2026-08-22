// Ported from Clipfield's HotkeyRecorder (MIT, Copyright 2026 Alex Jolley):
// reference/clipfield/Sources/Clipfield/UI/Settings/HotkeyRecorder.swift.
// Restyled with Klip's `Theme` tokens and generalized to record any
// `KeyBinding` (Models/KeyBinding.swift) instead of only the single global
// hotkey, so it can back every row in `Views/Settings/ShortcutsTab.swift` as
// well as the Global row (which still writes through to
// `SettingsManager.hotkeyModifiers`/`hotkeyKeyCode`).

import SwiftUI
import AppKit

/// A click-to-record control that captures a key + modifier combination.
/// Reports the recorded `KeyBinding` via `onRecord`. Escape cancels an
/// in-progress recording; recording a bare Escape key itself is impossible
/// as a result (matching Clipfield's original behavior).
struct HotkeyRecorder: NSViewRepresentable {
    var display: String
    var isRebindable: Bool = true
    var onRecord: (KeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.display = display
        view.isRebindable = isRebindable
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.isRebindable = isRebindable
        view.onRecord = onRecord
        if !view.isRecording {
            view.display = display
            view.needsDisplay = true
        }
    }
}

final class RecorderView: NSView {
    var display: String = ""
    var isRebindable: Bool = true {
        didSet { needsDisplay = true }
    }
    var isRecording = false {
        didSet { needsDisplay = true }
    }
    var onRecord: ((KeyBinding) -> Void)?

    private static let textFontSize: CGFloat = 12 // semantic: .footnote

    override var acceptsFirstResponder: Bool { isRebindable }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            xRadius: Theme.badgeCornerRadius,
            yRadius: Theme.badgeCornerRadius
        )
        let accent = NSColor(Theme.accent)
        let fill: NSColor
        if isRecording {
            fill = accent.withAlphaComponent(0.18)
        } else if isRebindable {
            fill = .controlBackgroundColor
        } else {
            fill = NSColor.controlBackgroundColor.withAlphaComponent(0.5)
        }
        fill.setFill()
        path.fill()

        let stroke = isRecording ? accent : NSColor.separatorColor.withAlphaComponent(isRebindable ? 1 : 0.5)
        stroke.setStroke()
        path.stroke()

        let text: String
        if !isRebindable {
            text = display
        } else if isRecording {
            text = "Press shortcut…"
        } else {
            text = display.isEmpty ? "Click to record" : display
        }

        let color: NSColor
        if isRecording {
            color = accent
        } else if isRebindable {
            color = .labelColor
        } else {
            color = .tertiaryLabelColor
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: RecorderView.textFontSize, weight: .medium),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        guard isRebindable else { return }
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording rather than being recordable itself.
        if event.keyCode == 53 {
            isRecording = false
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let mods = KeyModifiers(eventFlags: flags)

        // Require at least one of ⌘⌃⌥ so a rebind can't collide with
        // ordinary typing (shift-only is not sufficient).
        guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
            NSSound.beep()
            return
        }

        onRecord?(KeyBinding(keyCode: event.keyCode, modifiers: mods))
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }
}
