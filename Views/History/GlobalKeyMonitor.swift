import SwiftUI
import AppKit

/// Installs a local NSEvent key-down monitor for the history window and routes
/// keys to `HistoryViewModel`.
///
/// Phase 3E made this table-driven: instead of a hardcoded keycode switch,
/// every keydown is resolved to a `ShortcutAction` via
/// `ShortcutManager.shared.action(for:)`, and the dispatch below switches on
/// that action. The per-action "what happens while editing / what happens to
/// the event afterwards" behaviour is preserved exactly from the old keycode
/// switch (see the case-by-case comments) — rebinding a key changes *which*
/// event triggers an action, never what the action does once triggered.
///
/// `onBackspace` stays a closure because it needs the search field's
/// `@FocusState`, which can only live in a `View`.
struct GlobalKeyMonitor: NSViewRepresentable {
    let viewModel: HistoryViewModel
    let onBackspace: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            // Add local monitor to window
            guard view.window != nil else { return }

            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let viewModel = context.coordinator.viewModel
                let isEditing = viewModel.isEditing

                // While an inline prompt owns the keyboard, list shortcuts stand
                // down: only Esc is intercepted (to unwind one prompt layer),
                // everything else goes to the prompt's own text field. Escape
                // is fixed (not rebindable), so the raw keycode is safe here.
                if viewModel.isPromptShowing {
                    if event.keyCode == 53 {
                        viewModel.keyEscape()
                        return nil
                    }
                    return event
                }

                guard let action = ShortcutManager.shared.action(for: event) else {
                    // Unbound/unknown event: fall through untouched, exactly
                    // as the old switch's `default: return event`.
                    return event
                }

                switch action {
                // MARK: Fixed navigation keys (↑ ↓ ⇧↑ ⇧↓) — while editing,
                // let them move the text cursor instead of the selection.
                case .moveUp:
                    if isEditing { return event }
                    viewModel.scrollTrigger = true
                    viewModel.keyUp()
                    return nil
                case .moveDown:
                    if isEditing { return event }
                    viewModel.scrollTrigger = true
                    viewModel.keyDown()
                    return nil
                case .extendUp:
                    if isEditing { return event }
                    viewModel.keyExtendUp()
                    return nil
                case .extendDown:
                    if isEditing { return event }
                    viewModel.keyExtendDown()
                    return nil

                // MARK: Fixed ↩ / ⌥↩ — while editing, let Return insert a
                // newline (or do nothing) instead of pasting.
                case .paste:
                    if isEditing { return event }
                    viewModel.keyEnter()
                    return nil
                case .pastePlain:
                    if isEditing { return event }
                    viewModel.keyPastePlain()
                    return nil

                // MARK: Fixed Esc — always runs; keyEscape() itself unwinds
                // edit mode → tag input → prompt → window, one layer at a time.
                case .escape:
                    viewModel.keyEscape()
                    return nil

                // MARK: ⌘⌫ delete vs bare ⌫ clear-filter. These used to share
                // one keycode case; the two actions now carry the modifier
                // distinction themselves, but the isEditing behaviour differs
                // per action exactly as before: ⌘⌫ is swallowed as a no-op
                // while editing, but a bare ⌫ still reaches the text editor.
                case .delete:
                    if isEditing { return nil } // ⌘Delete is no-op while editing
                    viewModel.keyDelete()
                    return nil
                case .clearFilter:
                    if isEditing { return event }
                    if context.coordinator.onBackspace?() == true { return nil }
                    return event

                // MARK: ⌘C / ⌥⌘C — defer to an NSTextView first responder so
                // selected text inside e.g. the edit field copies natively.
                case .copy:
                    if isEditing { return event }
                    if let responder = view.window?.firstResponder, responder is NSTextView {
                        return event
                    }
                    viewModel.keyCopy()
                    return nil
                case .copyPlain:
                    if isEditing { return event }
                    if let responder = view.window?.firstResponder, responder is NSTextView {
                        return event
                    }
                    viewModel.keyCopyPlain()
                    return nil

                // MARK: Single-key item toggles — swallowed (not passed to
                // the text editor) while editing, same as the old ⌘P/⌘B/⌘T cases.
                case .pin:
                    if isEditing { return nil }
                    viewModel.keyPin()
                    return nil
                case .star:
                    if isEditing { return nil }
                    viewModel.keyBookmark()
                    return nil
                case .lock:
                    if isEditing { return nil }
                    viewModel.keyLock()
                    return nil
                case .addTag:
                    if isEditing { return nil }
                    viewModel.keyAddTag()
                    return nil

                // MARK: ⌘E — unconditional, exactly as before: toggles edit
                // mode on regardless of whether it is already active.
                case .edit:
                    viewModel.keyEdit()
                    return nil

                // MARK: ⌘S save-to-disk — passes through untouched while
                // editing, same as the old case.
                case .saveToDisk:
                    if isEditing { return event }
                    viewModel.keySaveImage()
                    return nil

                // MARK: ⌘[ / ⌘] scope cycling — passes through untouched
                // while editing, same as the old cases.
                case .previousScope:
                    if isEditing { return event }
                    viewModel.keyPrevScope()
                    return nil
                case .nextScope:
                    if isEditing { return event }
                    viewModel.keyNextScope()
                    return nil

                // MARK: Fixed Tab — while editing, let it move focus instead
                // of tag-completing.
                case .tabComplete:
                    if isEditing { return event }
                    viewModel.keyTabComplete()
                    return nil

                // MARK: New in 3E — organize/window actions with no prior
                // keycode case. Organize actions mirror the swallow-while-
                // editing pattern of pin/star/addTag; window toggles run
                // unconditionally like edit, since they affect layout, not
                // the text being edited.
                case .newFolder:
                    if isEditing { return nil }
                    viewModel.keyNewFolder()
                    return nil
                case .renameFolder:
                    if isEditing { return nil }
                    viewModel.keyRenameFolder()
                    return nil
                case .moveToFolder:
                    if isEditing { return nil }
                    viewModel.keyMoveToFolder()
                    return nil
                case .toggleSidebar:
                    viewModel.toggleSidebar()
                    return nil
                case .togglePreview:
                    viewModel.togglePreviewPane()
                    return nil

                // MARK: New in 3E — quick paste (⌘1…⌘9). Mirrors paste's
                // passthrough-while-editing behaviour so a stray ⌘-digit
                // doesn't fight with typing in the edit field.
                case .quickPaste1:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 1)
                    return nil
                case .quickPaste2:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 2)
                    return nil
                case .quickPaste3:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 3)
                    return nil
                case .quickPaste4:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 4)
                    return nil
                case .quickPaste5:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 5)
                    return nil
                case .quickPaste6:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 6)
                    return nil
                case .quickPaste7:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 7)
                    return nil
                case .quickPaste8:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 8)
                    return nil
                case .quickPaste9:
                    if isEditing { return event }
                    viewModel.quickPaste(index: 9)
                    return nil
                }
            }

            context.coordinator.monitor = monitor
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.onBackspace = onBackspace
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator {
        var monitor: Any?
        var viewModel: HistoryViewModel
        var onBackspace: (() -> Bool)?

        init(viewModel: HistoryViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
