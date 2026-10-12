import AppKit
import Carbon

@main struct PinnedImageChecks {
    static func closeEnough(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let external = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let visible = primary.insetBy(dx: 0, dy: 30)
        for rect in [CGRect(x: 35, y: 800, width: 100, height: 80),
                     CGRect(x: -1700, y: 500, width: 300, height: 240),
                     CGRect(x: 10, y: 970, width: 10, height: 10),
                     primary] {
            let result = PinnedImageWindowController.initialWindowFrame(for: rect.size, displayMode: .pinned,
                sourceRect: rect, visibleFrame: visible, screenFrames: [primary, external])
            precondition(result == rect, "area pin must keep source position and size, including screen edges and negative coordinates")
        }
        let disconnected = PinnedImageWindowController.initialWindowFrame(for: CGSize(width: 100, height: 80),
            displayMode: .pinned, sourceRect: CGRect(x: -5000, y: 500, width: 100, height: 80),
            visibleFrame: visible, screenFrames: [primary])
        precondition(disconnected.size == CGSize(width: 100, height: 80) && visible.contains(disconnected))
        let longFrame = PinnedImageWindowController.initialWindowFrame(for: CGSize(width: 100, height: 80),
            displayMode: .longCapturePreview, sourceRect: CGRect(x: 35, y: 800, width: 100, height: 80),
            visibleFrame: visible, screenFrames: [primary])
        precondition(longFrame.width >= 360 && longFrame.height >= 280
                     && closeEnough(longFrame.midX, visible.midX) && closeEnough(longFrame.midY, visible.midY))
        print("PASS: original area geometry, small/full-screen pins, negative monitor coordinates, disconnected fallback and long-preview isolation")

        let fixture = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        fixture.setFillColor(NSColor.systemRed.cgColor)
        fixture.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        fixture.setFillColor(NSColor.systemBlue.cgColor)
        fixture.fill(CGRect(x: 100, y: 0, width: 100, height: 160))
        let image = NSImage(cgImage: fixture.makeImage()!, size: CGSize(width: 100, height: 80))
        let originalPixels = image.tiffRepresentation!
        let liveScreen = NSScreen.main!.frame
        let original = CGRect(x: liveScreen.minX + 80, y: liveScreen.minY + 160, width: 100, height: 80)
        let controller = PinnedImageWindowController(image: image, sourceRect: original)
        let window = controller.window!
        precondition(window.frame == original, "hosting view must not enlarge a small source area")
        controller.showWindow(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        precondition(window.frame == original, "first show must not recenter or cascade an area pin")
        let host = window.contentView as! PinnedImageHostingView
        let backingScale = NSScreen.main!.backingScaleFactor
        // Raster pixel density must not change the logical initial frame.
        let raster = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let retina = PinnedImageWindowController(image: NSImage(cgImage: raster.makeImage()!, size: original.size), sourceRect: original)
        precondition(retina.window!.frame == original)
        retina.close()
        print("PASS: actual small-window frame and Retina logical sizing (host backing scale \(backingScale))")

        let anchor = CGPoint(x: 30, y: 24), screenAnchor = CGPoint(x: original.minX + 30, y: original.minY + 24)
        controller.zoom(by: 1.5, at: anchor)
        let enlarged = window.frame
        precondition(closeEnough(enlarged.width, 150) && closeEnough(enlarged.height, 120))
        precondition(closeEnough(enlarged.minX + 45, screenAnchor.x) && closeEnough(enlarged.minY + 36, screenAnchor.y))
        // Simulate edge resizing before the next wheel operation.
        window.setFrame(CGRect(origin: original.origin, size: CGSize(width: 200, height: 160)), display: false)
        controller.zoom(by: 1.1, at: CGPoint(x: 100, y: 80))
        precondition(closeEnough(window.frame.width, 220) && closeEnough(window.frame.height, 176))
        controller.restoreOriginalSize()
        precondition(window.frame.size == image.size)
        controller.zoom(by: 1000, at: .zero)
        precondition(closeEnough(window.frame.width, 800) && closeEnough(window.frame.height, 640))
        controller.zoom(by: 0.000001, at: .zero)
        precondition(closeEnough(window.frame.width, 10) && closeEnough(window.frame.height, 8))
        controller.restoreOriginalSize()
        precondition(image.size == original.size)
        precondition(image.tiffRepresentation == originalPixels, "display scaling must never resample the saved/copied source")
        print("PASS: cursor anchor, edge-resize continuity, original-size reset, zoom limits and source size retention")

        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let left = bitmap.colorAt(x: bitmap.pixelsWide / 4, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        let right = bitmap.colorAt(x: bitmap.pixelsWide * 3 / 4, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        precondition(left.redComponent > left.blueComponent && right.blueComponent > right.redComponent,
                     "the actual hosting view must display both sides of the image without empty margins or clipping")
        print("PASS: actual small-pin view displays the original image content after zoom/reset")

        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        let event = NSEvent(cgEvent: wheel)!
        let before = window.frame
        host.scrollWheel(with: event)
        precondition(window.frame.width > before.width, "the native hosting view must route wheel input to window zoom")
        let preciseWheel = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -5, wheel2: 0, wheel3: 0)!
        let precise = NSEvent(cgEvent: preciseWheel)!
        let afterWheel = window.frame
        host.scrollWheel(with: precise)
        precondition(window.frame.width < afterWheel.width)
        wheel.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        let momentum = NSEvent(cgEvent: wheel)!
        precondition(!momentum.momentumPhase.isEmpty)
        let beforeMomentum = window.frame
        host.scrollWheel(with: momentum)
        precondition(window.frame == beforeMomentum, "inertia must not continue resizing")
        let preview = PinnedImageWindowController(image: image, displayMode: .longCapturePreview)
        let beforePreview = preview.window!.frame
        precondition(!preview.handleScroll(event))
        preview.zoom(by: 2, at: .zero)
        precondition(preview.window!.frame == beforePreview)
        preview.close(); controller.close()
        print("PASS: native wheel/precise-scroll dispatch, momentum suppression and long-preview input isolation")

        // An extreme long-image fallback can start below 10%; the first scroll must
        // grow gently from the fitted size, not jump straight to 10% of the source.
        let tall = PinnedImageWindowController(image: NSImage(size: CGSize(width: 1000, height: 100000)))
        let fitted = tall.window!.frame
        tall.zoom(by: 1.1, at: .zero)
        precondition(abs(tall.window!.frame.width - fitted.width * 1.1) <= 1,
                     "a fitted long image should grow gently, within native frame rounding")
        tall.close()

        checkPinShortcuts()
        checkUnifiedEditingAndWheels()
    }

    @MainActor static func checkUnifiedEditingAndWheels() {
        let suite = "LibreShot.PinUnified.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        precondition(settings.toolbarAlignment == .center)
        settings.toolbarAlignment = .right
        precondition(SettingsService(defaults: defaults).toolbarAlignment == .right)
        settings.restoreDefaultToolbar()
        precondition(settings.toolbarAlignment == .center)
        settings.toolbarAlignment = .right
        let layout = ToolbarLayout(items: [.select, .pen, .text], availableWidth: 1000)
        let selection = CGRect(x: 300, y: 300, width: 300, height: 200), screen = CGSize(width: 1200, height: 900)
        for alignment in ToolbarAlignment.allCases {
            let p = layout.position(selection: selection, screenSize: screen, accessorySize: CGSize(width: 300, height: 40), alignment: alignment)
            let expected: CGFloat = alignment == .left ? selection.minX + layout.size.width / 2
                : alignment == .right ? selection.maxX - layout.size.width / 2 : selection.midX
            precondition(closeEnough(p.x, expected), "align the main toolbar, not its wider properties")
            precondition(layout.frame(selection: selection, screenSize: screen, accessorySize: CGSize(width: 300, height: 40), alignment: alignment).contains(p))
        }
        print("PASS: alignment defaults/persistence and main-toolbar geometry with wider accessory")
        let alignmentPin = PinnedImageWindowController(image: NSImage(size: CGSize(width: 160, height: 120)), settings: settings)
        alignmentPin.window!.setFrame(CGRect(x: 300, y: 300, width: 300, height: 200), display: false)
        alignmentPin.beginEditing()
        let alignmentModel = alignmentPin.presentation.editor!
        alignmentModel.selectTool(.rectangle)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let panel = alignmentPin.window!.childWindows!.first!
        let tools = alignmentModel.visibleToolbarItems.filter { $0.annotationType != nil || $0 == .select || $0 == .undo }
        let available = min(720, alignmentPin.window!.screen!.visibleFrame.width - 20)
        let mainWidth = ToolbarLayout(items: tools, availableWidth: available - 16 - PinnedEditorTools.accessoryWidth).size.width
        // 18-point grip + 3-point gap precede the main toolbar; the trailing
        // collapse button is not part of the right-aligned annotation tools.
        let mainRight = panel.frame.minX + (panel.frame.width - mainWidth - 54) / 2 + 21 + mainWidth
        print("Pin alignment: image=\(alignmentPin.window!.frame), panel=\(panel.frame), tools=\(mainWidth), right=\(mainRight)")
        precondition(closeEnough(mainRight, alignmentPin.window!.frame.maxX),
                     "right alignment must align the main toolbar, excluding grip and collapse controls")
        alignmentPin.close()

        func wheel(_ delta: Int32, flags: CGEventFlags = [], precise: Bool = false) -> NSEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
            event.flags = flags
            return NSEvent(cgEvent: event)!
        }
        let bitmap = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(NSColor.white.cgColor); bitmap.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        bitmap.setFillColor(NSColor.black.cgColor)
        for x in stride(from: 0, to: 320, by: 8) { bitmap.fill(CGRect(x: x, y: 0, width: 4, height: 240)) }
        let base = NSImage(cgImage: bitmap.makeImage()!, size: CGSize(width: 160, height: 120))
        var shape = Annotation(type: .rectangle, color: .red)
        shape.startPoint = CGPoint(x: 50, y: 70); shape.endPoint = CGPoint(x: 110, y: 110)
        var effect = Annotation(type: .blur, color: .red)
        effect.points = [CGPoint(x: 60, y: 90), CGPoint(x: 130, y: 100)]
        effect.startPoint = effect.points[0]; effect.endPoint = effect.points[1]; effect.lineWidth = 12
        var number = Annotation(type: .number, color: .blue)
        number.startPoint = CGPoint(x: 150, y: 130); number.endPoint = number.startPoint; number.text = "7"
        let doc = PinnedImageDocument(baseImage: base, annotations: [shape, effect, number], origin: CGPoint(x: 30, y: 50), roundedCorners: false)
        precondition(doc.annotations[0].startPoint == CGPoint(x: 20, y: 20) && doc.annotations[1].points[0] == CGPoint(x: 30, y: 40))
        let pin = PinnedImageWindowController(image: doc.rendered(), document: doc, settings: settings)
        let originalPixels = pin.presentation.image.tiffRepresentation!
        pin.presentation.setOpacity(0.5)
        let frame = pin.window!.frame
        precondition(pin.handleScroll(wheel(1, flags: .maskControl)))
        precondition(abs(pin.presentation.opacity - 0.55) < 0.001 && pin.window!.frame == frame)
        _ = pin.handleScroll(wheel(1, flags: [.maskControl, .maskCommand]))
        precondition(pin.window!.frame == frame && abs(pin.presentation.opacity - 0.55) < 0.001)
        _ = pin.handleScroll(wheel(-100, flags: .maskControl)); precondition(pin.presentation.opacity == 0.1)
        _ = pin.handleScroll(wheel(100, flags: .maskControl)); precondition(pin.presentation.opacity == 1)
        pin.presentation.setOpacity(0.5)
        _ = pin.handleScroll(wheel(3, flags: .maskControl, precise: true))
        precondition(pin.presentation.opacity == 0.5)
        _ = pin.handleScroll(wheel(5, flags: .maskControl, precise: true))
        precondition(abs(pin.presentation.opacity - 0.55) < 0.001)
        _ = pin.handleScroll(wheel(1, flags: .maskCommand))
        precondition(pin.window!.frame.width > frame.width && abs(pin.presentation.opacity - 0.55) < 0.001)
        precondition(pin.presentation.image.tiffRepresentation == originalPixels)
        print("PASS: Control-wheel opacity, Cmd-wheel zoom, ambiguous modifiers, limits and precision accumulation without source changes")

        let beforeEdit = pin.window!.frame, beforeOpacity = pin.presentation.opacity
        pin.beginEditing()
        let model = pin.presentation.editor!
        model.selectedAnnotationID = shape.id
        precondition(model.annotations == doc.annotations && model.nextNumber == 8)
        precondition(model.toolbarAlignment == .right && !model.allowsCaptureCompletion)
        precondition(model.beginConfirmationClick(at: CGPoint(x: 140, y: 100)),
                     "blank double-click must remain available while editing a pin")
        model.cancelConfirmationClick()
        let blank = CGPoint(x: 140, y: 100)
        precondition(model.canMoveBlankCanvas(at: blank))
        precondition(!model.canMoveBlankCanvas(at: doc.annotations[0].startPoint),
                     "annotation handles must retain their own editing gestures")
        model.selectTool(.pen)
        precondition(!model.canMoveBlankCanvas(at: blank), "drawing must not move the pin")
        model.selectTool(nil)
        model.selectedAnnotationID = shape.id
        let dragFrame = pin.window!.frame, localAnnotations = model.annotations
        let dragScale = dragFrame.width / base.size.width
        pin.moveEditingPin(by: CGSize(width: 25, height: 15), ended: false)
        pin.moveEditingPin(by: CGSize(width: 40, height: 20), ended: true)
        precondition(closeEnough(pin.window!.frame.minX, dragFrame.minX + 40 * dragScale)
            && closeEnough(pin.window!.frame.minY, dragFrame.minY - 20 * dragScale))
        precondition(model.annotations == localAnnotations && pin.presentation.editor === model)
        pin.moveEditingPin(by: CGSize(width: -40, height: -20), ended: true)
        precondition(pin.window!.frame == dragFrame, "successive moves must use their own starting frame")
        pin.moveEditingPinFromPointer(translation: .zero, imageCoordinates: true, ended: false,
                                     pointer: CGPoint(x: 500, y: 500))
        pin.moveEditingPinFromPointer(translation: .zero, imageCoordinates: true, ended: true,
                                     pointer: CGPoint(x: 560, y: 460))
        precondition(pin.window!.frame.origin == CGPoint(x: dragFrame.minX + 60, y: dragFrame.minY - 40),
                     "moving a window must not cancel out the drag in its changing local coordinate space")
        pin.moveEditingPinFromPointer(translation: .zero, imageCoordinates: false, ended: false,
                                     pointer: CGPoint(x: 560, y: 460))
        pin.moveEditingPinFromPointer(translation: CGSize(width: -60, height: -40), imageCoordinates: false, ended: true,
                                     pointer: CGPoint(x: 500, y: 500))
        precondition(pin.window!.frame == dragFrame)
        var savedImages: [NSImage] = []
        let saveDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot.PinSave.\(UUID())")
        try! FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: saveDirectory) }
        precondition(settings.saveSaveDirectory(saveDirectory))
        let saveService = CaptureService(settings: settings)
        pin.savePinnedImage = { image in
            savedImages.append(image)
            return try await saveService.saveImageDirectly(image)
        }
        precondition(model.beginConfirmationClick(at: blank) && model.confirmDoubleClick(at: blank))
        precondition(!model.confirmDoubleClick(at: blank), "a double-click must save only once")
        for _ in 0..<100 where pin.isSavingPin {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        print("Pin save: requests=\(savedImages.count), busy=\(pin.isSavingPin), saved=\(pin.lastSavedURL?.path ?? "nil"), expected=\(saveDirectory.path)")
        precondition(savedImages.count == 1 && pin.lastSavedURL?.deletingLastPathComponent().resolvingSymlinksInPath().path == saveDirectory.resolvingSymlinksInPath().path && !pin.isSavingPin)
        let savedPNG = try! Data(contentsOf: pin.lastSavedURL!)
        precondition(NSBitmapImageRep(data: savedPNG) != nil
            && savedPNG == saveService.pngData(from: pin.pinDocument.rendered()),
                     "blank double-click must write the current composed image to the configured directory")
        precondition(pin.presentation.editor === model && model.annotations == localAnnotations,
                     "saving must preserve live editing, annotations and undo history")
        precondition(!pin.window!.isMovableByWindowBackground && pin.window!.childWindows?.count == 1)
        let toolsPanel = pin.window!.childWindows!.first!
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let toolsHost = toolsPanel.contentView!
        let click = NSEvent.mouseEvent(with: .leftMouseDown,
            location: CGPoint(x: 29, y: toolsPanel.frame.height - 29), modifierFlags: [],
            timestamp: 0, windowNumber: toolsPanel.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        let target = toolsHost.hitTest(toolsHost.convert(click.locationInWindow, from: nil))!
        print("First-click target: \(type(of: target)), accepts=\(target.acceptsFirstMouse(for: click))")
        precondition(target.acceptsFirstMouse(for: click),
                     "a tool button must accept the first click while the image window owns focus")
        let imageHost = pin.window!.contentView as! PinnedImageHostingView
        precondition(imageHost.acceptsFirstMouse(for: click),
                     "the first drawing click must also work after selecting a tool in the other window")
        let textInput = NSTextView(frame: CGRect(x: 5, y: 5, width: 40, height: 20))
        imageHost.addSubview(textInput)
        precondition(!imageHost.isImagePoint(CGPoint(x: 10, y: 10)), "text input must not trigger image wheel gestures")
        textInput.removeFromSuperview()
        if let output = ProcessInfo.processInfo.environment["LIBRESHOT_PIN_QA_OUTPUT"] {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let directory = URL(fileURLWithPath: output)
            try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, view) in [("in-place-image", pin.window!.contentView!),
                                 ("edit-toolbar", pin.window!.childWindows!.first!.contentView!)] {
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            }
        }
        let property = PropertyWheelView()
        model.selectedAnnotationID = shape.id
        property.value = model.currentToolStyle.lineWidth; property.range = 1...30
        property.begin = { model.beginToolPropertyAdjustment() }; property.end = { model.endToolPropertyAdjustment() }
        property.change = { model.setLineWidth($0) }
        let originalWidth = model.annotations[0].lineWidth
        property.scrollWheel(with: wheel(1)); property.scrollWheel(with: wheel(1)); property.finish()
        precondition(model.annotations[0].lineWidth == originalWidth + 2)
        model.undoLastAnnotation(); precondition(model.annotations[0].lineWidth == originalWidth)
        let firstOwner = UUID(), secondOwner = UUID()
        model.beginToolPropertyAdjustment(owner: firstOwner); model.setLineWidth(originalWidth + 1)
        model.beginToolPropertyAdjustment(owner: secondOwner); model.setRectangleCornerRadius(12)
        model.endToolPropertyAdjustment(owner: firstOwner)
        model.setRectangleCornerRadius(16); model.endToolPropertyAdjustment(owner: secondOwner)
        model.undoLastAnnotation()
        precondition(model.annotations[0].lineWidth == originalWidth + 1 && model.annotations[0].rectangleCornerRadius == nil,
                     "a previous control's delayed finish must not split the next control's undo group")
        model.undoLastAnnotation(); precondition(model.annotations[0].lineWidth == originalWidth)
        let untouchedWidth = model.annotations[0].lineWidth
        property.enabled = false; property.scrollWheel(with: wheel(1)); property.finish()
        precondition(model.annotations[0].lineWidth == untouchedWidth)
        model.selectedAnnotationID = shape.id
        model.setColor(.green)
        precondition(pin.pinDocument.annotations[0].color == .green,
                     "pin edits must update the document immediately, without Apply")
        pin.finishEditing()
        precondition(pin.presentation.editor == nil && pin.pinDocument.annotations[0].color == .green)
        precondition(pin.window!.frame == beforeEdit && pin.presentation.opacity == beforeOpacity)
        pin.beginEditing()
        precondition(pin.presentation.editor === model, "reopening the tools must retain undo history")
        pin.presentation.editor!.undoLastAnnotation()
        precondition(pin.pinDocument.annotations == doc.annotations, "undo must restore the earlier edit after reopening")
        pin.presentation.editor!.selectedAnnotationID = shape.id
        pin.presentation.editor!.setColor(.green)
        pin.finishEditing()
        precondition(pin.pinDocument.annotations[0].color == .green && pin.presentation.editor == nil)
        let applied = pin.presentation.image.tiffRepresentation!
        precondition(applied != originalPixels)
        for _ in 0..<4 { pin.beginEditing(); pin.finishEditing() }
        precondition(pin.pinDocument.baseImage === base, "re-editing must retain the cropped immutable base, not the rendered pixels")
        precondition(pin.presentation.image.tiffRepresentation == applied, "unchanged re-edit must not repeatedly bake effects")
        precondition(pin.window!.frame == beforeEdit && pin.presentation.opacity == beforeOpacity)
        precondition(pin.window!.childWindows?.isEmpty != false)
        weak var releasedModel: OverlayViewModel?
        autoreleasepool {
            pin.close()
            let other = PinnedImageWindowController(image: base, document: doc, settings: settings)
            other.beginEditing(); releasedModel = other.presentation.editor
            other.close()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        precondition(releasedModel == nil && pin.presentation.editor == nil)
        for _ in 0..<10 {
            weak var closedPin: PinnedImageWindowController?
            weak var croppedBase: NSImage?
            autoreleasepool {
                let source = NSImage(cgImage: bitmap.makeImage()!, size: CGSize(width: 160, height: 120))
                croppedBase = source
                let item = PinnedImageWindowController(image: source,
                    document: PinnedImageDocument(baseImage: source, roundedCorners: false), settings: settings)
                closedPin = item
                item.beginEditing(); item.finishEditing(); item.close()
            }
            precondition(closedPin == nil && croppedBase == nil, "closed pin windows must release their documents and cropped source")
        }
        print("PASS: blank move at current zoom, drawing/handle isolation, double-click direct PNG save without ending editing, compact collapse tools, live edits and retained undo/model release")
    }

    @MainActor static func checkPinShortcuts() {
        let suite = "LibreShot.PinChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let pin = EditorShortcut(keyCode: kVK_ANSI_P, modifiers: cmdKey)
        precondition(settings.editorShortcuts[ToolbarItem.pin.rawValue] == pin)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing; model.selectionRect = CGRect(x: 30, y: 50, width: 100, height: 80)
        var captures = 0
        model.onCapture = { rect, _, action, _ in
            precondition(action == .pin && rect == model.selectionRect); captures += 1
        }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 1,
            windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_P))!
        let editingWindow = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        editingWindow.isReleasedWhenClosed = false; editingWindow.bindEditingActions(to: model)
        precondition(editingWindow.performKeyEquivalent(with: key) && captures == 1)
        let repeated = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 2,
            windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: true,
            keyCode: UInt16(kVK_ANSI_P))!
        precondition(model.performEditorShortcut(repeated) && captures == 1)
        precondition(!model.performEditorShortcut(key, textResponder: true) && captures == 1)
        precondition(settings.setEditorShortcut(pin, for: .ocr) != nil)
        precondition(settings.setEditorShortcut(nil, for: .pin) == nil)
        precondition(SettingsService(defaults: defaults).editorShortcuts[ToolbarItem.pin.rawValue] == nil,
                     "an explicitly cleared pin binding must stay cleared after restart")
        let custom = EditorShortcut(keyCode: kVK_ANSI_P, modifiers: cmdKey | shiftKey)
        precondition(settings.setEditorShortcut(custom, for: .pin) == nil)
        precondition(SettingsService(defaults: defaults).editorShortcuts[ToolbarItem.pin.rawValue] == custom)
        settings.restoreDefaultEditorShortcuts()
        precondition(settings.editorShortcuts[ToolbarItem.pin.rawValue] == pin)
        var legacy = EditorShortcut.defaults; legacy.removeValue(forKey: ToolbarItem.pin.rawValue)
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "editorShortcuts")
        precondition(SettingsService(defaults: defaults).editorShortcuts[ToolbarItem.pin.rawValue] == nil,
                     "existing shortcut configurations must not gain unsolicited bindings")
        editingWindow.clearEditingActions(); editingWindow.close(); model.reset()
        print("PASS: default Cmd+P through native editor window, repeat/text protection, conflicts, custom/cleared/legacy bindings and explicit restore")
    }
}
