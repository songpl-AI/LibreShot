import AppKit
import SwiftUI
import ScreenCaptureKit
import Translation

@main
struct ToolbarRegressionChecks {
    @MainActor
    static func main() async throws {
        checkEscapeCancellation()
        try await checkOCRAndTranslation()
        let displayConfiguration = CaptureService.displayConfiguration(width: 3024, height: 1964)
        precondition(!displayConfiguration.showsCursor, "Captured pixels must exclude the system cursor in both frozen previews and exported screenshots")
        precondition(displayConfiguration.width == 3024 && displayConfiguration.height == 1964)
        precondition(!displayConfiguration.scalesToFit && !displayConfiguration.capturesAudio)
        print("PASS: screen capture excludes cursor while retaining physical resolution")

        precondition(CaptureServiceError.permissionDenied.localizedDescription.contains("屏幕录制权限"),
                     "Screen capture permission failures must explain how to authorize LibreShot")
        let systemFailure = NSError(domain: "LibreShot.Test.ScreenContent", code: 42,
                                    userInfo: [NSLocalizedDescriptionKey: "Screen content fixture failure"])
        for (hasAccess, grantsAccess) in [(false, false), (false, true), (true, false)] {
            var requests = 0
            var loads = 0
            do {
                _ = try await ScreenCaptureAccess.content(
                    preflight: { hasAccess },
                    request: { requests += 1; return grantsAccess },
                    load: { loads += 1; throw systemFailure }
                )
                preconditionFailure("The fixture must throw")
            } catch CaptureServiceError.permissionDenied {
                precondition(!hasAccess && !grantsAccess && loads == 0)
            } catch CaptureServiceError.screenContentUnavailable(let underlying) {
                precondition((hasAccess || grantsAccess) && loads == 1)
                precondition((underlying as NSError) === systemFailure)
                let message = CaptureServiceError.screenContentUnavailable(underlying: underlying).localizedDescription
                precondition(message.contains("42") && message.contains(systemFailure.domain))
                precondition(!message.contains("尚未获得屏幕录制权限"))
            }
            precondition(requests == (hasAccess ? 0 : 1))
        }
        let declined = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        let denialMessage = CaptureServiceError.screenContentUnavailable(underlying: declined).localizedDescription
        precondition(denialMessage.contains("屏幕录制权限") && denialMessage.contains("-3801"))
        print("PASS: Chinese permission guidance, newly granted access continues, system error identity preserved")

        let suite = "LibreShot.ToolbarChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        precondition(settings.toolbarConfiguration.visibleItems == ToolbarItem.allCases)
        checkSelectionResizing(settings: settings)

        if let output = ProcessInfo.processInfo.environment["LIBRESHOT_CHECK_SELECTION"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            let selection = OverlayViewModel(settings: settings)
            selection.startSelection(at: CGPoint(x: 100, y: 100))
            selection.updateSelection(to: CGPoint(x: 400, y: 300))
            selection.endSelection()
            precondition(selection.selectedTool == .rectangle)
            let initial = try render(OverlayView(viewModel: selection).background(Color.black),
                                     size: CGSize(width: 640, height: 480), path: output + "/initial.png")
            selection.selectTool(nil) // Choose Select/Move; Esc now cancels the entire capture.
            let selectionMode = try render(OverlayView(viewModel: selection).background(Color.black),
                                         size: CGSize(width: 640, height: 480), path: output + "/selection-mode.png")
            let scale = CGFloat(initial.pixelsWide) / 640
            // Sample inside each circular handle, away from the one-pixel selection border.
            for point in [CGPoint(x: 102, y: 102), CGPoint(x: 398, y: 102),
                          CGPoint(x: 102, y: 298), CGPoint(x: 398, y: 298)] {
                let x = Int(point.x * scale), y = Int(point.y * scale)
                let control = selectionMode.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let actual = initial.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(control.redComponent > 0.8, "Selection mode must render a white resize handle")
                precondition(actual.redComponent > 0.8, "Selection handles must appear immediately, before Esc")
            }
            print("PASS: actual overlay renders all four corner handles immediately after selection, before Esc")
        }

        // Required actions survive hiding everything, including malformed stored preferences.
        ToolbarItem.allCases.forEach { settings.setToolbarItem($0, visible: false) }
        precondition(settings.toolbarConfiguration.visibleItems == [.cancel, .complete])
        let reloaded = SettingsService(defaults: defaults)
        precondition(reloaded.toolbarConfiguration.visibleItems == [.cancel, .complete])
        defaults.set(ToolbarItem.allCases.map(\.rawValue) + ["future-tool"], forKey: "hiddenToolbarItems")
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.visibleItems == [.cancel, .complete])
        reloaded.restoreDefaultToolbar()
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.visibleItems == ToolbarItem.allCases)
        print("PASS: visibility, required actions, persistence, unknown IDs, restore defaults")

        // Old preferences need no migration; partial/corrupt orders still include each tool once.
        let repairedOrder = ToolbarConfiguration(itemOrder: ["save", "unknown", "save", "complete"])
        precondition(repairedOrder.orderedItems == [.save, .complete] + ToolbarItem.allCases.filter { $0 != .save && $0 != .complete })
        defaults.set(["save", "unknown", "save", "complete"], forKey: "toolbarItemOrder")
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.orderedItems == repairedOrder.orderedItems)
        defaults.set("invalid-array", forKey: "toolbarItemOrder")
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.orderedItems == ToolbarItem.allCases)
        settings.restoreDefaultToolbar()
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: 16), toOffset: 0)
        precondition(settings.toolbarConfiguration.orderedItems == [.save] + ToolbarItem.allCases.filter { $0 != .save })
        settings.setToolbarItem(.save, visible: false)
        precondition(!settings.toolbarConfiguration.visibleItems.contains(.save))
        settings.setToolbarItem(.save, visible: true)
        precondition(settings.toolbarConfiguration.visibleItems.first == .save)
        let movedReload = SettingsService(defaults: defaults)
        precondition(movedReload.toolbarConfiguration.orderedItems == settings.toolbarConfiguration.orderedItems)
        movedReload.moveToolbarItems(fromOffsets: IndexSet(integer: 0), toOffset: ToolbarItem.allCases.count)
        precondition(movedReload.toolbarConfiguration.orderedItems.last == .save)
        movedReload.moveToolbarItems(fromOffsets: IndexSet(integer: 17), toOffset: 16)
        precondition(movedReload.toolbarConfiguration.orderedItems == ToolbarItem.allCases)
        movedReload.moveToolbarItems(fromOffsets: IndexSet([11, 15]), toOffset: 0)
        ToolbarItem.allCases.forEach { movedReload.setToolbarItem($0, visible: false) }
        precondition(movedReload.toolbarConfiguration.visibleItems == [.cancel, .complete])
        movedReload.moveToolbarItems(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        precondition(movedReload.toolbarConfiguration.visibleItems == [.complete, .cancel])
        let beforeInvalidMove = movedReload.toolbarConfiguration.orderedItems
        for (source, destination) in [(IndexSet(integer: 99), 0), (IndexSet(integer: 0), -1), (IndexSet(integer: 0), 19), (IndexSet(), 0)] {
            movedReload.moveToolbarItems(fromOffsets: source, toOffset: destination)
            precondition(movedReload.toolbarConfiguration.orderedItems == beforeInvalidMove)
        }
        movedReload.restoreDefaultToolbar()
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.orderedItems == ToolbarItem.allCases)
        precondition(SettingsService(defaults: defaults).toolbarConfiguration.visibleItems == ToolbarItem.allCases)
        print("PASS: reorder up/down/multiple, persistence, hidden positions, required actions, malformed orders, reset")

        settings.restoreDefaultToolbar()
        let model = OverlayViewModel(settings: settings)
        settings.setToolbarItem(.rectangle, visible: false)
        settings.moveToolbarItems(fromOffsets: IndexSet(integer: 15), toOffset: 0)
        precondition(model.visibleToolbarItems.first == .select)
        model.startSelection(at: CGPoint(x: 10, y: 10))
        model.updateSelection(to: CGPoint(x: 200, y: 200))
        model.endSelection()
        precondition(model.selectedTool == .rectangle) // Active session remains unchanged.
        model.reset()
        precondition(model.visibleToolbarItems.first == .complete)
        model.startSelection(at: CGPoint(x: 10, y: 10))
        model.updateSelection(to: CGPoint(x: 200, y: 200))
        model.endSelection()
        precondition(model.selectedTool == nil)
        precondition(!model.visibleToolbarItems.contains(.rectangle))
        model.captureMode = .longScreenshot
        precondition(!model.visibleToolbarItems.contains(.longCapture))
        model.captureMode = .normal
        print("PASS: capture-session snapshot, hidden default tool, long-capture availability")

        // Finalizing must include text that has not yet been committed by clicking the canvas.
        for action in [CaptureAction.copy, .save, .saveAs, .pin, .ocr] {
            model.reset()
            model.state = .editing
            model.selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)
            model.selectTool(.text)
            model.startTextInput(at: CGPoint(x: 20, y: 20))
            model.editingTextContent = "最后一段文字\nFinal line"
            var received = false
            model.onCapture = { _, annotations, actualAction, _ in
                precondition(actualAction == action)
                precondition(annotations.count == 1 && annotations[0].text == "最后一段文字\nFinal line")
                received = true
            }
            switch action {
            case .copy: model.confirmCopy()
            case .save: model.confirmSave()
            case .saveAs: model.confirmSaveAs()
            case .pin: model.confirmPin()
            case .ocr: model.confirmOCR()
            }
            precondition(received && !model.isEditingText)
        }
        print("PASS: uncommitted text included in copy/save/save-as/pin/OCR")

        // Check full, minimal, and wrapped toolbars at all screen corners.
        for width: CGFloat in [320, 640, 1280, 2560] {
            let screen = CGSize(width: width, height: 720)
            for items in [ToolbarItem.allCases, [.cancel, .complete], [.text, .undo, .cancel, .complete], repairedOrder.orderedItems] {
                let layout = ToolbarLayout(items: items, availableWidth: width - 20)
                precondition(layout.rows.flatMap { $0 } == items)
                for x in [CGFloat(0), width / 2, width - 20] {
                    for y: CGFloat in [0, 350, 700] {
                        let center = layout.position(selection: CGRect(x: x, y: y, width: 20, height: 20), screenSize: screen)
                        let bounds = CGRect(x: center.x - layout.size.width / 2, y: center.y - layout.size.height / 2,
                                            width: layout.size.width, height: layout.size.height)
                        precondition(bounds.minX >= 10 && bounds.maxX <= width - 10)
                        precondition(bounds.minY >= 10 && bounds.maxY <= screen.height - 10)
                        for item in items {
                            let tip = layout.tooltipFrame(for: item, tooltipSize: CGSize(width: 280, height: 28),
                                                          toolbarCenter: center, screenSize: screen)
                            precondition(tip.minX >= 10 && tip.maxX <= screen.width - 10)
                            precondition(tip.minY >= 10 && tip.maxY <= screen.height - 10)
                            precondition(!tip.intersects(bounds), "Tooltip must not cover toolbar buttons")
                        }
                    }
                }
            }
        }
        print("PASS: screen-edge positioning, wrapping and tooltip bounds (144 configurations, including custom order)")

        if ProcessInfo.processInfo.environment["LIBRESHOT_CHECK_PERFORMANCE"] == "1" {
            let payload = try PropertyListSerialization.data(fromPropertyList: [
                "toolbarItemOrder": settings.toolbarConfiguration.orderedItems.map(\.rawValue)
            ], format: .binary, options: 0)
            var checksum = 0
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<100_000 {
                let layout = ToolbarLayout(items: model.visibleToolbarItems, availableWidth: 1200)
                checksum += layout.rows[0].count
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            precondition(checksum > 0)
            print(String(format: "MEASURE: order preference binary plist = %d bytes; visible tools + layout = %.3f microseconds/call (100,000 iterations, checksum %d)", payload.count, elapsed * 10, checksum))
        }

        _ = NSApplication.shared
        for item in ToolbarItem.allCases {
            precondition(NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) != nil,
                         "Missing icon: \(item.iconName)")
        }
        print("PASS: all toolbar symbols exist on this macOS version")

        // Use an isolated pasteboard and temporary directory; never touch the user's clipboard.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        settings.saveSaveDirectory(directory)
        precondition(settings.saveDirectory?.standardizedFileURL == directory.standardizedFileURL)
        let service = CaptureService(settings: settings, pasteboard: pasteboard)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.red, atX: 4, y: 4)
        let image = NSImage(size: CGSize(width: 16, height: 16))
        image.addRepresentation(bitmap)
        settings.autoSaveEnabled = true
        let saved = try await service.completeCapture(image)!
        precondition(NSImage(contentsOf: saved) != nil)
        precondition(pasteboard.data(forType: .png) != nil)
        settings.autoSaveEnabled = false
        let copiedOnly = try await service.completeCapture(image)
        precondition(copiedOnly == nil)
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(savedFiles.count == 1)
        precondition(pasteboard.data(forType: .png) != nil)
        // A regular file cannot contain screenshot files: force a real write failure.
        settings.saveSaveDirectory(saved)
        settings.autoSaveEnabled = true
        pasteboard.clearContents()
        var failed = false
        do { _ = try await service.completeCapture(image) }
        catch { failed = true }
        precondition(failed && pasteboard.data(forType: .png) != nil)
        print("PASS: automatic save on/off, real PNG output, failed save retains clipboard image")

        if let output = ProcessInfo.processInfo.environment["LIBRESHOT_QA_OUTPUT"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            settings.restoreDefaultToolbar()
            try render(ToolbarSettingsView(settings: settings).frame(width: 560, height: 390),
                       size: CGSize(width: 560, height: 390), path: output + "/toolbar-settings.png")
            settings.setToolbarItem(.pen, visible: false)
            settings.setToolbarItem(.blur, visible: false)
            settings.setToolbarItem(.save, visible: false)
            settings.setToolbarItem(.saveAs, visible: false)
            settings.moveToolbarItems(fromOffsets: IndexSet(integer: 15), toOffset: 0)
            model.reset()
            let layout = ToolbarLayout(items: model.visibleToolbarItems, availableWidth: 900)
            try render(EditorToolbarView(viewModel: model, layout: layout).padding(16),
                       size: CGSize(width: layout.size.width + 32, height: layout.size.height + 32), path: output + "/toolbar-custom.png")
            let wrapped = ToolbarLayout(items: ToolbarItem.allCases, availableWidth: 300)
            try render(EditorToolbarView(viewModel: model, layout: wrapped).padding(16),
                       size: CGSize(width: wrapped.size.width + 32, height: wrapped.size.height + 32), path: output + "/toolbar-wrapped.png")
            print("PASS: rendered native SwiftUI settings and toolbar previews")
        }
    }

    @MainActor
    private static func checkOCRAndTranslation() async throws {
        let image = NSImage(size: NSSize(width: 1000, height: 220))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 220).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black]
        ("Hello world 12345" as NSString).draw(at: CGPoint(x: 30, y: 140), withAttributes: attributes)
        ("截图测试 颜色文字" as NSString).draw(at: CGPoint(x: 30, y: 60), withAttributes: attributes)
        image.unlockFocus()
        let recognized = try await OCRService.shared.recognizeText(from: image)
        precondition(recognized.contains("Hello world") && recognized.contains("12345") && recognized.contains("截图测试"), recognized)
        print("PASS: system Vision OCR recognizes a generated English/Chinese image")

        if #available(macOS 26.0, *) {
            let source = Locale.Language(identifier: "en")
            let target = Locale.Language(identifier: "zh-Hans")
            let text = "Hello world. This is a screenshot test."
            let unchanged = try await TranslationService.translate(text, target: source)
            precondition(unchanged == text)
            let availability = await LanguageAvailability().status(from: source, to: target)
            if availability == .installed {
                let translated = try await TranslationService.translate(text, target: target)
                precondition(!translated.isEmpty && translated != text && translated.range(of: "[\\p{Han}]", options: .regularExpression) != nil)
                print("PASS: installed system language model translates English into Chinese")
            } else {
                print("NOT RUN: English-to-Chinese translation model is not installed; same-language path passed")
            }
        } else {
            print("NOT RUN: system translation requires macOS 26 or later")
        }
    }

    @MainActor
    private static func checkEscapeCancellation() {
        _ = NSApplication.shared
        let window = OverlayWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var cancellations = 0
        window.onEscapeKey = { cancellations += 1 }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        window.sendEvent(escape)
        precondition(cancellations == 1, "One Escape must cancel the capture")

        let editor = NSTextView(frame: window.contentView!.bounds)
        editor.string = "Unfinished text"
        window.contentView = editor
        precondition(window.makeFirstResponder(editor))
        window.sendEvent(escape)
        precondition(cancellations == 2, "The text editor must not consume Escape before capture cancellation")
        precondition(editor.string == "Unfinished text")
        print("PASS: a single Escape cancels through the native window, including with the text editor focused")
    }

    @MainActor
    private static func checkSelectionResizing(settings: SettingsService) {
        let model = OverlayViewModel(settings: settings)
        let original = CGRect(x: 100, y: 100, width: 300, height: 200)
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        let cases: [(SelectionHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 80, y: 80), CGRect(x: 80, y: 80, width: 320, height: 220)),
            (.top, CGPoint(x: 250, y: 80), CGRect(x: 100, y: 80, width: 300, height: 220)),
            (.topRight, CGPoint(x: 420, y: 80), CGRect(x: 100, y: 80, width: 320, height: 220)),
            (.right, CGPoint(x: 420, y: 200), CGRect(x: 100, y: 100, width: 320, height: 200)),
            (.bottomRight, CGPoint(x: 420, y: 320), CGRect(x: 100, y: 100, width: 320, height: 220)),
            (.bottom, CGPoint(x: 250, y: 320), CGRect(x: 100, y: 100, width: 300, height: 220)),
            (.bottomLeft, CGPoint(x: 80, y: 320), CGRect(x: 80, y: 100, width: 320, height: 220)),
            (.left, CGPoint(x: 80, y: 200), CGRect(x: 80, y: 100, width: 320, height: 200))
        ]
        for tool in [nil] + AnnotationType.allCases.map({ Optional($0) }) {
            for (handle, end, expected) in cases {
                model.reset()
                model.startSelection(at: original.origin)
                model.updateSelection(to: CGPoint(x: original.maxX, y: original.maxY))
                model.endSelection()
                model.selectTool(tool)
                precondition(model.canResizeSelection)
                let start = handle.position(in: original)
                // The first event may already have a translation; no zero-distance event is required.
                let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                precondition(model.handleSelectionResizeDrag(from: start, to: middle, within: bounds))
                precondition(model.activeSelectionHandle == handle)
                precondition(model.handleSelectionResizeDrag(from: start, to: end, within: bounds))
                precondition(model.selectionRect == expected)
                precondition(model.selectedTool == tool && model.annotations.isEmpty && model.currentAnnotation == nil)
                model.endResizeSelection()
                precondition(!model.isManipulatingSelection)
            }
        }
        model.selectionRect = original
        model.selectedTool = .rectangle
        let center = CGPoint(x: 250, y: 200)
        precondition(!model.handleSelectionResizeDrag(from: center, to: original.origin, within: bounds))
        model.startDrawing(at: center)
        model.updateDrawing(to: original.origin)
        precondition(!model.handleSelectionResizeDrag(from: center, to: original.origin, within: bounds))
        model.endDrawing()
        precondition(model.selectionRect == original && model.annotations.count == 1)

        model.selectedTool = .text
        model.startTextInput(at: center)
        model.editingTextContent = "调整前的文字"
        precondition(model.handleSelectionResizeDrag(from: original.origin, to: CGPoint(x: 900, y: 900), within: bounds))
        precondition(model.selectionRect == CGRect(x: 380, y: 280, width: 20, height: 20))
        precondition(model.annotations.last?.text == "调整前的文字" && !model.isEditingText && model.selectedTool == .text)
        model.endResizeSelection()
        model.selectionRect = original
        precondition(model.handleSelectionResizeDrag(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 900, y: 900), within: bounds))
        precondition(model.selectionRect == CGRect(x: 100, y: 100, width: 540, height: 380))
        model.endResizeSelection()
        for state in [OverlayState.idle, .selecting, .longCapturing] {
            model.state = state
            precondition(!model.canResizeSelection)
            precondition(!model.handleSelectionResizeDrag(from: original.origin, to: .zero, within: bounds))
        }
        model.state = .longCaptureReady
        model.selectionRect = original
        precondition(model.handleSelectionResizeDrag(from: original.origin, to: .zero, within: bounds))
        model.endResizeSelection()
        model.selectionRect = .zero
        precondition(!model.canResizeSelection)
        print("PASS: eight resize handles across all tools (72 cases), drag priority, annotation preservation, bounds, minimum size, capture states")
    }

    @MainActor
    @discardableResult
    private static func render<V: View>(_ view: V, size: CGSize, path: String) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light).background(Color.white))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
        return bitmap
    }
}
