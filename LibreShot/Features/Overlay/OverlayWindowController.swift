import Cocoa
import Combine
import SwiftUI

/// Join another app's fullscreen Space. Window level alone cannot cover that Space.
private let captureOverlayCollectionBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications
]

class OverlayWindowController: NSWindowController {
    private var cursorPushed = false
    private let viewModel = OverlayViewModel()
    private let previewCaptureService = CaptureService()
    var previewImageLoader: ((CGDirectDisplayID?) async throws -> NSImage)?
    private var currentCaptureMode: CaptureMode = .normal
    private var previousFrontmostApplication: NSRunningApplication?
    private var longCaptureGuideOverlay: LongCaptureGuideOverlay?
    private var longCaptureSession: LongCaptureSession?
    private var longCaptureStartTask: Task<Void, Never>?
    private var longCaptureSubscriptions: Set<AnyCancellable> = []
    private var longCaptureActionInFlight = false
    // Every show() owns one generation. Async start/finish/cancel callbacks
    // must prove that they still belong to the visible session before they
    // touch the window or release the controller.
    private var captureGeneration = UUID()
    private var previewErrorHandler: ((Error) -> Void)?
    private var previewRequestID = UUID()
    private var previewTask: Task<Void, Never>?
    // Captured before finishOverlaySession() resets the view model. The
    // application callback runs synchronously after cleanup and reads this
    // value to decide whether a direct sourceRect capture is safe.
    private var captureRequiresExistingPreviewForCallback = false
    
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
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = captureOverlayCollectionBehavior
        
        self.init(window: window)
        
        attachContentViewIfNeeded()
    }

    private func attachContentViewIfNeeded() {
        guard let window, window.contentViewController == nil else { return }
        let overlayView = OverlayView(viewModel: self.viewModel)
        let hostingController = NSHostingController(rootView: overlayView)
        hostingController.sizingOptions = [.minSize, .intrinsicContentSize, .maxSize]
        // Keep the controller type for callers that inspect its root model, but
        // use the first-click-aware host for the actual full-screen canvas.
        let drawingHost = DrawingHostingView(rootView: AnyView(overlayView))
        drawingHost.sizingOptions = []
        drawingHost.autoresizingMask = [.width, .height]
        hostingController.view = drawingHost
        window.contentViewController = hostingController
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }

    
    // Store the screen where the window is shown
    private var targetScreen: NSScreen?
    
    func show(
        captureMode: CaptureMode = .normal,
        onCapture: @escaping (CGRect, [Annotation], CaptureAction, CGImage?) -> Void,
        onLongCapture: ((NSImage) -> Void)? = nil,
        onLongCaptureError: ((Error) -> Void)? = nil,
        onPreviewError: ((Error) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        guard let overlayWindow = window as? OverlayWindow else { return }
        guard longCaptureSession == nil, longCaptureStartTask == nil else {
            print("Capture session already active, ignoring show request")
            return
        }
        attachContentViewIfNeeded()
        previewTask?.cancel()
        captureRequiresExistingPreviewForCallback = false
        currentCaptureMode = captureMode
        previewErrorHandler = onPreviewError
        let requestID = UUID()
        previewRequestID = requestID
        
        // 1. Reset State
        cleanupLongCaptureState()
        let generation = UUID()
        captureGeneration = generation
        viewModel.reset()
        viewModel.captureMode = captureMode
        viewModel.longCaptureStatusText = captureMode == .longScreenshot ? "框选目标区域，松开后直接滚动" : "拖动选择截图区域"
        
        // 2. Setup Callbacks
        let cancelAction: () -> Void = { [weak self] in
            guard let self else { return }
            self.cancelOverlayFlow(onCancel: onCancel)
        }
        
        viewModel.onCapture = { [weak self] rect, annotations, action, image in
            guard let self else { return }
            // The caller reads the display ID while submitting the final image.
            self.captureRequiresExistingPreviewForCallback = self.viewModel.captureRequiresExistingPreview
            self.finishOverlaySession(preservingTargetScreen: true)
            onCapture(rect, annotations, action, image)
            self.targetScreen = nil
        }
        viewModel.onLongCaptureStart = { [weak self] rect in
            self?.startLongCapture(with: rect, generation: generation,
                                   onFinish: onLongCapture, onError: onLongCaptureError, onCancel: onCancel)
        }
        viewModel.onCancel = cancelAction
        
        // Escape always cancels the capture, just like the toolbar's Cancel button.
        overlayWindow.onEscapeKey = cancelAction
        overlayWindow.bindEditingActions(to: viewModel)
        
        // 3. Determine Screen
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication != NSRunningApplication.current {
            previousFrontmostApplication = frontmostApplication
        }
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
        
        let previewImageLoader = self.previewImageLoader
        let requestedDisplayID = getCurrentDisplayID()
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.previewRequestID == requestID { self.previewTask = nil } }
            do {
                // Wait a tiny bit for any previous events to settle
                try await Task.sleep(nanoseconds: 10 * 1_000_000)
                guard self.previewRequestID == requestID else { return }
                
                let image: NSImage
                if let previewImageLoader {
                    image = try await previewImageLoader(requestedDisplayID)
                } else {
                    image = try await previewCaptureService.captureDisplayImage(displayID: requestedDisplayID)
                }
                try Task.checkCancellation()
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                
                // Calculate scale factor from the captured image (Pixels) vs Screen Frame (Points)
                let pixelWidth = CGFloat(cgImage?.width ?? Int(image.size.width))
                let screenWidth = self.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? pixelWidth
                let scale = pixelWidth / screenWidth
                
                await MainActor.run {
                    guard self.previewRequestID == requestID else { return }
                    self.viewModel.updatePreviewImage(cgImage, scale: scale)
                    
                    // Now that we have the screenshot (including menus), we can show the window and take focus
                    overlayWindow.orderFront(nil) // Show window first
                    self.pushCrosshairCursor()
                    NSApp.activate(ignoringOtherApps: true) // Then activate app
                    overlayWindow.makeKeyAndOrderFront(nil) // Then make key
                }
            } catch {
                await MainActor.run {
                    guard self.previewRequestID == requestID else { return }
                    self.failPreview(error)
                }
            }
        }
    }
    
    // Helper to get the display ID of the current target screen
    func getCurrentDisplayID() -> CGDirectDisplayID? {
        guard let screen = targetScreen else { return nil }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Whether the just-submitted capture must use the frozen preview image.
    /// This remains separate from the existing four-argument callback so
    /// existing test and editor clients keep their callback API unchanged.
    func captureRequiresExistingPreview() -> Bool {
        captureRequiresExistingPreviewForCallback
    }
    
    private func makeLongCaptureRegion(from rect: CGRect) -> LongCaptureRegion? {
        guard let screen = targetScreen, let displayID = getCurrentDisplayID() else { return nil }
        var globalRect = rect
        globalRect.origin.x = screen.frame.minX + rect.minX
        globalRect.origin.y = screen.frame.maxY - rect.minY - rect.height
        return LongCaptureRegion(
            selectionRect: rect,
            screenRect: globalRect,
            screenFrame: screen.frame,
            displayID: displayID
        )
    }
    
    private func startLongCapture(
        with rect: CGRect,
        generation: UUID,
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        guard captureGeneration == generation, longCaptureSession == nil else { return }
        guard let overlayWindow = window as? OverlayWindow,
              let region = makeLongCaptureRegion(from: rect) else {
            return
        }
        
        let session: LongCaptureSession
        do {
            guard let preview = viewModel.previewImage,
                  let initialImage = LongCaptureInitialFrameSource.selection(from: preview, region: region) else {
                throw LongCaptureError.noStableFrame
            }
            session = try LongCaptureSession(region: region, initialImage: initialImage)
        } catch {
            finishOverlaySession()
            onCancel()
            onError?(error)
            return
        }
        longCaptureSession = session
        longCaptureActionInFlight = false
        bindLongCaptureSession(session, generation: generation)
        updateLongCaptureStatus(progress: session.progress, status: session.status)
        longCaptureGuideOverlay?.close()
        longCaptureGuideOverlay = LongCaptureGuideOverlay(
            viewModel: viewModel,
            region: region,
            onFinish: { [weak self] in
                self?.finishLongCapture(generation: generation, onFinish: onFinish, onError: onError, onCancel: onCancel)
            },
            onCancel: { [weak self] in
                self?.cancelOverlayFlow(generation: generation, onCancel: onCancel)
            }
        )
        longCaptureGuideOverlay?.show()
        overlayWindow.orderOut(nil)
        // Only the detached selected baseline is needed by the live capture.
        // Release the full-display preview before the SCK surfaces are created.
        viewModel.updatePreviewImage(nil)
        AnnotationColorPanel.close()
        overlayWindow.contentViewController = nil
        overlayWindow.contentView = nil
        installLongCaptureKeyMonitors(generation: generation, onFinish: onFinish, onError: onError, onCancel: onCancel)
        popCrosshairCursor()
        reactivatePreviousApplication()
        
        longCaptureStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await session.start()
            } catch {
                await MainActor.run {
                    guard self.captureGeneration == generation, self.longCaptureSession === session else { return }
                    self.finishOverlaySession()
                    onCancel()
                    onError?(error)
                }
            }
        }
    }
    
    private func finishLongCapture(
        generation: UUID,
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        guard let session = longCaptureSession,
              captureGeneration == generation,
              !longCaptureActionInFlight else { return }
        longCaptureActionInFlight = true
        viewModel.longCaptureStatusText = "正在生成长截图"
        window?.ignoresMouseEvents = false
        if let overlayWindow = window as? OverlayWindow {
            overlayWindow.clearEditingActions()
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await session.finish()
                await MainActor.run {
                    guard self.captureGeneration == generation, self.longCaptureSession === session else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    self.finishOverlaySession()
                    onFinish?(image)
                }
            } catch {
                await MainActor.run {
                    guard self.captureGeneration == generation, self.longCaptureSession === session else { return }
                    self.finishOverlaySession()
                    onCancel()
                    onError?(error)
                }
            }
        }
    }
    
    private func cancelOverlayFlow(generation: UUID? = nil, onCancel: @escaping () -> Void) {
        if let generation, captureGeneration != generation { return }
        guard !longCaptureActionInFlight else { return }
        if let session = longCaptureSession {
            let sessionGeneration = captureGeneration
            longCaptureActionInFlight = true
            Task { [weak self] in
                await session.cancel()
                await MainActor.run {
                    guard let self,
                          self.captureGeneration == sessionGeneration,
                          self.longCaptureSession === session else { return }
                    self.finishOverlaySession()
                    onCancel()
                }
            }
            return
        }
        
        finishOverlaySession()
        onCancel()
    }
    
    private func bindLongCaptureSession(_ session: LongCaptureSession, generation: UUID) {
        longCaptureSubscriptions.removeAll()
        session.$progress
            .combineLatest(session.$status)
            .receive(on: RunLoop.main)
            .sink { [weak self] progress, status in
                guard let self,
                      self.captureGeneration == generation,
                      self.longCaptureSession === session else { return }
                self.updateLongCaptureStatus(progress: progress, status: status)
            }
            .store(in: &longCaptureSubscriptions)
    }
    
    private func updateLongCaptureStatus(progress: LongCaptureProgress, status: LongCaptureStatus) {
        switch status {
        case .idle:
            viewModel.longCaptureStatusText = "正在准备长截图"
        case .capturing:
            if let warning = progress.warning {
                viewModel.longCaptureStatusText = warning
            } else if progress.acceptedFrameCount == 0 {
                viewModel.longCaptureStatusText = "滚动目标区域，按回车完成，按 Esc 取消"
            } else {
                viewModel.longCaptureStatusText = "已采集 \(progress.acceptedFrameCount) 帧 · 当前高度 \(progress.appendedPixelHeight) px · 回车完成"
            }
        case .paused:
            viewModel.longCaptureStatusText = "已暂停，按回车完成，按 Esc 取消"
        case .finishing:
            viewModel.longCaptureStatusText = "正在生成长截图"
        case .completed:
            viewModel.longCaptureStatusText = "长截图已完成"
        case .cancelled:
            viewModel.longCaptureStatusText = "已取消长截图"
        case .failed(let message):
            viewModel.longCaptureStatusText = message
        }
    }
    
    override func close() {
        guard longCaptureSession != nil || longCaptureStartTask != nil else {
            finishOverlaySession()
            super.close()
            return
        }

        // NSWindowController.close() is synchronous, while ScreenCaptureKit
        // teardown is async. Keep the controller alive until the stream has
        // stopped and its output queue has drained.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancelAndWait()
            self.closeWindowAfterCleanup()
        }
    }

    private func closeWindowAfterCleanup() {
        super.close()
    }

    /// Cancel the active long-capture stream and wait until ScreenCaptureKit
    /// has stopped delivering frames before releasing the session.
    @MainActor
    func cancelAndWait() async {
        let generation = captureGeneration
        // Invalidate callbacks before awaiting teardown. A cancelled start or
        // finish task may otherwise arrive on the main actor during this wait
        // and clear a replacement session.
        captureGeneration = UUID()
        let startTask = longCaptureStartTask
        let session = longCaptureSession
        startTask?.cancel()
        if let startTask { await startTask.value }
        if let session { await session.cancel() }
        if let session {
            guard longCaptureSession === session else { return }
        } else {
            guard longCaptureSession == nil else { return }
        }
        guard captureGeneration != generation else { return }
        finishOverlaySession()
    }

    private func finishOverlaySession(preservingTargetScreen: Bool = false) {
        captureGeneration = UUID()
        previewRequestID = UUID()
        previewTask?.cancel()
        previewTask = nil
        #if DEBUG
        let hadLongSession = longCaptureSession != nil
        #endif
        cleanupLongCaptureState()
        popCrosshairCursor()
        AnnotationColorPanel.close()
        window?.orderOut(nil)
        window?.contentViewController = nil
        window?.contentView = nil
        (window as? OverlayWindow)?.onEscapeKey = nil
        viewModel.reset()
        viewModel.onCapture = nil
        viewModel.onCancel = nil
        viewModel.onLongCaptureStart = nil
        previewErrorHandler = nil
        previewImageLoader = nil
        if !preservingTargetScreen { targetScreen = nil }
        currentCaptureMode = .normal
        #if DEBUG
        if hadLongSession { MemoryTrace.markAfterRelease("long_session_released") }
        #endif
    }

    private func failPreview(_ error: Error) {
        // A blank screenSaver-level window would cover the system authorization prompt.
        let errorHandler = previewErrorHandler
        finishOverlaySession()
        errorHandler?(error)
    }
    
    private func installLongCaptureKeyMonitors(
        generation: UUID,
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        removeLongCaptureKeyMonitors()
        _ = HotkeyService.shared.registerLongCaptureHotkeys(
            onFinish: { [weak self] in
                self?.finishLongCapture(generation: generation, onFinish: onFinish, onError: onError, onCancel: onCancel)
            },
            onCancel: { [weak self] in
                self?.cancelOverlayFlow(generation: generation, onCancel: onCancel)
            }
        )
    }
    
    private func handleLongCaptureKeyEvent(
        _ event: NSEvent,
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) -> Bool {
        switch event.keyCode {
        case 53:
            cancelOverlayFlow(onCancel: onCancel)
            return true
        case 36, 76:
            finishLongCapture(generation: captureGeneration, onFinish: onFinish, onError: onError, onCancel: onCancel)
            return true
        default:
            return false
        }
    }
    
    private func removeLongCaptureKeyMonitors() {
        HotkeyService.shared.unregisterLongCaptureHotkeys()
    }
    
    private func reactivatePreviousApplication() {
        guard let previousFrontmostApplication,
              previousFrontmostApplication != NSRunningApplication.current else {
            return
        }
        previousFrontmostApplication.activate(options: [.activateIgnoringOtherApps])
    }
    
    private func cleanupLongCaptureState() {
        longCaptureStartTask?.cancel()
        longCaptureStartTask = nil
        longCaptureSession = nil
        longCaptureSubscriptions.removeAll()
        longCaptureGuideOverlay?.close()
        longCaptureGuideOverlay = nil
        removeLongCaptureKeyMonitors()
        longCaptureActionInFlight = false
        if let overlayWindow = window as? OverlayWindow {
            overlayWindow.ignoresMouseEvents = false
            overlayWindow.clearEditingActions()
        }
        previousFrontmostApplication = nil
    }
    
    // Public method to reset capture session (for re-triggering while active)
    func resetCapture() {
        // Long capture detaches the main SwiftUI tree while ScreenCaptureKit
        // owns an active stream. Reusing that controller for a normal region
        // capture would recreate an empty screenSaver-level window and leave
        // the old stream running. The app-level shortcut gate also ignores
        // this input; keep this method safe for any remaining callers.
        guard currentCaptureMode == .normal,
              longCaptureSession == nil,
              longCaptureStartTask == nil else {
            print("Long capture is active, ignoring reset request")
            return
        }
        attachContentViewIfNeeded()
        let requestID = UUID()
        previewRequestID = requestID
        previewTask?.cancel()
        captureRequiresExistingPreviewForCallback = false
        // 1. Reset View Model (clears selection, annotations, preview)
        cleanupLongCaptureState()
        viewModel.reset()
        viewModel.captureMode = currentCaptureMode
        viewModel.longCaptureStatusText = currentCaptureMode == .longScreenshot ? "框选目标区域，松开后直接滚动" : "拖动选择截图区域"
        
        (window as? OverlayWindow)?.bindEditingActions(to: viewModel)

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
        
        let previewImageLoader = self.previewImageLoader
        let requestedDisplayID = getCurrentDisplayID()
        previewTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.previewRequestID == requestID { self.previewTask = nil } }
            do {
                try Task.checkCancellation()
                let image: NSImage
                if let previewImageLoader {
                    image = try await previewImageLoader(requestedDisplayID)
                } else {
                    image = try await previewCaptureService.captureDisplayImage(displayID: requestedDisplayID)
                }
                try Task.checkCancellation()
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                
                // Calculate scale factor from the captured image (Pixels) vs Screen Frame (Points)
                let pixelWidth = CGFloat(cgImage?.width ?? Int(image.size.width))
                let screenWidth = self.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? pixelWidth
                let scale = pixelWidth / screenWidth
                
                await MainActor.run {
                    guard self.previewRequestID == requestID else { return }
                    self.viewModel.updatePreviewImage(cgImage, scale: scale)
                    self.pushCrosshairCursor()
                    NSApp.activate(ignoringOtherApps: true)
                    self.window?.makeKeyAndOrderFront(nil)
                }
            } catch {
                await MainActor.run {
                    guard self.previewRequestID == requestID else { return }
                    self.failPreview(error)
                }
            }
        }
    }
    
    deinit {
        print("OverlayWindowController deinit - Memory Released")
    }
}

private final class LongCaptureGuideOverlay {
    private let viewModel: OverlayViewModel
    private let region: LongCaptureRegion
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private var dimmingWindows: [NSWindow] = []
    private var borderWindows: [NSWindow] = []
    private var statusWindow: NSWindow?
    
    init(
        viewModel: OverlayViewModel,
        region: LongCaptureRegion,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.region = region
        self.onFinish = onFinish
        self.onCancel = onCancel
    }
    
    func show() {
        close()
        dimmingWindows = makeDimmingWindows(for: region.screenRect, in: region.screenFrame)
        dimmingWindows.forEach { $0.orderFrontRegardless() }
        borderWindows = makeBorderWindows(for: region.screenRect)
        borderWindows.forEach { $0.orderFrontRegardless() }
        let statusWindow = makeStatusWindow()
        statusWindow.orderFrontRegardless()
        self.statusWindow = statusWindow
    }
    
    func close() {
        dimmingWindows.forEach { window in
            window.orderOut(nil)
            window.contentViewController = nil
        }
        dimmingWindows.removeAll()
        borderWindows.forEach { window in
            window.orderOut(nil)
            window.contentViewController = nil
        }
        borderWindows.removeAll()
        statusWindow?.orderOut(nil)
        statusWindow?.contentViewController = nil
        statusWindow = nil
    }
    
    private func makeDimmingWindows(for rect: CGRect, in screenFrame: CGRect) -> [NSWindow] {
        let frames = [
            CGRect(
                x: screenFrame.minX,
                y: rect.maxY,
                width: screenFrame.width,
                height: max(0, screenFrame.maxY - rect.maxY)
            ),
            CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: max(0, rect.minY - screenFrame.minY)
            ),
            CGRect(
                x: screenFrame.minX,
                y: rect.minY,
                width: max(0, rect.minX - screenFrame.minX),
                height: rect.height
            ),
            CGRect(
                x: rect.maxX,
                y: rect.minY,
                width: max(0, screenFrame.maxX - rect.maxX),
                height: rect.height
            )
        ]
        return frames
            .filter { $0.width > 0 && $0.height > 0 }
            .map(makeDimmingWindow(frame:))
    }
    
    private func makeDimmingWindow(frame: CGRect) -> NSWindow {
        let window = LongCaptureBorderWindow(
            contentRect: frame.integral,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor.black.withAlphaComponent(0.28)
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        // SCK excludes our application from the long-capture stream. Keep the
        // guide UI readable so remote desktops can display it to the user.
        window.sharingType = .readOnly
        window.collectionBehavior = captureOverlayCollectionBehavior
        return window
    }
    
    private func makeBorderWindows(for rect: CGRect) -> [NSWindow] {
        let thickness: CGFloat = 2
        let frames = [
            CGRect(x: rect.minX, y: rect.maxY - thickness, width: rect.width, height: thickness),
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: thickness),
            CGRect(x: rect.minX, y: rect.minY, width: thickness, height: rect.height),
            CGRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: rect.height)
        ]
        return frames
            .filter { $0.width > 0 && $0.height > 0 }
            .map(makeBorderWindow(frame:))
    }
    
    private func makeBorderWindow(frame: CGRect) -> NSWindow {
        let window = LongCaptureBorderWindow(
            contentRect: frame.integral,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = NSColor.white.withAlphaComponent(0.95)
        window.isOpaque = false
        window.hasShadow = true
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        // SCK excludes our application from the long-capture stream. Keep the
        // guide UI readable so remote desktops can display it to the user.
        window.sharingType = .readOnly
        window.collectionBehavior = captureOverlayCollectionBehavior
        return window
    }
    
    private func makeStatusWindow() -> NSWindow {
        let statusSize = NSSize(width: 320, height: 42)
        let frame = statusFrame(size: statusSize)
        let window = LongCaptureStatusWindow(
            contentRect: frame.integral,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        // SCK excludes our application from the long-capture stream. Keep the
        // guide UI readable so remote desktops can display it to the user.
        window.sharingType = .readOnly
        window.collectionBehavior = captureOverlayCollectionBehavior
        window.contentViewController = NSHostingController(
            rootView: LongCaptureFloatingStatusView(
                viewModel: viewModel,
                onFinish: onFinish,
                onCancel: onCancel
            )
        )
        return window
    }
    
    private func statusFrame(size: NSSize) -> CGRect {
        let horizontalMargin: CGFloat = 12
        let verticalMargin: CGFloat = 12
        let preferredOriginY = region.screenRect.maxY + verticalMargin
        let hasSpaceAbove = preferredOriginY + size.height <= region.screenFrame.maxY - verticalMargin
        let originY = hasSpaceAbove
            ? preferredOriginY
            : max(region.screenRect.minY - size.height - verticalMargin, region.screenFrame.minY + verticalMargin)
        let originX = min(
            max(region.screenRect.midX - size.width / 2, region.screenFrame.minX + horizontalMargin),
            region.screenFrame.maxX - size.width - horizontalMargin
        )
        return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
    }
}

private final class LongCaptureBorderWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LongCaptureStatusWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct LongCaptureFloatingStatusView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let onFinish: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
            Text(viewModel.longCaptureStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("取消") {
                onCancel()
            }
            .buttonStyle(LongCaptureStatusButtonStyle())
            Button("完成") {
                onFinish()
            }
            .buttonStyle(LongCaptureStatusButtonStyle(primary: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 320, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 5)
    }
}

private struct LongCaptureStatusButtonStyle: ButtonStyle {
    var primary = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(primary ? .black : .white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(primary ? Color.white.opacity(configuration.isPressed ? 0.78 : 0.92) : Color.white.opacity(configuration.isPressed ? 0.10 : 0.16))
            )
    }
}
