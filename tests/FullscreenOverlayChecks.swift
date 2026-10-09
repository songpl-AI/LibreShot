import AppKit

@MainActor final class FullscreenRegressionHost: NSObject, NSWindowDelegate {
    var window: NSWindow!
    var child: Process!
    let trigger = "/tmp/libreshot-fullscreen-trigger-" + UUID().uuidString
    func start() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 900, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.title = "LibreShot public fullscreen regression fixture"
        window.backgroundColor = .white
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = [String(ProcessInfo.processInfo.processIdentifier), trigger]
        child.terminationHandler = { process in
            DispatchQueue.main.async {
                print("HOST stillFullScreen=\(self.window.styleMask.contains(.fullScreen)) onActiveSpace=\(self.window.isOnActiveSpace)")
                try? FileManager.default.removeItem(atPath: self.trigger)
                try? FileManager.default.removeItem(atPath: self.trigger + ".ready")
                exit(process.terminationStatus)
            }
        }
        try! child.run()
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if FileManager.default.fileExists(atPath: self.trigger + ".ready") {
                timer.invalidate()
                NSApp.activate(ignoringOtherApps: true)
                self.window.makeKeyAndOrderFront(nil)
                self.window.toggleFullScreen(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.child?.terminate()
            try? FileManager.default.removeItem(atPath: self.trigger)
            try? FileManager.default.removeItem(atPath: self.trigger + ".ready")
            fputs("FAIL: fullscreen fixture timed out\n", stderr)
            exit(3)
        }
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        FileManager.default.createFile(atPath: trigger, contents: Data())
    }
}
@main struct FullscreenOverlayChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.count == 1 {
            let host = FullscreenRegressionHost()
            host.start()
            withExtendedLifetime(host) { app.run() }
            return
        }
        app.setActivationPolicy(.accessory)
        let hostPID = Int(CommandLine.arguments[1])!
        func hostOnScreen() -> Bool {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            return windows.contains { ($0[kCGWindowOwnerPID as String] as? Int) == hostPID && ($0[kCGWindowLayer as String] as? Int) == 0 }
        }
        let prefs = NSWindow(contentRect: CGRect(x: 50, y: 50, width: 500, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        prefs.title = "Public fixture preferences"
        prefs.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let trigger = CommandLine.arguments[2]
        FileManager.default.createFile(atPath: trigger + ".ready", contents: Data())
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard FileManager.default.fileExists(atPath: trigger) else { return }
            timer.invalidate()
            runOverlay(hostOnScreen: hostOnScreen, prefs: prefs)
        }
        app.run()
    }
    @MainActor static func runOverlay(hostOnScreen: @escaping () -> Bool, prefs: NSWindow) {
        let before = hostOnScreen()
        var spaceChanges = 0
        let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in spaceChanges += 1 }
        let controller = OverlayWindowController()
        controller.previewImageLoader = { _ in
            let image = NSImage(size: NSScreen.main!.frame.size)
            image.lockFocus(); NSColor.white.setFill(); NSRect(origin: .zero, size: image.size).fill(); image.unlockFocus()
            return image
        }
        controller.show(onCapture: { _,_,_,_ in }, onCancel: {})
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let window = controller.window!
            let after = hostOnScreen()
            let passed = before && after && window.isVisible && window.isKeyWindow && spaceChanges == 0
            print("\(passed ? "PASS" : "FAIL"): visible=\(window.isVisible) activeSpace=\(window.isOnActiveSpace) key=\(window.isKeyWindow) spaceChanges=\(spaceChanges) fullscreenHostBefore=\(before) fullscreenHostAfter=\(after)")
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            controller.close()
            exit(passed ? 0 : 1)
        }
    }
}
