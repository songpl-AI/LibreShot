import Cocoa
import Carbon

class HotkeyService {
    static let shared = HotkeyService()
    
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var optionTap: CFMachPort?
    private var optionRunLoopSource: CFRunLoopSource?
    private var optionGesture = DoubleOptionGesture()
    
    var onSelectionTrigger: (() -> Void)?
    var onDoubleOptionTrigger: (() -> Void)?
    var onFullScreenTrigger: (() -> Void)?
    var onLongScreenshotTrigger: (() -> Void)?
    var onLongCaptureFinishTrigger: (() -> Void)?
    var onLongCaptureCancelTrigger: (() -> Void)?
    
    private let selectionHotkeyID: UInt32 = 1
    private let fullScreenHotkeyID: UInt32 = 2
    private let longCaptureFinishHotkeyID: UInt32 = 3
    private let longCaptureCancelHotkeyID: UInt32 = 4
    private let longScreenshotHotkeyID: UInt32 = 5
    
    private init() {
        installEventHandler()
    }
    
    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        unregisterAllHotkeys()
        stopDoubleOption()
    }

    @discardableResult
    func enableDoubleOption(_ enabled: Bool, requestPermission: Bool = false) -> Bool {
        stopDoubleOption()
        guard enabled else { return true }
        guard CGPreflightListenEventAccess() || (requestPermission && CGRequestListenEventAccess()) else { return false }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            // The source is installed exclusively on the main run loop.
            MainActor.assumeIsolated {
                let service = Unmanaged<HotkeyService>.fromOpaque(pointer).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    service.optionGesture = DoubleOptionGesture()
                    if let tap = service.optionTap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else if let input = NSEvent(cgEvent: event) {
                    service.handleOptionEvent(input)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        optionTap = tap
        optionRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleOptionEvent(_ event: NSEvent) {
        if optionGesture.consume(type: event.type, keyCode: event.type == .flagsChanged ? event.keyCode : 0,
                                 modifiers: event.modifierFlags, timestamp: event.timestamp) {
            // A modifier gesture must not reset an in-progress editor or shortcut recorder.
            guard !(NSApp.isActive && NSApp.keyWindow?.isVisible == true) else { return }
            onDoubleOptionTrigger?()
        }
    }

    private func stopDoubleOption() {
        if let source = optionRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = optionTap { CFMachPortInvalidate(tap) }
        optionRunLoopSource = nil
        optionTap = nil
        optionGesture = DoubleOptionGesture()
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
        } else if id == longScreenshotHotkeyID {
            onLongScreenshotTrigger?()
        } else if id == longCaptureFinishHotkeyID {
            onLongCaptureFinishTrigger?()
        } else if id == longCaptureCancelHotkeyID {
            onLongCaptureCancelTrigger?()
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
    
    @discardableResult
    func registerLongScreenshotHotkey(keyCode: Int, modifiers: Int) -> Bool {
        return registerHotkey(id: longScreenshotHotkeyID, keyCode: keyCode, modifiers: modifiers)
    }
    
    func unregisterSelectionHotkey() {
        unregisterHotkey(id: selectionHotkeyID)
    }
    
    func unregisterFullScreenHotkey() {
        unregisterHotkey(id: fullScreenHotkeyID)
    }
    
    func unregisterLongScreenshotHotkey() {
        unregisterHotkey(id: longScreenshotHotkeyID)
    }
    
    @discardableResult
    func registerLongCaptureHotkeys(onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) -> Bool {
        onLongCaptureFinishTrigger = onFinish
        onLongCaptureCancelTrigger = onCancel
        let finishRegistered = registerHotkey(id: longCaptureFinishHotkeyID, keyCode: kVK_Return, modifiers: 0)
        let cancelRegistered = registerHotkey(id: longCaptureCancelHotkeyID, keyCode: kVK_Escape, modifiers: 0)
        if finishRegistered && cancelRegistered {
            return true
        }
        unregisterLongCaptureHotkeys()
        return false
    }
    
    func unregisterLongCaptureHotkeys() {
        unregisterHotkey(id: longCaptureFinishHotkeyID)
        unregisterHotkey(id: longCaptureCancelHotkeyID)
        onLongCaptureFinishTrigger = nil
        onLongCaptureCancelTrigger = nil
    }
    
    private func registerHotkey(id: UInt32, keyCode: Int, modifiers: Int) -> Bool {
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

/// Two complete taps of the same Option key, without any intervening input.
struct DoubleOptionGesture {
    private var pressedAt: TimeInterval?
    private var previousRelease: TimeInterval?
    private var key: UInt16?

    mutating func consume(type: NSEvent.EventType, keyCode: UInt16,
                          modifiers: NSEvent.ModifierFlags, timestamp: TimeInterval) -> Bool {
        let flags = modifiers.intersection([.command, .shift, .control, .option])
        guard type == .flagsChanged, [UInt16(kVK_Option), UInt16(kVK_RightOption)].contains(keyCode),
              flags == .option || flags.isEmpty else {
            self = DoubleOptionGesture()
            return false
        }
        if flags == .option {
            if pressedAt != nil { self = DoubleOptionGesture(); return false }
            if key != keyCode || previousRelease.map({ timestamp - $0 > 0.35 || timestamp < $0 }) == true {
                previousRelease = nil
            }
            key = keyCode
            pressedAt = timestamp
            return false
        }
        guard let pressedAt, key == keyCode, timestamp >= pressedAt, timestamp - pressedAt <= 0.3 else {
            self = DoubleOptionGesture()
            return false
        }
        self.pressedAt = nil
        if let previousRelease, timestamp - previousRelease <= 0.5 {
            self = DoubleOptionGesture()
            return true
        }
        previousRelease = timestamp
        return false
    }
}
