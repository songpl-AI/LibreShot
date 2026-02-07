import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    var onEscapeKey: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscapeKey?()
            return
        }
        super.keyDown(with: event)
    }
}

class OverlayWindowController: NSWindowController {
    private var cursorPushed = false
    private let viewModel = OverlayViewModel()
    
    private func pushCrosshairCursor() {
        if !cursorPushed {
            NSCursor.crosshair.push()
            cursorPushed = true
        }
    }
    
    private func popCrosshairCursor() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
    
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
        
        // Setup Content View Controller once
        let overlayView = OverlayView(viewModel: self.viewModel)
        // Use a subclass or configuration to avoid auto-layout constraints on the root view if possible
        // Or simply add the view directly to contentView without constraints if using pure frame layout
        
        let hostingController = NSHostingController(rootView: overlayView)
        // IMPORTANT: Set sizing options to avoid constraint conflicts
        hostingController.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        
        window.contentViewController = hostingController
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }

    
    // Store the screen where the window is shown
    private var targetScreen: NSScreen?
    
    func show(onCapture: @escaping (CGRect, [Annotation], CaptureAction) -> Void, onCancel: @escaping () -> Void) {
        guard let overlayWindow = window as? OverlayWindow else { return }
        
        // 1. Reset State
        viewModel.reset()
        
        // 2. Setup Callbacks
        let cancelAction = { [weak self] in
            self?.popCrosshairCursor()
            self?.close()
            onCancel()
        }
        
        viewModel.onCapture = { [weak self] rect, annotations, action in
            self?.popCrosshairCursor()
            self?.close()
            onCapture(rect, annotations, action)
        }
        viewModel.onCancel = cancelAction
        
        overlayWindow.onEscapeKey = cancelAction
        
        // 3. Determine Screen
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        targetScreen = screen
        
        // 4. Update Window Frame
        if let target = screen {
            // Disable animation for instant appearance
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            overlayWindow.setFrame(target.frame, display: true)
            // Force layout update after frame change to sync view bounds
            overlayWindow.contentView?.needsLayout = true
            overlayWindow.layoutIfNeeded()
            NSAnimationContext.endGrouping()
        }
        
        // 5. Show
        pushCrosshairCursor()
        NSApp.activate(ignoringOtherApps: true)
        overlayWindow.makeKeyAndOrderFront(nil)
    }
    
    // Helper to get the display ID of the current target screen
    func getCurrentDisplayID() -> CGDirectDisplayID? {
        guard let screen = targetScreen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
