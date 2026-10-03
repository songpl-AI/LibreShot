import AppKit

@main struct OCRPublicFixtureApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let frame = CGRect(x: 30, y: 80, width: 600, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "LibreShot Public OCR Fixture"
        window.backgroundColor = .white
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        for row in 0..<14 {
            let label = NSTextField(labelWithString: row.isMultiple(of: 2)
                ? "LibreShot public OCR fixture row \(row)"
                : "中文识别测试：原图翻译与内存验证 \(row)")
            label.font = .systemFont(ofSize: 24)
            label.textColor = .black
            label.frame = CGRect(x: 90, y: frame.height - 180 - CGFloat(row) * 42, width: 510, height: 36)
            view.addSubview(label)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime(window) { app.run() }
    }
}
