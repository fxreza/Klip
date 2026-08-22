import SwiftUI
import AppKit

/// Installs a local NSEvent key-down monitor for the history window and routes
/// keys to `HistoryViewModel`.
///
/// The keycode switch is still hardcoded — Phase 3E makes it table-driven.
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
                switch event.keyCode {
                case 126: // Up
                    if isEditing { return event }
                    if event.modifierFlags.contains(.shift) {
                        viewModel.keyExtendUp()
                    } else {
                        viewModel.keyUp()
                    }
                    return nil // Consume event
                case 125: // Down
                    if isEditing { return event }
                    if event.modifierFlags.contains(.shift) {
                        viewModel.keyExtendDown()
                    } else {
                        viewModel.keyDown()
                    }
                    return nil // Consume event
                case 36: // Enter
                    if isEditing { return event }
                    viewModel.keyEnter()
                    return nil
                case 53: // Escape
                    viewModel.keyEscape()
                    return nil
                case 51: // Delete/Backspace
                    if isEditing {
                        if event.modifierFlags.contains(.command) {
                            return nil // ⌘Delete is no-op
                        }
                        return event
                    }
                    if event.modifierFlags.contains(.command) {
                        viewModel.keyDelete()
                        return nil
                    }
                    if context.coordinator.onBackspace?() == true { return nil }
                    return event
                case 8: // C (for Copy)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return event }
                        // If text is selected in a text view, let the system handle native copy
                        if let responder = view.window?.firstResponder, responder is NSTextView {
                            return event
                        }
                        viewModel.keyCopy()
                        return nil
                    }
                    return event
                case 35: // Cmd+P (P is 35)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        viewModel.keyPin()
                        return nil
                    }
                    return event
                case 11: // Cmd+B (B is 11)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        viewModel.keyBookmark()
                        return nil
                    }
                    return event
                case 1: // Cmd+S (S is 1)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return event }
                        viewModel.keySaveImage()
                        return nil
                    }
                    return event
                case 17: // Cmd+T (T is 17)
                    if event.modifierFlags.contains(.command) {
                        if isEditing { return nil }
                        viewModel.keyAddTag()
                        return nil
                    }
                    return event
                case 14: // Cmd+E (E is 14)
                    if event.modifierFlags.contains(.command) {
                        viewModel.keyEdit()
                        return nil
                    }
                    return event
                case 48: // Tab
                    if isEditing { return event }
                    viewModel.keyTabComplete()
                    return nil
                default:
                    return event
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
