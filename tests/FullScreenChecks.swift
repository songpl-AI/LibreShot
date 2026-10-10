import AppKit

@main struct FullScreenChecks {
    @MainActor static func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    static func check(_ result: Bool) { precondition(result) }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot.FullScreen.\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // This standalone executable has its own defaults domain, separate from the installed app.
        precondition(Bundle.main.bundleIdentifier != "com.allensong.LibreShot")
        let settings = SettingsService.shared
        precondition(settings.saveSaveDirectory(directory))
        settings.autoSaveEnabled = true
        settings.doubleClickCompletesCapture = true
        let image = NSImage(size: NSSize(width: 320, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 240).fill()
        image.unlockFocus()
        let delegate = AppDelegate(fullScreenImageProvider: { image })
        func editor() -> ImageEditorWindowController? {
            NSApp.windows.filter(\.isVisible).compactMap { $0.windowController as? ImageEditorWindowController }.first
        }
        func files() -> [URL] { (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] }
        delegate.perform(NSSelectorFromString("captureFullScreen"))
        guard await waitFor({ editor() != nil }), let first = editor() else {
            print("FAIL: full-screen capture produced no visible annotation editor (saved files: \(files().count))")
            exit(1)
        }
        precondition(first.model.state == .editing && first.model.selectionRect.size == image.size)
        precondition(files().isEmpty, "Must not save before confirmation")
        first.model.selectTool(.rectangle)
        first.model.startDrawing(at: CGPoint(x: 20, y: 20))
        first.model.updateDrawing(to: CGPoint(x: 120, y: 100))
        first.model.endDrawing()
        precondition(first.model.annotations.count == 1)
        let annotated = first.renderedImage().tiffRepresentation
        precondition(annotated != image.tiffRepresentation, "Export must include the annotation")
        (first.window as? OverlayWindow)?.onConfirmKey?()
        check(await waitFor({ editor() == nil && files().count == 1 }))
        precondition(NSImage(contentsOf: files()[0]) != nil)
        precondition(NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil))
        let savedPNG = try Data(contentsOf: files()[0])
        precondition(savedPNG == NSPasteboard.general.data(forType: .png),
                     "Saved PNG and clipboard must contain the same final image")
        print("PASS: full-screen capture opens editor; Enter copies and saves annotated image")
        delegate.perform(NSSelectorFromString("captureFullScreen"))
        check(await waitFor({ editor() != nil }))
        let count = files().count
        let clipboard = NSPasteboard.general.changeCount
        (editor()?.window as? OverlayWindow)?.onEscapeKey?()
        check(await waitFor({ editor() == nil }))
        precondition(files().count == count && NSPasteboard.general.changeCount == clipboard)
        print("PASS: Escape cancels without saving or copying")
        settings.autoSaveEnabled = false
        delegate.perform(NSSelectorFromString("captureFullScreen"))
        check(await waitFor({ editor() != nil }))
        precondition(editor()!.model.confirmDoubleClick(at: CGPoint(x: 150, y: 150)))
        check(await waitFor({ editor() == nil }))
        precondition(files().count == count && NSPasteboard.general.changeCount > clipboard)
        print("PASS: double-click copies without saving when auto-save is disabled")
    }
}
