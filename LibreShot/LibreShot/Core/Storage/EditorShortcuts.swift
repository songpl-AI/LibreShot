import AppKit
import Carbon

struct EditorShortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int

    var title: String { ShortcutUtils.string(for: keyCode, modifiers: modifiers) }

    static let defaults: [String: EditorShortcut] = [
        ToolbarItem.save.rawValue: .init(keyCode: kVK_ANSI_S, modifiers: cmdKey),
        ToolbarItem.saveAs.rawValue: .init(keyCode: kVK_ANSI_S, modifiers: cmdKey | shiftKey),
        ToolbarItem.complete.rawValue: .init(keyCode: kVK_Return, modifiers: 0),
        ToolbarItem.undo.rawValue: .init(keyCode: kVK_ANSI_Z, modifiers: cmdKey)
    ]

    var isAllowed: Bool {
        guard (0...127).contains(keyCode), modifiers & ~(cmdKey | shiftKey | optionKey | controlKey) == 0 else { return false }
        if [kVK_Escape, kVK_Space, kVK_Tab, kVK_Delete, kVK_ForwardDelete,
            kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option,
            kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function].contains(keyCode) { return false }
        // Leave editing, window management and application commands with AppKit.
        if modifiers & cmdKey != 0,
           [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Q,
            kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Comma].contains(keyCode) { return false }
        return true
    }

    func matches(_ event: NSEvent) -> Bool {
        let key = event.keyCode == kVK_ANSI_KeypadEnter ? kVK_Return : Int(event.keyCode)
        let ownKey = keyCode == kVK_ANSI_KeypadEnter ? kVK_Return : keyCode
        return key == ownKey && modifiers == ShortcutUtils.carbonModifiers(from: event.modifierFlags)
    }

    func conflicts(with other: EditorShortcut) -> Bool {
        let a = keyCode == kVK_ANSI_KeypadEnter ? kVK_Return : keyCode
        let b = other.keyCode == kVK_ANSI_KeypadEnter ? kVK_Return : other.keyCode
        return a == b && modifiers == other.modifiers
    }
}

enum EditorSpaceAction: String, CaseIterable {
    case disabled, complete, saveAndCopy

    var title: String {
        switch self {
        case .disabled: return "关闭"
        case .complete: return "完成"
        case .saveAndCopy: return "保存并复制"
        }
    }
}
