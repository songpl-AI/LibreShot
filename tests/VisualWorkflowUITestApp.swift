import AppKit
import SwiftUI

/// Synthetic native UI fixtures. No screen recording, global hotkeys or shared pasteboard.
@main
struct VisualWorkflowUITestApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let root = NSMenuItem()
        let commands = NSMenu()
        root.submenu = commands
        menu.addItem(root)
        app.mainMenu = menu
        commands.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let suite = "LibreShot.Visual.UI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if ProcessInfo.processInfo.environment["LIBRESHOT_QA_CUSTOM_TOOLBAR"] == "1" {
            let priority: [ToolbarItem] = [.pin, .ocr, .select, .pen, .rectangle, .arrow, .ellipse,
                                           .text, .number, .mosaic, .undo, .cancel, .complete, .style, .translate]
            defaults.set((priority + ToolbarItem.allCases.filter { !priority.contains($0) }).map(\.rawValue),
                         forKey: "toolbarItemOrder")
        }
        let settings = SettingsService(defaults: defaults)
        let board = NSPasteboard.withUniqueName()
        let service = CaptureService(settings: settings, pasteboard: board)
        let document = fixture(width: 720, height: 460)
        let frozen = NSImage(size: CGSize(width: 1040, height: 780))
        frozen.lockFocus()
        NSColor(white: 0.8, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 1040, height: 780).fill()
        document.draw(in: CGRect(x: 160, y: 200, width: 720, height: 460))
        frozen.unlockFocus()
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 160, y: 120, width: 720, height: 460)
        model.selectedTool = .rectangle
        let cg = frozen.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        model.updatePreviewImage(cg, scale: CGFloat(cg.width) / 1040)
        let window = OverlayWindow(contentRect: CGRect(x: 50, y: 80, width: 1040, height: 780),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "原选区翻译与工具栏验收"
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OverlayView(viewModel: model))
        window.bindEditingActions(to: model)
        window.onEscapeKey = { model.clearImageTranslation() }
        model.onCapture = { rect, annotations, action, image in
            guard let image else { return }
            let scale = model.previewScale
            guard let cropped = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                          width: rect.width * scale, height: rect.height * scale)) else { return }
            let source = NSImage(cgImage: cropped, size: rect.size)
            let output = service.compositeCropped(image: source, annotations: annotations, cropRect: rect, displayID: nil)
            let folder = URL(fileURLWithPath: "/tmp/LibreShot-Visual-QA")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? service.pngData(from: output)?.write(to: folder.appendingPathComponent("selection-\(action).png"))
            window.title = "原选区翻译与工具栏验收 · 已导出"
        }
        model.onCancel = { model.clearImageTranslation() }
        let editor = ImageEditorWindowController(image: fixture(width: 720, height: 2800), settings: settings)
        editor.window?.title = "长截图适配验收"
        editor.onAction = { image, _ in
            let folder = URL(fileURLWithPath: "/tmp/LibreShot-Visual-QA")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try service.pngData(from: image)!.write(to: folder.appendingPathComponent("long-image.png"))
        }
        let windows = FixtureWindows(selection: window, editor: editor.window!)
        for (title, key, tag) in [("选区翻译", "1", 0), ("长截图", "2", 1)] {
            let item = NSMenuItem(title: title, action: #selector(FixtureWindows.show(_:)), keyEquivalent: key)
            item.target = windows
            item.tag = tag
            commands.insertItem(item, at: 0)
        }
        editor.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
        withExtendedLifetime(editor) {}
        withExtendedLifetime(windows) {}
        board.releaseGlobally()
        defaults.removePersistentDomain(forName: suite)
    }

    static func fixture(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: image.size).fill()
        let ink = NSColor(red: 0.17, green: 0.23, blue: 0.31, alpha: 1)
        func text(_ value: String, top: CGFloat, size: CGFloat = 18, color: NSColor? = nil, bold: Bool = false) {
            (value as NSString).draw(in: CGRect(x: 38, y: height - top - 40, width: width - 76, height: 40),
                                    withAttributes: [.font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                                                     .foregroundColor: color ?? ink])
        }
        text("Create issue", top: 24, size: 30, bold: true)
        text("Create an issue, or a subtask in a project.", top: 94)
        text("The transition may be applied to a different workflow step.", top: 130)
        text("Fields and issue properties can be included in the request.", top: 166)
        text("Required permissions", top: 224, color: .systemBlue, bold: true)
        text("Browse projects and create issues in the selected project.", top: 264)
        text("Data security policy", top: 322, color: .systemBlue, bold: true)
        text("Not exempt from application access rules.", top: 362)
        if height > 500 {
            for row in 0..<45 {
                let top = CGFloat(460 + row * 50)
                if row % 2 == 0 {
                    NSColor(white: 0.96, alpha: 1).setFill()
                    CGRect(x: 0, y: height - top - 44, width: width, height: 50).fill()
                }
                text("Row \(row + 1)  ·  Capture layout and annotation alignment", top: top, size: 17)
            }
        }
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class FixtureWindows: NSObject {
    let selection: NSWindow
    let editor: NSWindow

    init(selection: NSWindow, editor: NSWindow) {
        self.selection = selection
        self.editor = editor
    }

    @objc func show(_ sender: NSMenuItem) {
        // Hide the screen-saver-level fixture before showing the normal editor window.
        let target = sender.tag == 0 ? selection : editor
        let other = sender.tag == 0 ? editor : selection
        other.orderOut(nil)
        target.makeKeyAndOrderFront(nil)
    }
}
