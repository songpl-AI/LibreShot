import AppKit

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscapeKey: (() -> Void)?
    var onConfirmKey: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        // Handle Escape before the first responder (including the inline text editor).
        if event.type == .keyDown, event.keyCode == 53, let onEscapeKey {
            onEscapeKey()
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onConfirmKey?()
            return
        }
        super.keyDown(with: event)
    }
}
