//
//  MyScreenShotsApp.swift
//  MyScreenShots
//
//  Created by Allen on 2026/2/7.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct MyScreenShotsApp: App {
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
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "MyScreenShots")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "全屏截图", action: #selector(captureFullScreen), keyEquivalent: "1"))
        menu.addItem(NSMenuItem(title: "区域截图", action: #selector(captureSelection), keyEquivalent: "2"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
    
    private func setupHotkeys() {
        // Register saved hotkey
        let savedKey = SettingsService.shared.shortcutKey
        let savedMods = SettingsService.shared.shortcutModifiers
        if savedKey != -1 {
            HotkeyService.shared.registerHotkey(keyCode: savedKey, modifiers: savedMods)
        }
        
        // Handle trigger
        HotkeyService.shared.onTrigger = { [weak self] in
            self?.captureSelection()
        }
        
        // Listen for hotkey changes from settings
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("Hotkey changed notification received, re-registering...")
            self?.reregisterHotkey()
        }
    }
    
    private func reregisterHotkey() {
        let keyCode = SettingsService.shared.shortcutKey
        let modifiers = SettingsService.shared.shortcutModifiers
        
        if keyCode != -1 {
            HotkeyService.shared.registerHotkey(keyCode: keyCode, modifiers: modifiers)
        } else {
            HotkeyService.shared.unregisterHotkey()
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
            window.title = "设置"
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView())
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
        let controller: OverlayWindowController
        if let existing = overlayWindowController {
            controller = existing
        } else {
            let created = OverlayWindowController()
            overlayWindowController = created
            controller = created
        }
        controller.show(onCapture: { [weak self] rect, annotations, action in
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
                var fullImage: NSImage? = try await CaptureService.shared.captureDisplayImage(displayID: displayID)
                guard let capturedImage = fullImage else {
                    await showAlert(title: "截图失败", message: "无法获取屏幕图像")
                    return
                }

                var croppedImage: NSImage?
                autoreleasepool {
                    croppedImage = CaptureService.shared.crop(image: capturedImage, to: rect, displayID: displayID)
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

                switch action {
                case .copy:
                    CaptureService.shared.copyToClipboard(outputImage)
                    await playSuccessSound()
                case .save:
                    _ = try await CaptureService.shared.saveImageWithFallback(outputImage)
                    await playSuccessSound()
                case .pin:
                    await pinImageToScreen(image: outputImage)
                    await playSuccessSound()
                case .ocr:
                    let text = try await CaptureService.shared.recognizeText(in: cropped)
                    await showOCRResult(text: text)
                }
            } catch {
                await handleCaptureError(error)
            }
        }
    }
    
    @MainActor
    private func pinImageToScreen(image: NSImage) {
        let controller = PinnedImageWindowController(image: image)
        controller.showWindow(nil)
        pinnedWindows.append(controller)
        
        // Listen for window close to cleanup
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: controller.window, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let window = notification.object as? NSWindow,
               let index = self.pinnedWindows.firstIndex(where: { $0.window === window }) {
                self.pinnedWindows.remove(at: index)
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

    @MainActor
    private func showOCRResult(text: String) async {
        if let existing = ocrWindowController {
            existing.close()
        }
        let controller = OCRResultWindowController(text: text, onCopy: { [weak self] content in
            self?.copyTextToClipboard(content)
        })
        ocrWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

final class OCRResultWindowController: NSWindowController {
    init(text: String, onCopy: @escaping (String) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OCR 结果"
        window.isReleasedWhenClosed = false
        window.center()
        let view = OCRResultView(text: text, onCopy: onCopy, onClose: {
            window.close()
        })
        window.contentView = NSHostingView(rootView: view)
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct OCRResultView: View {
    @State private var text: String
    @State private var selectedRange: NSRange = NSRange(location: 0, length: 0)
    var onCopy: (String) -> Void
    var onClose: () -> Void

    init(text: String, onCopy: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _text = State(initialValue: text)
        self.onCopy = onCopy
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("OCR 结果")
                    .font(.headline)
                Spacer()
                Button("复制选中") {
                    if let range = Range(selectedRange, in: text) {
                        onCopy(String(text[range]))
                    }
                }
                .disabled(selectedRange.length == 0)
                Button("复制全部") {
                    onCopy(text)
                }
                Button("关闭") {
                    onClose()
                }
            }
            OCRTextView(text: $text, selectedRange: $selectedRange)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
    }
}

struct OCRTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.backgroundColor = .white
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.selectedRange() != selectedRange {
            textView.setSelectedRange(selectedRange)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: OCRTextView

        init(_ parent: OCRTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }
    }
}
