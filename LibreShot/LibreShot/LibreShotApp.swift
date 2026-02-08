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
        // No visible scenes, app is managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var captureSelectionMenuItem: NSMenuItem?
    private var captureFullScreenMenuItem: NSMenuItem?
    private var overlayWindowController: OverlayWindowController?
    private var settingsWindowController: NSWindowController?
    private var hotkeyObserver: NSObjectProtocol?

    private var pinnedWindows: [PinnedImageWindowController] = []
    private var ocrWindowController: OCRResultWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        setupStatusItem()
        setupHotkeys()
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
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
    
    private func setupHotkeys() {
        // Initial registration and title update
        reregisterHotkeys()
        
        // Handle trigger
        HotkeyService.shared.onSelectionTrigger = { [weak self] in
            self?.captureSelection()
        }
        
        HotkeyService.shared.onFullScreenTrigger = { [weak self] in
            self?.captureFullScreen()
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
        // Register Selection Shortcut
        let selKey = SettingsService.shared.shortcutKey
        let selMods = SettingsService.shared.shortcutModifiers
        
        if selKey != -1 {
            HotkeyService.shared.registerSelectionHotkey(keyCode: selKey, modifiers: selMods)
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
            HotkeyService.shared.registerFullScreenHotkey(keyCode: fullKey, modifiers: fullMods)
            let shortcutString = ShortcutUtils.string(for: fullKey, modifiers: fullMods)
            captureFullScreenMenuItem?.title = "全屏截图 (\(shortcutString))"
        } else {
            HotkeyService.shared.unregisterFullScreenHotkey()
            captureFullScreenMenuItem?.title = "全屏截图"
        }
    }
    
    deinit {
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    @objc private func openSettings() {
        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 250),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "偏好设置"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: window)
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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func captureFullScreen() {
        Task {
            do {
                // Default to main display for full screen shortcut
                let image = try await CaptureService.shared.captureDisplayImage()
                SoundService.shared.playCaptureSound()
                _ = try await CaptureService.shared.saveImageWithFallback(image)
            } catch is CancellationError {
                // User cancelled, do nothing
            } catch {
                await handleCaptureError(error)
            }
        }
    }

    @objc private func captureSelection() {
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
        
        controller.show(onCapture: { [weak self, weak controller] rect, annotations, action in
            // Capture the specific screen where the selection happened
            // Use local controller reference to ensure we get the ID even if self?.overlayWindowController is nil
            let displayID = controller?.getCurrentDisplayID()
            self?.performAreaCapture(rect: rect, annotations: annotations, displayID: displayID, action: action)
            
            // Cleanup: Release the controller to free memory
            self?.overlayWindowController = nil
        }, onCancel: { [weak self] in
            print("Selection cancelled")
            // Cleanup: Release the controller to free memory
            self?.overlayWindowController = nil
        })
    }

    private func performAreaCapture(rect: CGRect, annotations: [Annotation], displayID: CGDirectDisplayID?, action: CaptureAction) {
        Task {
            // Small delay to ensure overlay window is fully closed/faded out
            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            
            do {
                var fullImage: NSImage? = try await CaptureService.shared.captureDisplayImage(displayID: displayID)
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

                switch action {
                case .save:
                    do {
                        _ = try await CaptureService.shared.saveImageWithFallback(outputImage)
                    } catch is CancellationError {
                        // User cancelled, do nothing
                    } catch {
                        throw error
                    }
                case .copy:
                    CaptureService.shared.copyToClipboard(outputImage)
                case .pin:
                    // Create and show pinned window
                    await MainActor.run {
                        let pinnedWindow = PinnedImageWindowController(image: outputImage)
                        pinnedWindow.onClose = { [weak self, weak pinnedWindow] in
                            if let pw = pinnedWindow {
                                self?.pinnedWindows.removeAll { $0 === pw }
                            }
                        }
                        self.pinnedWindows.append(pinnedWindow)
                        pinnedWindow.showWindow(nil)
                    }
                case .ocr:
                    // Perform OCR
                    do {
                         let text = try await OCRService.shared.recognizeText(from: outputImage)
                         await MainActor.run {
                             // Close existing OCR window if any
                             self.ocrWindowController?.close()
                             
                             let ocrWC = OCRResultWindowController(text: text)
                             self.ocrWindowController = ocrWC
                             ocrWC.showWindow(nil)
                         }
                    } catch {
                        await showAlert(title: "OCR 失败", message: error.localizedDescription)
                    }
                }
            } catch {
                await handleCaptureError(error)
            }
        }
    }

    private func handleCaptureError(_ error: Error) async {
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
