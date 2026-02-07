import Cocoa
import Carbon

class HotkeyService {
    static let shared = HotkeyService()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onTrigger: (() -> Void)?
    
    private init() {
        installEventHandler()
    }
    
    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        unregisterHotkey()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        // Convert Swift function to C function pointer
        // Using explicit EventHandlerUPP closure to match C convention
        let handler: EventHandlerUPP = { _, _, _ -> OSStatus in
            Task { @MainActor in
                HotkeyService.shared.onTrigger?()
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
    }
    
    @discardableResult
    func registerHotkey(keyCode: Int, modifiers: Int) -> Bool {
        unregisterHotkey()
        
        guard keyCode >= 0 else { return false }
        
        // OSType is UInt32
        let signature = OSType(1396920910) // "SCRN" in decimal: 'S'<<24 + 'C'<<16 + 'R'<<8 + 'N'
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        
        var ref: EventHotKeyRef? = nil
        
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        
        if status == noErr {
            hotKeyRef = ref
            print("Hotkey registered: code \(keyCode), mods \(modifiers)")
            return true
        } else {
            print("Failed to register hotkey: \(status)")
            return false
        }
    }
    
    func unregisterHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
