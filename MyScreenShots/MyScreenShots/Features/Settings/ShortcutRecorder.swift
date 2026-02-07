import SwiftUI
import Carbon

struct ShortcutRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onShortcutRecorded: ((Int, Int) -> Void)? = nil
    var onClear: (() -> Void)? = nil
    
    @State private var isRecording = false
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Main Recorder Area
            Button(action: {
                if !isRecording {
                    startRecording()
                }
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    
                    if isRecording {
                        Text("输入快捷键...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        if keyCode != -1 {
                            Text(currentShortcutString)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        } else {
                            Text("未设置")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 140, height: 28)
            }
            .buttonStyle(.plain)
            .onHover { hover in
                isHovering = hover
            }
            
            // Clear Button (only show if set and not recording)
            if keyCode != -1 && !isRecording {
                Button(action: {
                    clearShortcut()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("清除快捷键")
            }
        }
        .background(
            RecorderWindowManager(
                isRecording: $isRecording,
                onKeyRecorded: { recordedKey, recordedMods in
                    keyCode = recordedKey
                    modifiers = recordedMods
                    onShortcutRecorded?(recordedKey, recordedMods)
                },
                onCancel: {
                    isRecording = false
                }
            )
        )
    }
    
    private func startRecording() {
        print("Starting recording...")
        isRecording = true
    }
    
    private func clearShortcut() {
        keyCode = -1
        modifiers = 0
        onClear?()
    }
    
    private var currentShortcutString: String {
        return ShortcutUtils.string(for: keyCode, modifiers: modifiers)
    }
}

// Window manager to handle keyboard events using global event monitor
struct RecorderWindowManager: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onKeyRecorded: ((Int, Int) -> Void)?
    var onCancel: (() -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            context.coordinator.startMonitoring()
        } else {
            context.coordinator.stopMonitoring()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, onKeyRecorded: onKeyRecorded, onCancel: onCancel)
    }
    
    class Coordinator: NSObject {
        @Binding var isRecording: Bool
        var onKeyRecorded: ((Int, Int) -> Void)?
        var onCancel: (() -> Void)?
        private var keyDownMonitor: Any?
        private var flagsChangedMonitor: Any?
        private var currentModifiers: Int = 0
        
        init(isRecording: Binding<Bool>, onKeyRecorded: ((Int, Int) -> Void)?, onCancel: (() -> Void)?) {
            self._isRecording = isRecording
            self.onKeyRecorded = onKeyRecorded
            self.onCancel = onCancel
        }
        
        func startMonitoring() {
            guard keyDownMonitor == nil else { return }
            
            print("🔍 Starting local event monitoring...")
            currentModifiers = 0
            
            // Monitor key down events
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                
                print("📝 Key event received: keyCode=\(event.keyCode), char=\(event.charactersIgnoringModifiers ?? "nil")")
                
                // Check for Escape to cancel
                if event.keyCode == 53 {
                    print("  ↩ Escape pressed, cancelling")
                    DispatchQueue.main.async {
                        self.stopMonitoring()
                        self.onCancel?()
                    }
                    return nil // Consume the event
                }
                
                // Get current modifiers
                let carbonMods = ShortcutUtils.carbonModifiers(from: event.modifierFlags)
                
                // Validate: Must have at least one modifier key
                if carbonMods == 0 {
                    print("  ⚠️ Ignored: No modifier keys pressed (shortcuts must have ⌘/⌃/⌥/⇧)")
                    return nil // Consume but don't record
                }
                
                // Record the key
                print("  ✅ Recording: keyCode=\(event.keyCode), modifiers=\(carbonMods)")
                
                // Stop monitoring immediately to prevent multiple recordings
                DispatchQueue.main.async {
                    self.stopMonitoring()
                    self.onKeyRecorded?(Int(event.keyCode), carbonMods)
                }
                
                return nil // Consume the event
            }
            
            // Monitor modifier flags
            flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self = self else { return event }
                let carbonMods = ShortcutUtils.carbonModifiers(from: event.modifierFlags)
                self.currentModifiers = carbonMods
                print("🚩 Flags changed: modifiers=\(carbonMods)")
                return event // Don't consume flags
            }
            
            print("✅ Event monitoring started")
        }
        
        func stopMonitoring() {
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
                keyDownMonitor = nil
                print("🛑 Key down monitor removed")
            }
            if let monitor = flagsChangedMonitor {
                NSEvent.removeMonitor(monitor)
                flagsChangedMonitor = nil
                print("🛑 Flags monitor removed")
            }
            currentModifiers = 0
        }
        
        deinit {
            stopMonitoring()
        }
    }
}

struct RecorderOverlay: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var isRecording: Bool
    var onRecord: ((Int, Int) -> Void)?
    
    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.onKeyDown = { k, m in
            DispatchQueue.main.async {
                self.keyCode = k
                self.modifiers = m
                self.isRecording = false
                self.onRecord?(k, m)
            }
        }
        view.onFlagsChanged = { m in
            DispatchQueue.main.async {
                self.modifiers = m
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
        
        // Set frame to ensure the view is large enough to receive events
        view.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Request first responder through the window
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.makeFirstResponder(nsView)
                print("RecorderOverlay: Requested first responder status")
            } else {
                print("RecorderOverlay: Warning - no window available")
            }
        }
    }
}

class RecorderView: NSView {
    var onKeyDown: ((Int, Int) -> Void)?
    var onFlagsChanged: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Set a transparent background to ensure the view is visible and can receive events
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window else { return }
        
        // Make this view the first responder to capture keyboard events
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let didBecome = window.makeFirstResponder(self)
            print("RecorderView became first responder: \(didBecome)")
        }
    }
    
    override func keyDown(with event: NSEvent) {
        print("RecorderView keyDown: keyCode=\(event.keyCode)")
        
        if event.keyCode == 53 { // Escape
            print("Escape pressed, cancelling")
            onCancel?()
            return
        }
        
        // Convert NSEvent modifiers to Carbon modifiers
        let carbonModifiers = ShortcutUtils.carbonModifiers(from: event.modifierFlags)
        print("Recording shortcut: keyCode=\(event.keyCode), modifiers=\(carbonModifiers)")
        onKeyDown?(Int(event.keyCode), carbonModifiers)
    }
    
    override func flagsChanged(with event: NSEvent) {
        let carbonModifiers = ShortcutUtils.carbonModifiers(from: event.modifierFlags)
        print("Flags changed: modifiers=\(carbonModifiers)")
        onFlagsChanged?(carbonModifiers)
    }
}

struct ShortcutUtils {
    static func string(for keyCode: Int, modifiers: Int) -> String {
        var str = ""
        
        if (modifiers & cmdKey) != 0 { str += "⌘" }
        if (modifiers & shiftKey) != 0 { str += "⇧" }
        if (modifiers & optionKey) != 0 { str += "⌥" }
        if (modifiers & controlKey) != 0 { str += "⌃" }
        
        // Very basic mapping, a real app would use TISCopyCurrentKeyboardLayoutInputSource
        // For now, we assume US layout or simple mapping
        if let keyStr = keyString(for: keyCode) {
            str += keyStr
        } else {
            str += "?"
        }
        
        return str
    }
    
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var mods = 0
        if flags.contains(.command) { mods |= cmdKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.control) { mods |= controlKey }
        return mods
    }
    
    static func keyString(for keyCode: Int) -> String? {
        // Map common key codes
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_KeypadDecimal: return "."
        case kVK_ANSI_KeypadMultiply: return "*"
        case kVK_ANSI_KeypadPlus: return "+"
        case kVK_ANSI_KeypadClear: return "Clear"
        case kVK_ANSI_KeypadDivide: return "/"
        case kVK_ANSI_KeypadEnter: return "Enter"
        case kVK_ANSI_KeypadMinus: return "-"
        case kVK_ANSI_KeypadEquals: return "="
        case kVK_ANSI_Keypad0: return "0"
        case kVK_ANSI_Keypad1: return "1"
        case kVK_ANSI_Keypad2: return "2"
        case kVK_ANSI_Keypad3: return "3"
        case kVK_ANSI_Keypad4: return "4"
        case kVK_ANSI_Keypad5: return "5"
        case kVK_ANSI_Keypad6: return "6"
        case kVK_ANSI_Keypad7: return "7"
        case kVK_ANSI_Keypad8: return "8"
        case kVK_ANSI_Keypad9: return "9"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_Command: return "⌘"
        case kVK_Shift: return "⇧"
        case kVK_CapsLock: return "⇪"
        case kVK_Option: return "⌥"
        case kVK_Control: return "⌃"
        case kVK_RightShift: return "⇧"
        case kVK_RightOption: return "⌥"
        case kVK_RightControl: return "⌃"
        case kVK_Function: return "Fn"
        case kVK_F17: return "F17"
        case kVK_VolumeUp: return "Vol+"
        case kVK_VolumeDown: return "Vol-"
        case kVK_Mute: return "Mute"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F3: return "F3"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F11: return "F11"
        case kVK_F13: return "F13"
        case kVK_F16: return "F16"
        case kVK_F14: return "F14"
        case kVK_F10: return "F10"
        case kVK_F12: return "F12"
        case kVK_F15: return "F15"
        case kVK_Help: return "Help"
        case kVK_Home: return "↖"
        case kVK_PageUp: return "⇞"
        case kVK_ForwardDelete: return "⌦"
        case kVK_F4: return "F4"
        case kVK_End: return "↘"
        case kVK_F2: return "F2"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        default: return nil
        }
    }
}
