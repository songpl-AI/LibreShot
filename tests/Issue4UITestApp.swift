import AppKit

/// Interactive fixture; exports only into /tmp/LibreShot-Issue4-UI and never touches the user's clipboard.
@main
struct Issue4UITestApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let image = NSImage(size: NSSize(width: 700, height: 2400))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 700, height: 2400).fill()
        for i in 0..<60 {
            let y = 2400 - CGFloat(i + 1) * 40
            if i % 2 == 0 {
                NSColor(white: 0.94, alpha: 1).setFill()
                NSRect(x: 0, y: y - 5, width: 700, height: 40).fill()
            }
            ("第 \(i + 1) 行 — 长截图标注与缩放验收" as NSString).draw(at: NSPoint(x: 24, y: y),
                withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let defaults = UserDefaults(suiteName: "LibreShot.Issue4.UI")!
        defaults.removePersistentDomain(forName: "LibreShot.Issue4.UI")
        let settings = SettingsService(defaults: defaults)
        let editor = ImageEditorWindowController(image: image, settings: settings)
        editor.onAction = { image, action in
            let directory = URL(fileURLWithPath: "/tmp/LibreShot-Issue4-UI")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = CaptureService(settings: settings).pngData(from: image)!
            try data.write(to: directory.appendingPathComponent("\(action).png"))
            editor.window?.title = "已验证：\(action)"
        }
        editor.onClose = { app.stop(nil) }
        editor.showWindow(nil)
        editor.window?.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
