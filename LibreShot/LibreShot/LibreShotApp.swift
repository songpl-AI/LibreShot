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
            #if DEBUG
            CommandGroup(after: .appSettings) {
                Button("诊断：区域截图") { appDelegate.startDiagnosticSelectionCapture() }
                Button("诊断：完成长截图") { HotkeyService.shared.onLongCaptureFinishTrigger?() }
                Button("诊断：取消长截图") { HotkeyService.shared.onLongCaptureCancelTrigger?() }
            }
            #endif
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var captureSelectionMenuItem: NSMenuItem?
    private var captureFullScreenMenuItem: NSMenuItem?
    private var longCaptureMenuItem: NSMenuItem?
    private var overlayWindowController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hotkeyObserver: NSObjectProtocol?
    private var keepAliveWindow: NSWindow?

    private var imageEditors: [ImageEditorWindowController] = []
    private var pinnedWindows: [PinnedImageWindowController] = []
    private var ocrWindowController: OCRResultWindowController?
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
        menu.addItem(NSMenuItem(title: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
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
    
    @objc private func checkForUpdates() {
        // Check for updates by opening the GitHub Releases page
        if let url = URL(string: "https://github.com/songpl-AI/LibreShot/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    #if DEBUG
    func startDiagnosticSelectionCapture() {
        captureSelection()
    }
    #endif

    @objc private func captureFullScreen() {
        Task {
            do {
                // Default to main display for full screen shortcut
                let image = try await CaptureService.shared.captureDisplayImage()
                SoundService.shared.playCaptureSound()
                _ = try await saveImage(image)
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
        // If an overlay controller already exists, it means a capture session is active.
        // We should focus it or reset it, rather than creating a duplicate or overwriting it.
        if let existing = overlayWindowController {
            print("Capture session already active, resetting and bringing to front")
            // Reset state to allow fresh capture (e.g. if user wants to restart selection)
            existing.resetCapture()
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
            self?.performAreaCapture(rect: rect, annotations: annotations, displayID: displayID, action: action, existingImage: image)
            
            // Cleanup: Release the controller to free memory
            self?.overlayWindowController = nil
            #if DEBUG
            MemoryTrace.mark("selection_overlay_released")
            #endif
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
        if let existing = overlayWindowController {
            existing.close()
            overlayWindowController = nil
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
                showImageEditor(image)
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
                onEditAction: { [weak self] in self?.showImageEditor(image) }
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

    private func performAreaCapture(rect: CGRect, annotations: [Annotation], displayID: CGDirectDisplayID?, action: CaptureAction, existingImage: CGImage? = nil) {
        Task {
            // Only sleep if we don't have an existing image (meaning we need to capture NOW, so we need overlay to be gone)
            if existingImage == nil {
                // Small delay to ensure overlay window is fully closed/faded out
                try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            }
            
            do {
                var fullImage: NSImage?
                if let existing = existingImage {
                    let size = NSSize(width: existing.width, height: existing.height)
                    fullImage = NSImage(cgImage: existing, size: size)
                } else {
                    fullImage = try await CaptureService.shared.captureDisplayImage(displayID: displayID)
                }
                
                guard let capturedImage = fullImage else {
                    await showAlert(title: "截图失败", message: "无法获取屏幕图像")
                    return
                }

                // Find screen frame to convert coordinates
                var screenFrame = NSScreen.main?.frame ?? .zero
                if let id = displayID, let screen = NSScreen.screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
                }) {
                    screenFrame = screen.frame
                }

                // Convert SwiftUI/Window coordinates (Top-Left relative to screen)
                // to AppKit Global coordinates (Bottom-Left relative to primary screen)
                var globalRect = rect
                globalRect.origin.x = screenFrame.minX + rect.minX
                globalRect.origin.y = screenFrame.maxY - rect.minY - rect.height

                var croppedImage: NSImage?
                autoreleasepool {
                    croppedImage = CaptureService.shared.crop(image: capturedImage, to: globalRect, displayID: displayID)
                }
                fullImage = nil

                guard let cropped = croppedImage else {
                    await showAlert(title: "裁剪失败", message: "无法生成区域截图")
                    return
                }
                #if DEBUG
                MemoryTrace.mark("selection_cropped")
                #endif

                let outputImage: NSImage
                if annotations.isEmpty {
                    outputImage = cropped
                } else {
                    var composited: NSImage?
                    autoreleasepool {
                        composited = CaptureService.shared.compositeCropped(image: cropped, annotations: annotations, cropRect: rect, displayID: displayID)
                    }
                    outputImage = composited ?? cropped
                }

                SoundService.shared.playCaptureSound()

                try await handleImageAction(outputImage, action: action)
            } catch is CancellationError {
            } catch {
                await handleCaptureError(error)
            }
        }
    }
    
    @MainActor
    private func showImageEditor(_ image: NSImage) {
        let editor = ImageEditorWindowController(image: image)
        editor.onAction = { [weak self] image, action in
            guard let self else { return }
            try await self.handleImageAction(image, action: action)
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
    private func handleImageAction(_ outputImage: NSImage, action: CaptureAction) async throws {
        switch action {
        case .save:
            _ = try await saveImage(outputImage)
        case .saveAs:
            _ = try await CaptureService.shared.saveImageWithFallback(outputImage)
        case .saveAndCopy:
            do {
                _ = try await CaptureService.shared.copyAndSaveImageDirectly(outputImage)
            } catch {
                throw NSError(domain: "LibreShot.SaveAndCopy", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "已复制，但保存失败。截图仍在剪贴板中。\n\(error.localizedDescription)"])
            }
        case .copy:
            do {
                _ = try await CaptureService.shared.completeCapture(outputImage)
            } catch {
                showAlert(title: "已复制，但自动保存失败", message: "截图仍在剪贴板中，可粘贴使用。\n\(error.localizedDescription)")
            }
        case .pin:
            let pinnedWindow = PinnedImageWindowController(image: CaptureService.shared.styledImage(outputImage))
            pinnedWindow.onClose = { [weak self, weak pinnedWindow] in
                self?.pinnedWindows.removeAll { $0 === pinnedWindow }
            }
            pinnedWindows.append(pinnedWindow)
            pinnedWindow.showWindow(nil)
        case .ocr:
            #if DEBUG
            MemoryTrace.mark("ocr_action_started")
            #endif
            let text = try await OCRService.shared.recognizeText(from: outputImage)
            ocrWindowController?.close()
            let controller = OCRResultWindowController(text: text)
            ocrWindowController = controller
            controller.showWindow(nil)
            #if DEBUG
            MemoryTrace.mark("ocr_result_window_open")
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

    /// 统一保存入口：自动保存开关开启时直接写盘，否则弹保存面板。
    private func saveImage(_ image: NSImage) async throws -> URL {
        if SettingsService.shared.autoSaveEnabled {
            return try await CaptureService.shared.saveImageDirectly(image)
        } else {
            return try await CaptureService.shared.saveImageWithFallback(image)
        }
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
