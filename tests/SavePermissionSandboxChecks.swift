import AppKit

@MainActor private final class SaveQADelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await SavePermissionSandboxChecks.run() }
    }
}

/// Manual sandbox integration check: the first denied save uses the real folder
/// panel. Run the same signed bundle twice to verify its persisted directory grant.
@main struct SavePermissionSandboxChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let delegate = SaveQADelegate()
        NSApp.delegate = delegate
        withExtendedLifetime(delegate) { NSApp.run() }
    }

    @MainActor static func run() async {
        let settings = SettingsService(defaults: .standard)
        settings.autoSaveEnabled = true
        let hadBookmark = settings.saveDirectory != nil
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let service = CaptureService(settings: settings, pasteboard: board)
        let image = NSImage(size: NSSize(width: 320, height: 200))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x:0,y:0,width:320,height:200).fill()
        ("LibreShot public save fixture" as NSString).draw(at: NSPoint(x:20,y:80),
            withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.black])
        image.unlockFocus()
        var result: [String: Any] = ["hadBookmarkAtLaunch":hadBookmark,
                                   "timestamp":ISO8601DateFormatter().string(from:Date()),
                                   "sandboxHome":NSHomeDirectory()]
        do {
            var files: [String] = []
            for _ in 0..<2 {
                let url = try await service.completeCapture(image)!
                guard let directory = settings.saveDirectory else { throw CocoaError(.fileReadNoPermission) }
                let accessing = directory.startAccessingSecurityScopedResource()
                defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
                guard let png = board.data(forType:.png), png == (try Data(contentsOf:url)),
                      board.data(forType:.tiff) != nil else { throw CocoaError(.fileReadCorruptFile) }
                files.append(url.path)
            }
            result["passed"] = true
            result["files"] = files
            result["bookmarkPersisted"] = settings.saveDirectoryBookmark != nil
        } catch {
            result["passed"] = false
            result["error"] = String(describing:error)
        }
        let reportDir = URL(fileURLWithPath:NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/LibreShotSaveQA",isDirectory:true)
        try? FileManager.default.createDirectory(at:reportDir,withIntermediateDirectories:true)
        let data = try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        try? data.write(to:reportDir.appendingPathComponent("result.json"))
        NSApp.terminate(nil)
    }
}
