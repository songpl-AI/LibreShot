import AppKit
import SwiftUI

/// Native QA uses a generated image, isolated preferences and a private clipboard.
@main
struct RoadmapUITestApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        app.mainMenu = menu
        let suite = "LibreShot.Roadmap.UI.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let service = CaptureService(settings: settings, pasteboard: board)
        let window = NSWindow(contentRect: CGRect(x: 30, y: 100, width: 560, height: 450),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "快捷操作验收"
        window.isReleasedWhenClosed = false
        let settingsMenuItem = NSMenuItem(title: "快捷键…", action: #selector(NSWindow.makeKeyAndOrderFront(_:)), keyEquivalent: ",")
        settingsMenuItem.target = window
        appMenu.insertItem(settingsMenuItem, at: 0)
        window.contentView = NSHostingView(rootView: ShortcutSettingsView(settings: settings))
        window.orderFront(nil)
        guard #available(macOS 26.0, *),
              let image = NSImage(contentsOfFile: "/tmp/libreshot-roadmap-qa/translation-original.png") else { return }
        let translator = ImageTranslationWindowController(image: image)
        var editor: ImageEditorWindowController?
        translator.onAction = { image, action in
            if action == .copy { service.copyToClipboard(image) }
            else {
                try service.pngData(from: image)!.write(to: URL(fileURLWithPath: "/tmp/libreshot-roadmap-qa/ui-export.png"))
            }
        }
        translator.onEdit = { image in
            editor = ImageEditorWindowController(image: image, settings: settings)
            editor?.onAction = { image, _ in
                try service.pngData(from: image)!.write(to: URL(fileURLWithPath: "/tmp/libreshot-roadmap-qa/ui-annotated.png"))
            }
            editor?.showWindow(nil)
        }
        translator.showWindow(nil)
        translator.window?.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
        withExtendedLifetime(translator) {}
        withExtendedLifetime(editor) {}
    }
}
