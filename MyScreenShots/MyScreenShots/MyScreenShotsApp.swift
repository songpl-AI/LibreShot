//
//  MyScreenShotsApp.swift
//  MyScreenShots
//
//  Created by Allen on 2026/2/7.
//

import SwiftUI
import AppKit

@main
struct MyScreenShotsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayWindowController: OverlayWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "MyScreenShots")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "全屏截图", action: #selector(captureFullScreen), keyEquivalent: "1"))
        menu.addItem(NSMenuItem(title: "区域截图", action: #selector(captureSelection), keyEquivalent: "2"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func captureFullScreen() {
        Task {
            do {
                // Default to main display for full screen shortcut
                let image = try await CaptureService.shared.captureDisplayImage()
                _ = try await CaptureService.shared.saveImageWithFallback(image)
                await playSuccessSound()
            } catch {
                await handleCaptureError(error)
            }
        }
    }

    @objc private func captureSelection() {
        overlayWindowController = OverlayWindowController()
        overlayWindowController?.show(onCapture: { [weak self] rect, annotations, action in
            // Capture the specific screen where the selection happened
            let displayID = self?.overlayWindowController?.getCurrentDisplayID()
            self?.performAreaCapture(rect: rect, annotations: annotations, displayID: displayID, action: action)
        }, onCancel: {
            print("Selection cancelled")
        })
    }

    private func performAreaCapture(rect: CGRect, annotations: [Annotation], displayID: CGDirectDisplayID?, action: CaptureAction) {
        Task {
            // Small delay to ensure overlay window is fully closed/faded out
            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            
            do {
                let fullImage = try await CaptureService.shared.captureDisplayImage(displayID: displayID)
                
                // 1. Composite annotations onto the full image
                // IMPORTANT: Pass displayID to composite to get correct scaling for that screen
                let compositedImage = CaptureService.shared.composite(image: fullImage, annotations: annotations, displayID: displayID)
                
                // 2. Crop to selection
                guard let croppedImage = CaptureService.shared.crop(image: compositedImage, to: rect, displayID: displayID) else {
                    await showAlert(title: "裁剪失败", message: "无法生成区域截图")
                    return
                }
                
                switch action {
                case .copy:
                    CaptureService.shared.copyToClipboard(croppedImage)
                    await playSuccessSound()
                case .save:
                    _ = try await CaptureService.shared.saveImageWithFallback(croppedImage)
                    await playSuccessSound()
                }
            } catch {
                await handleCaptureError(error)
            }
        }
    }
    
    @MainActor
    private func handleCaptureError(_ error: Error) async {
        let message: String
        if let captureError = error as? CaptureServiceError {
            switch captureError {
            case .permissionDenied:
                message = "请在系统设置-隐私与安全性-屏幕录制中勾选 MyScreenShots，并重新启动应用。"
            case .saveCancelled:
                return
            case .saveFailed:
                message = "保存失败，请确认已开启桌面读写权限，或选择其他保存位置。"
            default:
                message = captureError.localizedDescription
            }
        } else {
            message = error.localizedDescription
        }
        await showAlert(title: "截图失败", message: message)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @MainActor
    private func showAlert(title: String, message: String) async {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    @MainActor
    private func playSuccessSound() async {
        NSSound.beep()
    }
}
