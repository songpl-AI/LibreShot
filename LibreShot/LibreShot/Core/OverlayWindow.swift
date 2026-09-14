import AppKit

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscapeKey: (() -> Void)?
    var onConfirmKey: (() -> Void)?
    var onSaveKey: (() -> Void)?
    var onSaveAsKey: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if event.type == .keyDown, event.charactersIgnoringModifiers?.lowercased() == "s" {
            let action = modifiers == [.command, .shift] ? onSaveAsKey : (modifiers == [.command] ? onSaveKey : nil)
            if let action { action(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        // Handle Escape before the first responder (including the inline text editor).
        if event.type == .keyDown, event.keyCode == 53, let onEscapeKey {
            onEscapeKey()
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76),
           event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
           let onConfirmKey {
            onConfirmKey()
            return
        }
        super.keyDown(with: event)
    }
}

extension OverlayWindow {
    func bindEditingActions(to model: OverlayViewModel) {
        onConfirmKey = { [weak model] in
            guard let model, model.state == .editing, !model.isEditingText, !model.selectionRect.isEmpty else { return }
            model.confirmCopy()
        }
        onSaveKey = { [weak model] in
            guard let model, model.state == .editing, !model.selectionRect.isEmpty else { return }
            model.confirmSave()
        }
        onSaveAsKey = { [weak model] in
            guard let model, model.state == .editing, !model.selectionRect.isEmpty else { return }
            model.confirmSaveAs()
        }
    }

    func clearEditingActions() {
        onConfirmKey = nil
        onSaveKey = nil
        onSaveAsKey = nil
    }
}
