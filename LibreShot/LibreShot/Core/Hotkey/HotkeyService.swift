import Cocoa
import Carbon

class HotkeyService {
    static let shared = HotkeyService()
    
    // Dictionary to store multiple hotkeys: ID -> HotKeyRef
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    
    // Callbacks for different actions
    var onSelectionTrigger: (() -> Void)?
    var onFullScreenTrigger: (() -> Void)?
    
    private let selectionHotkeyID: UInt32 = 1
    private let fullScreenHotkeyID: UInt32 = 2
    
    private init() {
        installEventHandler()
    }
    
    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        unregisterAllHotkeys()
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(eventRef,
                                         EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID),
                                         nil,
                                         MemoryLayout<EventHotKeyID>.size,
                                         nil,
                                         &hotKeyID)
            
            if status == noErr {
                Task { @MainActor in
                    HotkeyService.shared.handleHotkeyTrigger(id: hotKeyID.id)
                }
            }
            
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
    }
    
    private func handleHotkeyTrigger(id: UInt32) {
        if id == selectionHotkeyID {
            onSelectionTrigger?()
        } else if id == fullScreenHotkeyID {
            onFullScreenTrigger?()
        }
    }
    
    @discardableResult
    func registerSelectionHotkey(keyCode: Int, modifiers: Int) -> Bool {
        return registerHotkey(id: selectionHotkeyID, keyCode: keyCode, modifiers: modifiers)
    }
    
    @discardableResult
    func registerFullScreenHotkey(keyCode: Int, modifiers: Int) -> Bool {
        return registerHotkey(id: fullScreenHotkeyID, keyCode: keyCode, modifiers: modifiers)
    }
    
    func unregisterSelectionHotkey() {
        unregisterHotkey(id: selectionHotkeyID)
    }
    
    func unregisterFullScreenHotkey() {
        unregisterHotkey(id: fullScreenHotkeyID)
    }
    
    private func registerHotkey(id: UInt32, keyCode: Int, modifiers: Int) -> Bool {
        // Unregister existing one with same ID first
        unregisterHotkey(id: id)
        
        guard keyCode >= 0 else { return false }
        
        let signature = OSType(1396920910) // "SCRN"
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        
        var ref: EventHotKeyRef? = nil
        
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        
        if status == noErr, let ref = ref {
            hotKeyRefs[id] = ref
            print("Hotkey registered for ID \(id): code \(keyCode), mods \(modifiers)")
            return true
        } else {
            print("Failed to register hotkey ID \(id): \(status)")
            return false
        }
    }
    
    private func unregisterHotkey(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
    }
    
    func unregisterAllHotkeys() {
        for (id, _) in hotKeyRefs {
            unregisterHotkey(id: id)
        }
    }
    
    // Legacy support for single hotkey (mapped to selection)
    @discardableResult
    func registerHotkey(keyCode: Int, modifiers: Int) -> Bool {
        return registerSelectionHotkey(keyCode: keyCode, modifiers: modifiers)
    }
    
    func unregisterHotkey() {
        unregisterSelectionHotkey()
    }
    
    var onTrigger: (() -> Void)? {
        get { onSelectionTrigger }
        set { onSelectionTrigger = newValue }
    }
}
