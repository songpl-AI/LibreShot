import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}

class OverlayWindowController: NSWindowController {
    
    convenience init() {
        // Create a borderless, transparent window that covers the screen
        let screenRect = NSScreen.main?.frame ?? .zero
        let window = OverlayWindow(
            contentRect: screenRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.init(window: window)
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }

    
    // Store the screen where the window is shown
    private var targetScreen: NSScreen?
    
    func show(onCapture: @escaping (CGRect, [Annotation], CaptureAction) -> Void, onCancel: @escaping () -> Void) {
        guard let window = window else { return }
        
        // Use the screen containing the mouse cursor
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main
        targetScreen = screen
        
        if let target = screen {
            window.setFrame(target.frame, display: true)
        }
        
        let overlayView = OverlayView(onCapture: { [weak self] rect, annotations, action in
            self?.close()
            onCapture(rect, annotations, action)
        }, onCancel: { [weak self] in
            self?.close()
            onCancel()
        })
        
        window.contentView = NSHostingView(rootView: overlayView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Helper to get the display ID of the current target screen
    func getCurrentDisplayID() -> CGDirectDisplayID? {
        guard let screen = targetScreen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
