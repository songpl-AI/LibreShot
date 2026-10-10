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
        let suite = "LibreShot.SaveDefaults.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        guard !SettingsService(defaults: defaults).autoSaveEnabled else {
            print("FAIL: new users must default to copy-only completion")
            exit(1)
        }
        for existing in [true, false] {
            defaults.set(existing, forKey: "autoSaveEnabled")
            precondition(SettingsService(defaults: defaults).autoSaveEnabled == existing)
        }
        defaults.removeObject(forKey: "autoSaveEnabled")
        defaults.set(7, forKey: "shortcutKey")
        precondition(SettingsService(defaults: defaults).autoSaveEnabled,
                     "Legacy users without a stored toggle must retain their former enabled default")
        precondition(defaults.object(forKey: "autoSaveEnabled") as? Bool == true)
        print("PASS: new users default to copy-only; stored and implicit legacy choices preserved")
        let settings = SettingsService.shared
        precondition(settings.saveSaveDirectory(directory))
        settings.autoSaveEnabled = true
        settings.doubleClickCompletesCapture = true
        let image = NSImage(size: NSSize(width: 320, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 240).fill()
        image.unlockFocus()
        var targetID: CGDirectDisplayID = 42
        var requestedID: CGDirectDisplayID?
        var requests = 0
        let delegate = AppDelegate(fullScreenImageProvider: { id in
            requestedID = id
            requests += 1
            return image
        }, fullScreenDisplayIDProvider: { targetID })
        func editor() -> ImageEditorWindowController? {
            NSApp.windows.filter(\.isVisible).compactMap { $0.windowController as? ImageEditorWindowController }.first
        }
        func files() -> [URL] { (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] }
        delegate.perform(NSSelectorFromString("captureFullScreen"))
        targetID = 77
        check(await waitFor({ requests == 1 }))
        guard requestedID == 42 else {
            print("FAIL: full-screen capture ignored display at trigger time; requested \(String(describing: requestedID)), expected 42")
            exit(1)
        }
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
        print("PASS: display at trigger time is passed explicitly, even when target changes before capture")
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
        delegate.perform(NSSelectorFromString("captureFullScreen"))
        check(await waitFor({ editor() != nil }))
        let manual = editor()!
        let beforeManualCopy = NSPasteboard.general.changeCount
        try await manual.onAction!(manual.renderedImage(), .save)
        precondition(files().count == count + 1, "Manual Save must write even with Auto Save off")
        precondition(NSPasteboard.general.changeCount == beforeManualCopy, "Manual Save must not replace the clipboard")
        precondition(manual.window!.isVisible, "Manual Save keeps the editor open")
        manual.close()
        print("PASS: explicit Save writes to configured directory with Auto Save off and keeps clipboard/editor")
        let displays: [(id: CGDirectDisplayID, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 1512, height: 982)),
            (2, CGRect(x: -2560, y: 0, width: 2560, height: 1440)),
            (3, CGRect(x: 0, y: 982, width: 1920, height: 1080)),
            (4, CGRect(x: 1512, y: -1080, width: 1920, height: 1080))
        ]
        for (point, expected) in [(CGPoint(x: 100, y: 100), CGDirectDisplayID(1)),
                                  (CGPoint(x: -1200, y: 600), 2),
                                  (CGPoint(x: 600, y: 1400), 3),
                                  (CGPoint(x: 2000, y: -500), 4),
                                  (CGPoint(x: 9999, y: 9999), 1)] {
            precondition(CaptureService.displayID(at: point, displays: displays, fallback: 1) == expected)
        }
        precondition(CaptureService.displayID(at: .zero, displays: [], fallback: nil) == nil)
        if let screen = NSScreen.screens.last {
            let placed = ImageEditorWindowController(image: image, screen: screen)
            precondition(abs(placed.window!.frame.midX - screen.visibleFrame.midX) < 1)
            precondition(abs(placed.window!.frame.midY - screen.visibleFrame.midY) < 1)
            placed.close()
        }
        print("PASS: left/above/below displays, fallback, and editor placement on target screen")
    }
}
