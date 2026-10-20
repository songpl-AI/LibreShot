//
//  LibreShotApp.swift
//  LibreShot
//
//  Created by Allen on 2026/2/7.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct LibreShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            // The app menu and status-bar menu share the same settings window.
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { appDelegate.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button("退出 LibreShot") { appDelegate.quitApp() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("区域截图") { appDelegate.startSelectionCapture() }
                #if DEBUG
                Button("诊断：完成长截图") { HotkeyService.shared.onLongCaptureFinishTrigger?() }
                Button("诊断：取消长截图") { HotkeyService.shared.onLongCaptureCancelTrigger?() }
                #endif
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let fullScreenImageProvider: (CGDirectDisplayID?) async throws -> NSImage
    private let fullScreenDisplayIDProvider: () -> CGDirectDisplayID?

    override init() {
        fullScreenImageProvider = { try await CaptureService.shared.captureDisplayImage(displayID: $0) }
        fullScreenDisplayIDProvider = CaptureService.displayIDAtPointer
        super.init()
    }

    init(fullScreenImageProvider: @escaping (CGDirectDisplayID?) async throws -> NSImage,
         fullScreenDisplayIDProvider: @escaping () -> CGDirectDisplayID? = CaptureService.displayIDAtPointer) {
        self.fullScreenImageProvider = fullScreenImageProvider
        self.fullScreenDisplayIDProvider = fullScreenDisplayIDProvider
        super.init()
    }

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var captureSelectionMenuItem: NSMenuItem?
    private var captureFullScreenMenuItem: NSMenuItem?
    private var longCaptureMenuItem: NSMenuItem?
    private var overlayWindowController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hotkeyObserver: NSObjectProtocol?
    private var keepAliveWindow: NSWindow?

    private var imageEditors: [ImageEditorWindowController] = []
    private var pinnedWindows: [PinnedImageWindowController] = []
    private var ocrWindowController: OCRTextLayerWindowController?
    private var imageTranslationWindows: [NSWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        MemoryTrace.mark("app_launched")
        #endif
        NSApplication.shared.setActivationPolicy(.accessory)
        setupKeepAliveWindow()
        setupStatusItem()
        setupHotkeys()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        OCRService.shared.cancelAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }
    
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "LibreShot")
        }

        let menu = NSMenu()
        
        let fullScreenItem = NSMenuItem(title: "全屏截图", action: #selector(captureFullScreen), keyEquivalent: "")
        menu.addItem(fullScreenItem)
        captureFullScreenMenuItem = fullScreenItem
        
        let selectionItem = NSMenuItem(title: "区域截图", action: #selector(captureSelection), keyEquivalent: "")
        menu.addItem(selectionItem)
        captureSelectionMenuItem = selectionItem
        
        let longCaptureItem = NSMenuItem(title: "长截图", action: #selector(captureLongScreenshot), keyEquivalent: "")
        menu.addItem(longCaptureItem)
        longCaptureMenuItem = longCaptureItem
        
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusMenu = menu
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "LibreShot（右键打开菜单）"
        }
        statusItem = item
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let action = SettingsService.shared.menuBarLeftClickAction
        if NSApp.currentEvent?.type == .rightMouseUp || action == .menu {
            guard let menu = statusMenu, let item = statusItem else { return }
            // Attach only while tracking, so AppKit can position and dismiss its menu normally.
            item.menu = menu
            sender.performClick(nil)
            item.menu = nil
            return
        }
        switch action {
        case .selection: captureSelection()
        case .fullScreen: captureFullScreen()
        case .longScreenshot: captureLongScreenshot()
        case .settings: openSettings()
        case .menu: break
        }
    }

    private func setupKeepAliveWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.orderOut(nil)
        keepAliveWindow = window
    }
    
    private func setupHotkeys() {
        // Initial registration and title update
        reregisterHotkeys()
        
        // Handle trigger
        HotkeyService.shared.onSelectionTrigger = { [weak self] in
            self?.captureSelection()
        }

        HotkeyService.shared.onDoubleOptionTrigger = { [weak self] in
            guard let self, self.overlayWindowController == nil else { return }
            self.captureSelection()
        }
        
        HotkeyService.shared.onFullScreenTrigger = { [weak self] in
            self?.captureFullScreen()
        }
        
        HotkeyService.shared.onLongScreenshotTrigger = { [weak self] in
            self?.captureLongScreenshot()
        }
        
        // Listen for hotkey changes from settings
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("Hotkey changed notification received, re-registering...")
            self?.reregisterHotkeys()
        }
    }
    
    private func reregisterHotkeys() {
        var failures: [String] = []
        HotkeyService.shared.enableDoubleOption(SettingsService.shared.doubleOptionEnabled)
        // Register Selection Shortcut
        let selKey = SettingsService.shared.shortcutKey
        let selMods = SettingsService.shared.shortcutModifiers
        
        if selKey != -1 {
            if !HotkeyService.shared.registerSelectionHotkey(keyCode: selKey, modifiers: selMods) { failures.append("区域截图") }
            let shortcutString = ShortcutUtils.string(for: selKey, modifiers: selMods)
            captureSelectionMenuItem?.title = "区域截图 (\(shortcutString))"
        } else {
            HotkeyService.shared.unregisterSelectionHotkey()
            captureSelectionMenuItem?.title = "区域截图"
        }
        
        // Register Full Screen Shortcut
        let fullKey = SettingsService.shared.fullScreenShortcutKey
        let fullMods = SettingsService.shared.fullScreenShortcutModifiers
        
        if fullKey != -1 {
            if !HotkeyService.shared.registerFullScreenHotkey(keyCode: fullKey, modifiers: fullMods) { failures.append("全屏截图") }
            let shortcutString = ShortcutUtils.string(for: fullKey, modifiers: fullMods)
            captureFullScreenMenuItem?.title = "全屏截图 (\(shortcutString))"
        } else {
            HotkeyService.shared.unregisterFullScreenHotkey()
            captureFullScreenMenuItem?.title = "全屏截图"
        }
        
        let longKey = SettingsService.shared.longScreenshotShortcutKey
        let longMods = SettingsService.shared.longScreenshotShortcutModifiers
        
        if longKey != -1 {
            if !HotkeyService.shared.registerLongScreenshotHotkey(keyCode: longKey, modifiers: longMods) { failures.append("长截图") }
            let shortcutString = ShortcutUtils.string(for: longKey, modifiers: longMods)
            longCaptureMenuItem?.title = "长截图 (\(shortcutString))"
        } else {
            HotkeyService.shared.unregisterLongScreenshotHotkey()
            longCaptureMenuItem?.title = "长截图"
        }
        SettingsService.shared.reportHotkeyRegistrationFailures(failures)
    }
    
    deinit {
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    @objc func openSettings() {
        if settingsWindowController == nil {
            let controller = SettingsWindowController()
            controller.onClose = { [weak self, weak controller] in
                guard let self, self.settingsWindowController === controller else { return }
                self.settingsWindowController = nil
            }
            settingsWindowController = controller
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func startSelectionCapture() {
        captureSelection()
    }

    @objc private func captureFullScreen() {
        // Freeze the target before asynchronous capture or editor activation moves focus.
        let displayID = fullScreenDisplayIDProvider()
        Task {
            do {
                let image = try await fullScreenImageProvider(displayID)
                SoundService.shared.playCaptureSound()
                let screen = NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
                }
                await showImageEditor(image, on: screen)
            } catch is CancellationError {
                // User cancelled, do nothing
            } catch {
                await handleCaptureError(error)
            }
        }
    }

    @objc private func captureSelection() {
        #if DEBUG
        MemoryTrace.mark("selection_started")
        #endif
        // An existing controller owns the current overlay/session. Resetting it
        // while long capture has detached the SwiftUI tree can leave a blank
        // screenSaver-level window covering the desktop and can overlap the
        // old ScreenCaptureKit stream with a new one. Ignore duplicate input
        // until the current session finishes or is cancelled.
        if overlayWindowController != nil {
            print("Capture session already active, ignoring duplicate selection shortcut")
            return
        }

        // Always create a new controller to ensure fresh state and memory cleanup on release
        let controller = OverlayWindowController()
        
        // Hold a strong reference to keep it alive during the session
        self.overlayWindowController = controller
        
        controller.show(onCapture: { [weak self, weak controller] rect, annotations, action, image in
            // Capture the specific screen where the selection happened
            // Use local controller reference to ensure we get the ID even if self?.overlayWindowController is nil
            let displayID = controller?.getCurrentDisplayID()
            // OCR is intentionally run against the exact frozen preview the
            // user selected. This avoids recognizing pixels that changed while
            // the overlay was being dismissed (and keeps annotation effects
            // on the same source as copy/save).
            let preserveExistingImage = (controller?.captureRequiresExistingPreview() ?? false) || action == .ocr
            // Release the overlay owner before the detached selection is prepared.
            // finishOverlaySession() has already cleared the SwiftUI host and
            // preview image; the callback's image argument remains independently
            // owned until prepareAreaImage() finishes.
            self?.overlayWindowController = nil
            #if DEBUG
            MemoryTrace.mark("selection_overlay_released")
            #endif
            let directRegionRequested = ProcessInfo.processInfo.environment["LIBRESHOT_DIRECT_REGION_CAPTURE"] == "1"
            let directRegionAction: Bool = [.copy, .save, .saveAs, .saveAndCopy].contains(action)
            let directRegionCanUseFreshCapture = directRegionRequested && directRegionAction && !preserveExistingImage
            self?.performAreaCapture(rect: rect, annotations: annotations, displayID: displayID,
                                     action: action, existingImage: image,
                                     preserveExistingImage: preserveExistingImage,
                                     discardExistingImage: directRegionCanUseFreshCapture)
        }, onLongCapture: { [weak self] image in
            Task { [weak self] in
                await self?.handleLongCaptureResult(image)
            }
        }, onLongCaptureError: { [weak self] error in
            Task { [weak self] in
                await self?.handleCaptureError(error)
                await MainActor.run {
                    self?.overlayWindowController = nil
                }
            }
        }, onPreviewError: { [weak self] error in
            self?.overlayWindowController = nil
            Task { [weak self] in
                await self?.handleCaptureError(error)
            }
        }, onCancel: { [weak self] in
            print("Selection cancelled")
            // Cleanup: Release the controller to free memory
            self?.overlayWindowController = nil
            #if DEBUG
            MemoryTrace.markAfterRelease("selection_cancelled")
            #endif
        })
    }
    
    @objc private func captureLongScreenshot() {
        #if DEBUG
        MemoryTrace.mark("long_capture_started")
        #endif
        if overlayWindowController != nil {
            print("Capture session already active, ignoring duplicate long-capture shortcut")
            return
        }
        
        let controller = OverlayWindowController()
        overlayWindowController = controller
        
        controller.show(captureMode: .longScreenshot, onCapture: { _, _, _, _ in
        }, onLongCapture: { [weak self] image in
            Task { [weak self] in
                await self?.handleLongCaptureResult(image)
            }
        }, onLongCaptureError: { [weak self] error in
            Task { [weak self] in
                await self?.handleCaptureError(error)
                await MainActor.run {
                    self?.overlayWindowController = nil
                }
            }
        }, onPreviewError: { [weak self] error in
            self?.overlayWindowController = nil
            Task { [weak self] in
                await self?.handleCaptureError(error)
            }
        }, onCancel: { [weak self] in
            self?.overlayWindowController = nil
        })
    }
    
    private func handleLongCaptureResult(_ image: NSImage) async {
        await MainActor.run {
            #if DEBUG
            MemoryTrace.mark("long_capture_result_received")
            #endif
            SoundService.shared.playCaptureSound()
            if SettingsService.shared.editLongCaptureAfterFinish {
                showImageEditor(image, origin: .longCaptureDocument)
                self.overlayWindowController = nil
                return
            }
            var previewWindow: PinnedImageWindowController?
            previewWindow = PinnedImageWindowController(
                image: image,
                displayMode: .longCapturePreview,
                onCopyAction: {
                    CaptureService.shared.copyToClipboard(image)
                },
                onSaveAction: { [weak self] in
                    Task { [weak self] in
                        do {
                            guard let self else { return }
                            _ = try await self.saveImage(image)
                        } catch is CancellationError {
                        } catch {
                            await self?.handleCaptureError(error)
                        }
                    }
                },
                onSaveAsAction: { [weak self] in
                    Task { [weak self] in
                        do {
                            _ = try await CaptureService.shared.saveImageWithFallback(image)
                        } catch is CancellationError {
                        } catch {
                            await self?.handleCaptureError(error)
                        }
                    }
                },
                onEditAction: { [weak self] in self?.showImageEditor(image, origin: .longCaptureDocument) }
            )
            previewWindow?.onClose = { [weak self, weak previewWindow] in
                if let previewWindow {
                    self?.pinnedWindows.removeAll { $0 === previewWindow }
                }
                #if DEBUG
                MemoryTrace.markAfterRelease("long_capture_preview_closed")
                #endif
            }
            if let previewWindow {
                pinnedWindows.append(previewWindow)
                previewWindow.showWindow(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            self.overlayWindowController = nil
            #if DEBUG
            MemoryTrace.mark("long_capture_preview_open")
            #endif
        }
    }

    private func performAreaCapture(rect: CGRect, annotations: [Annotation], displayID: CGDirectDisplayID?, action: CaptureAction,
                                    existingImage: CGImage? = nil, preserveExistingImage: Bool = false,
                                    discardExistingImage: Bool = false) {
        // Keep the direct-region path behind an environment switch so the
        // installed build can be compared against the existing full-screen path
        // without changing the default user flow.
        // Keep OCR, image translation and pin on the frozen preview even when
        // no pixel effect is present. Direct region capture is an A/B path for
        // ordinary save/copy actions only.
        let actionAllowsDirectRegion: Bool = [.copy, .save, .saveAs, .saveAndCopy].contains(action)
        let directRegionCapture = ProcessInfo.processInfo.environment["LIBRESHOT_DIRECT_REGION_CAPTURE"] == "1"
            && actionAllowsDirectRegion
            && !preserveExistingImage
        let needsCapture = directRegionCapture || existingImage == nil
        // Keep the source only until the detached crop is ready. The task is
        // intentionally scheduled after the overlay callback returns, giving
        // SwiftUI/WindowServer one run-loop turn to release its graphics backing.
        // Do not retain the full-screen callback image in the asynchronous
        // task when direct capture is selected. The overlay callback has
        // already released its owner; keeping this parameter alive would make
        // the direct region frame overlap the full-screen backing again.
        var pendingImage = (directRegionCapture || discardExistingImage) ? nil : existingImage
        Task { [weak self] in
            if needsCapture {
                // Small delay to ensure overlay window is fully closed/faded out
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            } else {
                await Task.yield()
            }
            do {
                let preparedImage: PreparedAreaImage?
                if needsCapture {
                    preparedImage = try await self?.captureAreaImage(
                        rect: rect,
                        annotations: annotations,
                        displayID: displayID,
                        action: action,
                        directRegion: directRegionCapture
                    )
                } else {
                    if let sourceImage = pendingImage {
                        preparedImage = autoreleasepool {
                            self?.prepareAreaImage(
                                NSImage(cgImage: sourceImage, size: NSSize(width: sourceImage.width, height: sourceImage.height)),
                                rect: rect,
                                annotations: annotations,
                                displayID: displayID,
                                action: action
                            )
                        }
                        // Do not let the full-screen source survive into save/OCR.
                        pendingImage = nil
                    } else {
                        preparedImage = nil
                    }
                }
                guard let preparedImage else {
                    await self?.showAlert(title: "裁剪失败", message: "无法生成区域截图")
                    return
                }
                SoundService.shared.playCaptureSound()
                try await self?.handleImageAction(preparedImage.image, action: action,
                                                  sourceRect: preparedImage.sourceRect,
                                                  pinDocument: preparedImage.pinDocument)
            } catch is CancellationError {
            } catch {
                await self?.handleCaptureError(error)
            }
        }
    }

    private typealias PreparedAreaImage = (image: NSImage, sourceRect: CGRect, pinDocument: PinnedImageDocument?)

    private func captureAreaImage(rect: CGRect, annotations: [Annotation], displayID: CGDirectDisplayID?,
                                  action: CaptureAction, directRegion: Bool = false) async throws -> PreparedAreaImage? {
        if directRegion {
            let image = try await CaptureService.shared.captureDisplayImage(displayID: displayID, sourceRect: rect)
            #if DEBUG
            MemoryTrace.mark("selection_direct_region_captured")
            #endif
            let output = compositeDirectRegion(image, annotations: annotations, cropRect: rect, displayID: displayID)
            return (output, globalAreaRect(rect, displayID: displayID), nil)
        }
        let image = try await CaptureService.shared.captureDisplayImage(displayID: displayID)
        return prepareAreaImage(image, rect: rect, annotations: annotations, displayID: displayID, action: action)
    }

    private func compositeDirectRegion(_ image: NSImage, annotations: [Annotation], cropRect: CGRect, displayID: CGDirectDisplayID?) -> NSImage {
        guard !annotations.isEmpty else { return image }
        return CaptureService.shared.compositeCropped(image: image, annotations: annotations, cropRect: cropRect, displayID: displayID)
    }

    private func globalAreaRect(_ rect: CGRect, displayID: CGDirectDisplayID?) -> CGRect {
        var screenFrame = NSScreen.main?.frame ?? .zero
        if let id = displayID, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }) { screenFrame = screen.frame }
        return CGRect(x: screenFrame.minX + rect.minX,
                      y: screenFrame.maxY - rect.minY - rect.height,
                      width: rect.width, height: rect.height)
    }

    private func prepareAreaImage(_ image: NSImage, rect: CGRect, annotations: [Annotation],
                                  displayID: CGDirectDisplayID?, action: CaptureAction) -> PreparedAreaImage? {
        autoreleasepool {
            let globalRect = globalAreaRect(rect, displayID: displayID)
            guard let cropped = CaptureService.shared.crop(image: image, to: globalRect, displayID: displayID) else { return nil }
            #if DEBUG
            MemoryTrace.mark("selection_cropped")
            #endif
            // Only a pin needs the immutable cropped base for later edits.
            // Ordinary exports release the full-display source before saving/OCR.
            let document = action == .pin
                ? PinnedImageDocument(baseImage: cropped, annotations: annotations, origin: rect.origin)
                : nil
            let output = annotations.isEmpty ? cropped
                : CaptureService.shared.compositeCropped(image: cropped, annotations: annotations, cropRect: rect, displayID: displayID)
            return (output, globalRect, document)
        }
    }
    
    @MainActor
    private func showImageEditor(_ image: NSImage, on screen: NSScreen? = nil,
                                 origin: ImageEditorImageOrigin = .generic) {
        let editor = ImageEditorWindowController(image: image, screen: screen, origin: origin)
        editor.onAction = { [weak self, weak editor] image, action in
            guard let self else { return }
            let source = action == .pin ? editor?.editableImageSource() : nil
            let document = source.map { PinnedImageDocument(baseImage: $0.image, annotations: $0.annotations) }
            try await self.handleImageAction(image, action: action, preferredScreen: editor?.window?.screen,
                                            pinDocument: action == .pin ? document : nil)
        }
        editor.onClose = { [weak self, weak editor] in
            self?.imageEditors.removeAll { $0 === editor }
            #if DEBUG
            MemoryTrace.markAfterRelease("image_editor_closed")
            #endif
        }
        imageEditors.append(editor)
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func handleImageAction(_ outputImage: NSImage, action: CaptureAction,
                                   sourceRect: CGRect? = nil, preferredScreen: NSScreen? = nil,
                                   pinDocument: PinnedImageDocument? = nil) async throws {
        switch action {
        case .save:
            _ = try await saveImage(outputImage)
        case .saveAs:
            _ = try await CaptureService.shared.saveImageWithFallback(outputImage)
        case .saveAndCopy:
            do {
                _ = try await CaptureService.shared.copyAndSaveImageDirectly(outputImage)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw NSError(domain: "LibreShot.SaveAndCopy", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "已复制，但保存失败。截图仍在剪贴板中。\n\(error.localizedDescription)"])
            }
        case .copy:
            do {
                _ = try await CaptureService.shared.completeCapture(outputImage)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                showAlert(title: "已复制，但自动保存失败", message: "截图仍在剪贴板中，可粘贴使用。\n\(error.localizedDescription)")
            }
        case .pin:
            let pinnedWindow = PinnedImageWindowController(image: CaptureService.shared.styledImage(outputImage),
                                                          sourceRect: sourceRect, document: pinDocument, screen: preferredScreen)
            pinnedWindow.onClose = { [weak self, weak pinnedWindow] in
                self?.pinnedWindows.removeAll { $0 === pinnedWindow }
            }
            pinnedWindows.append(pinnedWindow)
            pinnedWindow.showWindow(nil)
        case .ocr:
            #if DEBUG
            MemoryTrace.mark("ocr_action_started")
            #endif
            let recognized = try await OCRService.shared.recognizeRegions(from: outputImage)
            let regions = OCRTextRegion.readingOrder(from: recognized)
            let text = regions.map(\.text).joined(separator: "\n")
            ocrWindowController?.close()
            let controller = OCRTextLayerWindowController(image: outputImage, regions: regions, text: text)
            controller.onClose = { [weak self, weak controller] in
                guard let self, self.ocrWindowController === controller else { return }
                self.ocrWindowController = nil
            }
            ocrWindowController = controller
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            #if DEBUG
            MemoryTrace.mark("ocr_text_layer_window_open")
            #endif
        case .translate:
            if #available(macOS 26.0, *) {
                #if DEBUG
                MemoryTrace.mark("image_translation_window_started")
                #endif
                let controller = ImageTranslationWindowController(image: outputImage)
                controller.onAction = { [weak self] image, action in
                    if action == .copy { CaptureService.shared.copyToClipboard(image) }
                    else { try await self?.handleImageAction(image, action: action) }
                }
                controller.onEdit = { [weak self] in self?.showImageEditor($0) }
                controller.onClose = { [weak self, weak controller] in
                    self?.imageTranslationWindows.removeAll { $0 === controller }
                }
                imageTranslationWindows.append(controller)
                controller.showWindow(nil)
                #if DEBUG
                MemoryTrace.mark("image_translation_window_open")
                #endif
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Explicit Save always writes to the configured directory, independently of Auto Save.
    private func saveImage(_ image: NSImage) async throws -> URL {
        try await CaptureService.shared.saveImageDirectly(image)
    }

    @MainActor
    private func handleCaptureError(_ error: Error) async {
        if let captureError = error as? CaptureServiceError {
            guard captureError.shouldPresentAlert else { return }
            if captureError.isPermissionFailure,
               !ScreenCaptureRequestGate.shared.claimPermissionAlert() {
                return
            }
        }
        await showAlert(title: "错误", message: error.localizedDescription)
    }
    
    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
