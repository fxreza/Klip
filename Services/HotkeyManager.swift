import Cocoa
import Carbon

/// Why the last `HotkeyManager.register()` failed, published for
/// `Views/Settings/ShortcutsTab.swift`.
///
/// A separate observable object rather than making `HotkeyManager` itself one:
/// the manager is owned by `AppDelegate` and never handed to SwiftUI, and the
/// Settings window is rebuilt from scratch every time it opens, so a shared
/// object is the only thing the tab can observe. `nil` means the current
/// global hotkey is registered and working.
class HotkeyRegistration: ObservableObject {
    static let shared = HotkeyRegistration()

    @Published private(set) var failureMessage: String?

    fileprivate func succeeded() {
        failureMessage = nil
    }

    /// Turns a Carbon failure (in practice always `eventHotKeyExistsErr`,
    /// -9878) into something the user can act on, by asking `SystemHotkeys`
    /// whether macOS itself holds the combination.
    fileprivate func failed(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        failureMessage = SystemHotkeys.message(for: SystemHotkeys.systemMatch(keyCode: keyCode, modifiers: modifiers))
    }
}

/// Manages global keyboard shortcut registration using Carbon API
class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    
    // Store the singleton for the C callback
    private static var instance: HotkeyManager?
    private static var eventHandlerInstalled = false
    
    init(callback: @escaping () -> Void) {
        self.callback = callback
        HotkeyManager.instance = self
    }
    
    /// Registers the global open-Klip hotkey. Returns false when macOS
    /// refused it — the combination is already held by the system or by
    /// another app — in which case `HotkeyRegistration.shared` carries the
    /// message Settings shows.
    @discardableResult
    func register() -> Bool {
        let settings = SettingsManager.shared
        print("[HotkeyManager] Registering: keyCode=\(settings.hotkeyKeyCode) mods=\(settings.hotkeyModifiers.displayString)")
        
        unregister()
        
        if !HotkeyManager.eventHandlerInstalled {
            // Install event handler
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { (nextHandler, theEvent, userData) -> OSStatus in
                    var hotKeyID = EventHotKeyID()
                    GetEventParameter(
                        theEvent,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    
                    if hotKeyID.id == 1 {
                        print("[HotkeyManager] Carbon hotkey detected!")
                        DispatchQueue.main.async {
                            HotkeyManager.instance?.callback()
                        }
                    }
                    
                    return noErr
                },
                1,
                &eventType,
                nil,
                nil
            )
            
            if status != noErr {
                print("[HotkeyManager] ❌ Failed to install event handler: \(status)")
                return false
            }
            HotkeyManager.eventHandlerInstalled = true
        }
        
        // Register the hotkey
        let requiredKeyCode = UInt32(SettingsManager.shared.hotkeyKeyCode)
        let mods = SettingsManager.shared.hotkeyModifiers
        var modifiers: UInt32 = 0
        if mods.shift { modifiers |= UInt32(shiftKey) }
        if mods.command { modifiers |= UInt32(cmdKey) }
        if mods.option { modifiers |= UInt32(optionKey) }
        if mods.control { modifiers |= UInt32(controlKey) }
        
        var hotKeyID = EventHotKeyID(signature: OSType(0x4255_4646), id: 1) // "BUFF"
        
        let registerStatus = RegisterEventHotKey(
            requiredKeyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("[HotkeyManager] ✅ Carbon hotkey registered: keyCode=\(requiredKeyCode)")
            HotkeyRegistration.shared.succeeded()
            return true
        }

        print("[HotkeyManager] ❌ Failed to register hotkey: \(registerStatus)")
        // The recorder speaks NSEvent flags, so translate the modifiers back
        // for the symbolic-hotkey lookup rather than reusing the Carbon mask.
        var eventModifiers: NSEvent.ModifierFlags = []
        if mods.shift { eventModifiers.insert(.shift) }
        if mods.command { eventModifiers.insert(.command) }
        if mods.option { eventModifiers.insert(.option) }
        if mods.control { eventModifiers.insert(.control) }
        HotkeyRegistration.shared.failed(keyCode: UInt16(settings.hotkeyKeyCode), modifiers: eventModifiers)
        return false
    }
    
    @discardableResult
    func reregister() -> Bool {
        register()
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("[HotkeyManager] Hotkey unregistered")
        }
    }
    
    deinit {
        unregister()
        HotkeyManager.instance = nil
    }
}
