import Cocoa
import Combine
import SwiftUI

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    var onEscapeKey: (() -> Void)?
    var onConfirmKey: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscapeKey?()
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            onConfirmKey?()
            return
        }
        super.keyDown(with: event)
    }
}

class OverlayWindowController: NSWindowController {
    private var cursorPushed = false
    private let viewModel = OverlayViewModel()
    private let previewCaptureService = CaptureService()
    private var currentCaptureMode: CaptureMode = .normal
    private var previousFrontmostApplication: NSRunningApplication?
    private var longCaptureGuideOverlay: LongCaptureGuideOverlay?
    private var longCaptureSession: LongCaptureSession?
    private var longCaptureStartTask: Task<Void, Never>?
    private var longCaptureSubscriptions: Set<AnyCancellable> = []
    private var longCaptureActionInFlight = false
    
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
    
    func show(
        captureMode: CaptureMode = .normal,
        onCapture: @escaping (CGRect, [Annotation], CaptureAction, CGImage?) -> Void,
        onLongCapture: ((NSImage) -> Void)? = nil,
        onLongCaptureError: ((Error) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        guard let overlayWindow = window as? OverlayWindow else { return }
        currentCaptureMode = captureMode
        
        // 1. Reset State
        cleanupLongCaptureState()
        viewModel.reset()
        viewModel.captureMode = captureMode
        viewModel.longCaptureStatusText = captureMode == .longScreenshot ? "框选目标区域，松开后直接滚动" : "拖动选择截图区域"
        
        // 2. Setup Callbacks
        let cancelAction: () -> Void = { [weak self] in
            guard let self else { return }
            self.cancelOverlayFlow(onCancel: onCancel)
        }
        
        viewModel.onCapture = { [weak self] rect, annotations, action, image in
            self?.finishOverlaySession()
            onCapture(rect, annotations, action, image)
        }
        viewModel.onLongCaptureStart = { [weak self] rect in
            self?.startLongCapture(with: rect, onFinish: onLongCapture, onError: onLongCaptureError, onCancel: onCancel)
        }
        viewModel.onCancel = cancelAction
        
        // Esc 分层：先退文字输入 → 再退工具到选择模式 → 无工具时取消截图
        overlayWindow.onEscapeKey = { [weak self] in
            guard let self else {
                cancelAction()
                return
            }
            if self.viewModel.isEditingText {
                self.viewModel.cancelTextInput()
            } else if self.viewModel.selectedTool != nil {
                self.viewModel.selectTool(nil)
            } else {
                cancelAction()
            }
        }
        overlayWindow.onConfirmKey = nil
        
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
        
        Task { [weak self] in
            guard let self else { return }
            do {
                // Wait a tiny bit for any previous events to settle
                try? await Task.sleep(nanoseconds: 10 * 1_000_000)
                
                let image = try await previewCaptureService.captureDisplayImage(displayID: getCurrentDisplayID())
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                
                // Calculate scale factor from the captured image (Pixels) vs Screen Frame (Points)
                let pixelWidth = CGFloat(cgImage?.width ?? Int(image.size.width))
                let screenWidth = self.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? pixelWidth
                let scale = pixelWidth / screenWidth
                
                await MainActor.run {
                    self.viewModel.updatePreviewImage(cgImage, scale: scale)
                    
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
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        guard let overlayWindow = window as? OverlayWindow,
              let region = makeLongCaptureRegion(from: rect) else {
            return
        }
        
        let session = LongCaptureSession(region: region)
        longCaptureSession = session
        longCaptureActionInFlight = false
        bindLongCaptureSession(session)
        updateLongCaptureStatus(progress: session.progress, status: session.status)
        longCaptureGuideOverlay?.close()
        longCaptureGuideOverlay = LongCaptureGuideOverlay(
            viewModel: viewModel,
            region: region,
            onFinish: { [weak self] in
                self?.finishLongCapture(onFinish: onFinish, onError: onError, onCancel: onCancel)
            },
            onCancel: { [weak self] in
                self?.cancelOverlayFlow(onCancel: onCancel)
            }
        )
        longCaptureGuideOverlay?.show()
        overlayWindow.orderOut(nil)
        installLongCaptureKeyMonitors(onFinish: onFinish, onError: onError, onCancel: onCancel)
        popCrosshairCursor()
        reactivatePreviousApplication()
        
        longCaptureStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await session.start()
            } catch {
                await MainActor.run {
                    self.finishOverlaySession()
                    onCancel()
                    onError?(error)
                }
            }
        }
    }
    
    private func finishLongCapture(
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        guard let session = longCaptureSession, !longCaptureActionInFlight else { return }
        longCaptureActionInFlight = true
        viewModel.longCaptureStatusText = "正在生成长截图"
        window?.ignoresMouseEvents = false
        if let overlayWindow = window as? OverlayWindow {
            overlayWindow.onConfirmKey = nil
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await session.finish()
                await MainActor.run {
                    NSApp.activate(ignoringOtherApps: true)
                    self.finishOverlaySession()
                    onFinish?(image)
                }
            } catch {
                await MainActor.run {
                    self.finishOverlaySession()
                    onCancel()
                    onError?(error)
                }
            }
        }
    }
    
    private func cancelOverlayFlow(onCancel: @escaping () -> Void) {
        guard !longCaptureActionInFlight else { return }
        if let session = longCaptureSession {
            longCaptureActionInFlight = true
            Task { [weak self] in
                await session.cancel()
                await MainActor.run {
                    self?.finishOverlaySession()
                    onCancel()
                }
            }
            return
        }
        
        finishOverlaySession()
        onCancel()
    }
    
    private func bindLongCaptureSession(_ session: LongCaptureSession) {
        longCaptureSubscriptions.removeAll()
        session.$progress
            .combineLatest(session.$status)
            .receive(on: RunLoop.main)
            .sink { [weak self] progress, status in
                self?.updateLongCaptureStatus(progress: progress, status: status)
            }
            .store(in: &longCaptureSubscriptions)
    }
    
    private func updateLongCaptureStatus(progress: LongCaptureProgress, status: LongCaptureStatus) {
        switch status {
        case .idle:
            viewModel.longCaptureStatusText = "正在准备长截图"
        case .capturing:
            if progress.acceptedFrameCount == 0 {
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
    
    private func finishOverlaySession() {
        cleanupLongCaptureState()
        popCrosshairCursor()
        window?.orderOut(nil)
        viewModel.reset()
    }
    
    private func installLongCaptureKeyMonitors(
        onFinish: ((NSImage) -> Void)?,
        onError: ((Error) -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        removeLongCaptureKeyMonitors()
        _ = HotkeyService.shared.registerLongCaptureHotkeys(
            onFinish: { [weak self] in
                self?.finishLongCapture(onFinish: onFinish, onError: onError, onCancel: onCancel)
            },
            onCancel: { [weak self] in
                self?.cancelOverlayFlow(onCancel: onCancel)
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
            finishLongCapture(onFinish: onFinish, onError: onError, onCancel: onCancel)
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
            overlayWindow.onConfirmKey = nil
        }
        previousFrontmostApplication = nil
    }
    
    // Public method to reset capture session (for re-triggering while active)
    func resetCapture() {
        // 1. Reset View Model (clears selection, annotations, preview)
        cleanupLongCaptureState()
        viewModel.reset()
        viewModel.captureMode = currentCaptureMode
        viewModel.longCaptureStatusText = currentCaptureMode == .longScreenshot ? "框选目标区域，松开后直接滚动" : "拖动选择截图区域"
        
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
                
                // Calculate scale factor from the captured image (Pixels) vs Screen Frame (Points)
                let pixelWidth = CGFloat(cgImage?.width ?? Int(image.size.width))
                let screenWidth = self.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? pixelWidth
                let scale = pixelWidth / screenWidth
                
                await MainActor.run {
                    self.viewModel.updatePreviewImage(cgImage, scale: scale)
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
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
