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
    private let previewCaptureService = CaptureService()
    
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
    
    func show(onCapture: @escaping (CGRect, [Annotation], CaptureAction, CGImage?) -> Void, onCancel: @escaping () -> Void) {
        guard let overlayWindow = window as? OverlayWindow else { return }
        
        // 1. Reset State
        viewModel.reset()
        
        // 2. Setup Callbacks
        let cancelAction = { [weak self] in
            self?.popCrosshairCursor()
            self?.close()
            self?.viewModel.reset()
            onCancel()
        }
        
        viewModel.onCapture = { [weak self] rect, annotations, action, image in
            self?.popCrosshairCursor()
            self?.close()
            onCapture(rect, annotations, action, image)
            // Reset view model to release memory (images) after capture parameters are passed
            self?.viewModel.reset()
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
        
        viewModel.updatePreviewImage(nil)
        
        // 5. Show - Use silent show first, then activate after capture
        // Don't activate app immediately to avoid closing open menus
        // NSApp.activate(ignoringOtherApps: true) 
        
        // CRITICAL: Do NOT order front yet. Even ordering front without key can cause some menus to close
        // or trigger window server composition changes that affect the capture.
        // overlayWindow.orderFront(nil) 
        
        Task { [weak self] in
            guard let self else { return }
            do {
                // Wait a tiny bit for any previous events to settle
                try? await Task.sleep(nanoseconds: 10 * 1_000_000)
                
                let image = try await previewCaptureService.captureDisplayImage(displayID: getCurrentDisplayID())
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                
                await MainActor.run {
                    self.viewModel.updatePreviewImage(cgImage)
                    
                    // Now that we have the screenshot (including menus), we can show the window and take focus
                    overlayWindow.orderFront(nil) // Show window first
                    self.pushCrosshairCursor()
                    NSApp.activate(ignoringOtherApps: true) // Then activate app
                    overlayWindow.makeKeyAndOrderFront(nil) // Then make key
                }
            } catch {
                await MainActor.run {
                    self.viewModel.updatePreviewImage(nil)
                    // Even if failed, we need to activate to show error or allow exit
                    overlayWindow.orderFront(nil)
                    self.pushCrosshairCursor()
                    NSApp.activate(ignoringOtherApps: true)
                    overlayWindow.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    // Helper to get the display ID of the current target screen
    func getCurrentDisplayID() -> CGDirectDisplayID? {
        guard let screen = targetScreen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
    
    // Public method to reset capture session (for re-triggering while active)
    func resetCapture() {
        // 1. Reset View Model (clears selection, annotations, preview)
        viewModel.reset()
        
        // 2. Re-determine screen based on current mouse location
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        targetScreen = screen
        
        // 3. Update Window Frame
        if let target = screen, let window = window {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            window.setFrame(target.frame, display: true)
            window.contentView?.needsLayout = true
            window.layoutIfNeeded()
            NSAnimationContext.endGrouping()
        }
        
        // 4. Capture new preview image
        viewModel.updatePreviewImage(nil)
        
        // Hide window temporarily to avoid capturing itself if needed, or just stay visible
        // Since we are overlay, capturing screen usually ignores us if we use excludingWindows, 
        // but here we want to capture everything.
        // For reset, we are already active, so menus are likely already closed.
        // So we can just capture.
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await previewCaptureService.captureDisplayImage(displayID: getCurrentDisplayID())
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                await MainActor.run {
                    self.viewModel.updatePreviewImage(cgImage)
                    self.pushCrosshairCursor()
                    NSApp.activate(ignoringOtherApps: true)
                    self.window?.makeKeyAndOrderFront(nil)
                }
            } catch {
                await MainActor.run {
                    self.viewModel.updatePreviewImage(nil)
                }
            }
        }
    }
    
    deinit {
        print("OverlayWindowController deinit - Memory Released")
    }
}
