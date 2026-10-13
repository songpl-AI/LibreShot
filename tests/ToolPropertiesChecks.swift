import AppKit
import SwiftUI

@main
struct ToolPropertiesChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor
    static func checkExport(rounded: Annotation, number: Annotation) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 400,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<400 { for x in 0..<500 { bitmap.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: x, y: y) } }
        let base = NSImage(size: CGSize(width: 500, height: 400)); base.addRepresentation(bitmap)
        let result = CaptureService().composite(image: base, annotations: [rounded, number])
        let decoded = NSBitmapImageRep(data: result.tiffRepresentation!)!
        func rgb(_ x: Int, _ y: Int) -> NSColor { decoded.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)! }
        require(rgb(50, 50).redComponent > 0.95 && rgb(50, 50).greenComponent > 0.95, "Export leaves rounded outer corner unpainted")
        require(rgb(100, 50).redComponent > 0.9 && rgb(100, 50).greenComponent < 0.5, "Export draws the rectangle top edge")
        let radius = number.numberRadius
        let fill = rgb(300 + Int(radius / 2), 200)
        require(fill.redComponent > 0.8 && fill.greenComponent > 0.8 && fill.blueComponent < 0.3, "Export uses independent yellow fill")
        let border = rgb(300 + Int(radius), 200)
        require(border.blueComponent > 0.5 && border.redComponent < 0.5, "Export uses independent blue border")
        var purplePixels = 0
        for y in 180..<220 { for x in 290..<310 {
            let c = rgb(x, y)
            if c.blueComponent > 0.3 && c.redComponent > c.greenComponent + 0.15 { purplePixels += 1 }
        } }
        require(purplePixels > 0, "Export contains explicitly colored purple digits")
        print("PASS: decoded export pixels for rounded rectangle, border, fill and digit color")
    }

    @MainActor
    static func main() throws {
        let suite = "LibreShot.ToolProperties.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("outline", forKey: "numberAnnotationStyle")
        defaults.set(["cancel", "style", "arrow", "complete"], forKey: "toolbarItemOrder")
        defaults.set(["style"], forKey: "hiddenToolbarItems")
        defaults.set(try JSONEncoder().encode(["style": EditorShortcut(keyCode: 3, modifiers: 0)]), forKey: "editorShortcuts")
        let settings = SettingsService(defaults: defaults)
        require(settings.menuBarLeftClickAction == .selection && settings.showSelectionGuides, "New interaction settings default to direct selection and visible guides")
        settings.menuBarLeftClickAction = .menu
        settings.showSelectionGuides = false
        let reloaded = SettingsService(defaults: defaults)
        require(reloaded.menuBarLeftClickAction == .menu && !reloaded.showSelectionGuides, "Menu and guide preferences survive relaunch")
        defaults.set("unknown", forKey: "menuBarLeftClickAction")
        require(SettingsService(defaults: defaults).menuBarLeftClickAction == .selection, "Invalid menu preferences recover to region capture")
        checkInitialDefaults()
        checkCompactProperties(settings: settings)
        checkNativePropertyInput()
        let vm = OverlayViewModel(settings: settings)
        vm.state = .editing
        vm.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        require(settings.editorShortcuts["style"] == nil, "Retired gear shortcut does not reserve a key")
        require(!vm.visibleToolbarItems.contains(.style), "Legacy gear entry is retired")
        require(Array(vm.visibleToolbarItems.prefix(4)) == [.cancel, .arrow, .complete, .select], "Upgrade retains remaining custom order")
        require(vm.propertyTool == nil, "No properties without a tool or selected object")
        vm.selectTool(.rectangle)
        vm.setColor(.blue)
        vm.setLineWidth(8)
        vm.startDrawing(at: CGPoint(x: 40, y: 40))
        vm.updateDrawing(to: CGPoint(x: 200, y: 180))
        vm.endDrawing()
        require(vm.annotations.count == 1, "Rectangle must be created")
        let rectangle = vm.annotations[0]
        require(rectangle.lineWidth == 8, "Drawing must use configured stroke width")
        vm.selectTool(.arrow)
        require(vm.currentToolStyle.lineWidth == 3, "Arrow width must be independent")
        vm.setLineWidth(5)
        vm.selectTool(.rectangle)
        require(vm.currentToolStyle.lineWidth == 8, "Switching tools restores defaults")
        vm.selectedAnnotationID = rectangle.id
        vm.setLineWidth(12)
        require(vm.annotations[0].lineWidth == 12, "Selected shape updates")
        vm.undoLastAnnotation()
        require(vm.annotations[0] == rectangle, "Style edit must undo without removing shape")
        require(vm.currentToolStyle.lineWidth == 8, "Panel reads restored object")
        require(settings.annotationStyle(for: .rectangle).lineWidth == 12, "Canvas undo leaves next-object preference intact")
        vm.restoreCurrentToolDefaults()
        require(vm.annotations[0].lineWidth == 3, "Reset updates selected object")
        vm.undoLastAnnotation()
        require(vm.annotations[0] == rectangle, "Reset is one undoable edit")
        require(settings.annotationStyle(for: .arrow).lineWidth == 5, "Reset affects only current tool")
        vm.selectTool(.text)
        vm.setFontSize(40)
        vm.selectTool(.number)
        require(vm.currentToolStyle.numberStyle == .outline, "Legacy sequence style retained")
        vm.setFontSize(32)
        vm.setNumberStyle(.filled)
        vm.placeNumber(at: CGPoint(x: 250, y: 150))
        let number = vm.annotations.last!
        require(number.fontSize == 32 && number.numberStyle == .filled, "Number uses its own properties")
        vm.selectedAnnotationID = number.id
        vm.setFontSize(48)
        vm.undoLastAnnotation()
        require(vm.annotations.last == number, "Number font edit undoes")
        vm.selectTool(.mosaic)
        vm.setEffectDrawingMode(.brush, for: .mosaic)
        vm.setEffectValue(60, parameter: "width")
        vm.setEffectValue(24, parameter: "block")
        vm.selectTool(.blur)
        require(vm.effectValue("width") == 20, "Effect brush widths are independent")
        vm.setEffectValue(8, parameter: "radius")
        let relaunched = SettingsService(defaults: defaults)
        let second = OverlayViewModel(settings: relaunched)
        second.selectTool(.text)
        require(second.currentToolStyle.fontSize == 40, "Text size survives restart")
        second.selectTool(.number)
        require(second.currentToolStyle.fontSize == 48, "Number size survives restart independently")
        second.selectTool(.mosaic)
        require(second.effectDrawingMode(for: .mosaic) == .brush && second.effectValue("width") == 60 && second.effectValue("block") == 24, "Mosaic properties survive restart")
        second.selectTool(.blur)
        require(second.effectValue("radius") == 8 && second.effectValue("width") == 20, "Blur properties survive independently")
        second.selectTool(.rectangle)
        require(second.currentToolStyle == .factory(for: .rectangle), "Reset survives restart")
        // Merely selecting a differently styled object must not overwrite tool defaults.
        var old = Annotation(type: .rectangle, color: .green)
        old.lineWidth = 2
        second.annotations = [old]
        second.selectedAnnotationID = old.id
        require(second.currentToolStyle.lineWidth == 2, "Panel shows selected object's properties")
        require(relaunched.annotationStyle(for: .rectangle).lineWidth == 3, "Reading selected properties does not persist them")
        second.selectTool(.arrow)
        second.setLineWidth(1000)
        require(second.currentToolStyle.lineWidth == 20, "Invalid values are bounded")
        for width: CGFloat in [220, 400, 900] {
            let screen = CGSize(width: width, height: 700)
            for tool in [AnnotationType.rectangle, .arrow, .text, .number, .mosaic, .blur] {
                second.selectTool(tool)
                let propertySize = ToolPropertyBarView.size(for: second, availableWidth: width - 20)
                require(propertySize.width <= width - 20 && propertySize.height > 0, "Automatic property bar fits narrow widths")
                let layout = ToolbarLayout(items: second.visibleToolbarItems, availableWidth: width - 20)
                for y: CGFloat in [20, 300, 560] {
                    let crop = CGRect(x: 20, y: y, width: width - 40, height: 100)
                    let frame = layout.frame(selection: crop, screenSize: screen, accessorySize: CGSize(width: propertySize.width, height: propertySize.height + 8))
                    require(frame.minX >= 10 && frame.maxX <= width - 10 && frame.minY >= 10 && frame.maxY <= 690, "Toolbar and properties stay inside screen edges")
                    require(frame.contains(CGPoint(x: frame.midX, y: frame.maxY - 1)), "Property row belongs to toolbar hit exclusion")
                }
            }
        }
        second.selectTool(nil)
        require(ToolPropertyBarView.size(for: second, availableWidth: 400) == .zero, "Property bar hides when selection is cleared")
        // Decode preferences produced before the new optional fields existed.
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnnotationToolStyle.factory(for: .rectangle))) as! [String: Any]
        oldJSON.removeValue(forKey: "rectangleCornerRadius")
        let migrated = try JSONDecoder().decode(AnnotationToolStyle.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        require(migrated.rectangleCornerRadius == nil && migrated.lineWidth == 3, "Older preferences retain straight corners and line width")
        second.state = .editing
        second.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        second.selectTool(.rectangle)
        second.setRectangleCornerRadius(32)
        second.startDrawing(at: CGPoint(x: 50, y: 50))
        second.updateDrawing(to: CGPoint(x: 150, y: 150)); second.endDrawing()
        let rounded = second.annotations.last!
        require(rounded.rectangleCornerRadius == 32, "New rectangle uses saved corner radius")
        require(!rounded.containsSelectionPoint(CGPoint(x: 50, y: 50)), "Rounded empty corner is not a visible-stroke hit")
        require(rounded.containsSelectionPoint(CGPoint(x: 100, y: 50)), "Rounded top stroke remains selectable")
        second.selectedAnnotationID = rounded.id
        second.setRectangleCornerRadius(8)
        second.undoLastAnnotation()
        require(second.annotations.last == rounded, "Radius edit is undoable")
        var tiny = rounded; tiny.endPoint = CGPoint(x: 60, y: 60)
        require(tiny.rectanglePath.boundingBox.width == 10, "Radius clamps to resized shape instead of expanding bounds")
        second.selectTool(.number)
        second.setNumberStyle(.filled)
        second.setNumberColor(.blue, role: .border)
        second.setNumberColor(.yellow, role: .fill)
        second.setNumberColor(.purple, role: .digit)
        second.placeNumber(at: CGPoint(x: 300, y: 200))
        let colorfulNumber = second.annotations.last!
        require(colorfulNumber.numberBorderInk == AnnotationInk(.blue) && colorfulNumber.numberFillInk == AnnotationInk(.yellow), "Border and fill remain independent")
        require(colorfulNumber.textColor.usingColorSpace(.sRGB) == NSColor(Color.purple).usingColorSpace(.sRGB), "Digit uses explicit color")
        second.selectedAnnotationID = colorfulNumber.id
        second.setNumberColor(nil, role: .digit)
        require(second.annotations.last!.textColor == .black, "Automatic digits contrast with actual yellow fill")
        second.undoLastAnnotation()
        require(second.annotations.last == colorfulNumber, "Digit edit is independently undoable")
        second.setNumberStyle(.outline)
        require(second.annotations.last!.numberFillInk == AnnotationInk(.yellow), "Changing mode preserves unused fill")
        second.restoreCurrentToolDefaults()
        require(second.annotations.last!.numberDigitInk == nil && second.annotations.last!.numberBorderInk == nil, "Reset clears explicit inks")
        second.undoLastAnnotation()
        require(second.annotations.last!.numberDigitInk == AnnotationInk(.purple), "Reset restores all inks with one undo")
        let stored = SettingsService(defaults: defaults)
        require(stored.annotationStyle(for: .rectangle).rectangleCornerRadius == 8, "Radius default survives settings reload")
        // Explicit color changes persist independently of canvas undo.
        second.selectTool(.number)
        second.setNumberColor(.green, role: .digit)
        require(SettingsService(defaults: defaults).annotationStyle(for: .number).numberDigitInk == AnnotationInk(.green), "Number ink survives settings reload")
        var legacyNumber = Annotation(type: .number, color: .red)
        legacyNumber.numberStyle = .filled
        require(legacyNumber.numberBorderWidth == 0 && legacyNumber.textColor == .white, "Legacy filled number keeps borderless automatic appearance")
        legacyNumber.numberStyle = .outline
        require(legacyNumber.numberBorderWidth == 3 && legacyNumber.textColor == NSColor(Color.red), "Legacy outline appearance is preserved")
        try checkExport(rounded: rounded, number: colorfulNumber)
        if let output = ProcessInfo.processInfo.environment["LIBRESHOT_PROPERTY_QA_OUTPUT"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            second.annotations = [rounded, colorfulNumber]
            for dark in [false, true] {
                let view = ZStack {
                    (dark ? Color(red: 0.12, green: 0.17, blue: 0.23) : Color(red: 0.91, green: 0.94, blue: 0.97))
                    Text("LibreShot · 对齐参考").font(.system(size: 24)).foregroundStyle(dark ? .white : .black)
                    SelectionGuidesView(point: CGPoint(x: 230, y: 105))
                }
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 280), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting; window.orderFrontRegardless(); window.layoutIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
                let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("guides-\(dark ? "dark" : "light").png"))
                window.orderOut(nil)
            }
            func render(_ width: CGFloat, name: String, scheme: ColorScheme = .light) throws {
                let size = ToolPropertyBarView.size(for: second, availableWidth: width)
                let hosting = NSHostingView(rootView: ToolPropertyBarView(viewModel: second, availableWidth: width).padding(12).environment(\.colorScheme, scheme))
                let bounds = CGRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24)
                let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = hosting; window.orderFrontRegardless()
                hosting.frame = bounds; window.layoutIfNeeded(); hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
                let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
                window.orderOut(nil)
            }
            for width: CGFloat in [200, 400, 640] {
                for annotation in [rounded, colorfulNumber] {
                    second.selectTool(nil); second.selectedAnnotationID = annotation.id
                    try render(width, name: "\(annotation.type.rawValue)-\(Int(width))")
                    if annotation.type == .number {
                        second.toolPropertyDetailsExpanded = true
                        try render(width, name: "number-details-\(Int(width))")
                        second.toolPropertyDetailsExpanded = false
                    }
                }
                for tool in [AnnotationType.pen, .ellipse, .arrow, .text, .mosaic, .blur] {
                    second.selectTool(tool)
                    try render(width, name: "\(tool.rawValue)-\(Int(width))")
                }
            }
            second.selectTool(.number); second.toolPropertyDetailsExpanded = true
            try render(640, name: "number-details-dark", scheme: .dark)
            second.selectTool(.rectangle); second.restoreCurrentToolDefaults()
            try render(640, name: "rectangle-defaults-640")
            second.selectTool(.text); second.restoreCurrentToolDefaults()
            try render(640, name: "text-defaults-640")
        }
        print("PASS: radius migration, resizing, hit testing, independent number inks, undo/reset and persistence")
        print("PASS: automatic properties, legacy gear migration, narrow widths and edge placement")
        print("PASS: independent tool defaults, legacy migration, drawing, selected editing, undo/reset and relaunch persistence")
    }

    @MainActor
    static func checkInitialDefaults() {
        let suite = "LibreShot.InitialProperties.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        model.selectTool(.rectangle)
        model.startDrawing(at: CGPoint(x: 40, y: 40))
        model.updateDrawing(to: CGPoint(x: 180, y: 160)); model.endDrawing()
        require(model.annotations[0].lineWidth == 3 && model.annotations[0].rectangleCornerRadius == 8, "First rectangle uses a moderate stroke and subtle corner radius")
        model.setRectangleCornerRadius(32)
        require(SettingsService(defaults: defaults).annotationStyle(for: .rectangle).rectangleCornerRadius == 32, "Existing custom radius remains preferred after reload")
        model.restoreCurrentToolDefaults()
        require(settings.annotationStyle(for: .rectangle).rectangleCornerRadius == 8, "Reset restores the same initial corner radius")
        model.selectTool(.text)
        require(model.inputFontSize == 24, "First text uses a readable 24-point font")
        model.selectTool(.number); model.placeNumber(at: CGPoint(x: 220, y: 140))
        require(model.annotations.last!.fontSize == 16, "First number keeps its compact 16-point font")
        model.selectTool(.mosaic)
        require(model.effectValue("width") == 20 && model.effectValue("block") == 16, "First mosaic uses moderate brush and grain values")
        model.selectTool(.blur)
        require(model.effectValue("width") == 20 && model.effectValue("radius") == 12, "First blur uses moderate brush and intensity values")
        print("PASS: first-use drawing defaults, custom preference preservation and reset consistency")
    }

    @MainActor
    static func checkNativePropertyInput() {
        _ = NSApplication.shared
        let suite = "LibreShot.CompactInput.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverlayViewModel(settings: SettingsService(defaults: defaults))
        model.state = .editing; model.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        model.selectTool(.rectangle)
        var cancelled = false, captured = false
        model.onCapture = { _, _, _, _ in captured = true }
        let size = ToolPropertyBarView.size(for: model, availableWidth: 640)
        let window = OverlayWindow(contentRect: CGRect(x: 80, y: 80, width: size.width + 24, height: size.height + 24), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isReleasedWhenClosed = false; window.bindEditingActions(to: model)
        window.onEscapeKey = { cancelled = true }
        let hosting = NSHostingView(rootView: ToolPropertyBarView(viewModel: model, availableWidth: 640).padding(12))
        window.contentView = hosting; window.makeKeyAndOrderFront(nil)
        func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1)) }
        settle()
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? view.subviews.flatMap(fields)
        }
        func colorWells(_ view: NSView) -> [NSColorWell] {
            (view as? NSColorWell).map { [$0] } ?? view.subviews.flatMap(colorWells)
        }
        let wells = colorWells(hosting)
        require(wells.count == 1 && wells[0].frame.size == CGSize(width: 22, height: 22), "Custom palette icon keeps the same button hit area as the presets")
        let clickPoint = wells[0].convert(CGPoint(x: 11, y: 11), to: nil)
        let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: clickPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(mouseUp, atStart: true)
        wells[0].mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: clickPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!)
        settle()
        require(wells[0].isActive && NSColorPanel.shared.isVisible, "Mouse click on palette icon opens the color panel")
        NSColorPanel.shared.performClose(nil)
        settle()
        wells[0].mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: clickPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!)
        require(wells[0].isActive && NSColorPanel.shared.isVisible, "Mouse click reopens a closed color panel")
        wells[0].deactivate()
        NSColorPanel.shared.orderOut(nil)
        wells[0].activate(true)
        require(wells[0].isActive, "Compact swatch retains native color-panel activation")
        require(NSColorPanel.shared.level.rawValue > window.level.rawValue, "Color panel appears above the production screenshot overlay")
        wells[0].deactivate()
        NSColorPanel.shared.orderOut(nil)
        let inputs = fields(hosting)
        require(inputs.count == 2, "Native compact rectangle exposes two exact value inputs")
        let input = inputs.first { $0.stringValue == "3" }!
        func enterDraft(_ text: String) {
            require(window.makeFirstResponder(input), "Exact value field accepts focus")
            settle()
            let editor = window.firstResponder as! NSTextView
            editor.insertText(text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            settle()
        }
        func key(_ code: UInt16, _ characters: String) {
            window.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!)
            settle()
        }
        enterDraft("7.5"); key(36, "\r")
        require(model.currentToolStyle.lineWidth == 7.5 && !captured, "Return commits an exact fractional value without exporting")
        enterDraft("18"); key(53, "\u{1b}")
        require(model.currentToolStyle.lineWidth == 7.5 && !cancelled && !captured, "Native Escape discards the draft and preserves the capture")
        enterDraft("invalid"); key(36, "\r")
        require(model.currentToolStyle.lineWidth == 7.5 && !captured, "Invalid native input restores the current value")
        model.setLineWidth(18); settle()
        require(model.currentToolStyle.lineWidth == 18 && input.stringValue == "18", "Rendering a saved width above the common drag limit must not clamp the model or exact field")
        enterDraft("19"); key(36, "\r")
        require(model.currentToolStyle.lineWidth == 19, "Exact input still accepts supported values above the common drag range")
        window.orderOut(nil); window.clearEditingActions()
        print("PASS: native exact input, Return commit, Escape cancellation, shortcut isolation")
    }

    @MainActor
    static func checkCompactProperties(settings: SettingsService) {
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        model.selectTool(.rectangle)
        var rectangle = Annotation(type: .rectangle, color: .red)
        rectangle.startPoint = CGPoint(x: 40, y: 40); rectangle.endPoint = CGPoint(x: 180, y: 160)
        model.annotations = [rectangle]; model.selectedAnnotationID = rectangle.id
        let stored = settings.annotationStyle(for: .rectangle)
        model.beginToolPropertyAdjustment()
        for width: CGFloat in [4, 7, 11] { model.setLineWidth(width) }
        require(model.annotations[0].lineWidth == 11, "Slider previews intermediate changes on the object")
        require(settings.annotationStyle(for: .rectangle) == stored, "Drag does not persist every intermediate value")
        model.endToolPropertyAdjustment()
        require(settings.annotationStyle(for: .rectangle).lineWidth == 11, "Gesture completion persists the final value")
        model.undoLastAnnotation()
        require(model.annotations == [rectangle], "One undo restores the complete drag")
        model.beginToolPropertyAdjustment(); model.setLineWidth(6); model.setLineWidth(rectangle.lineWidth)
        model.endToolPropertyAdjustment();
        require(settings.annotationStyle(for: .rectangle).lineWidth == 11, "A no-op drag does not overwrite the saved next-object style")
        model.undoLastAnnotation()
        require(model.annotations.isEmpty, "A drag returning to its starting value creates no extra undo")
        model.selectTool(.text)
        let oldFont = settings.annotationStyle(for: .text).fontSize
        model.beginToolPropertyAdjustment(); model.setFontSize(39)
        require(model.currentToolStyle.fontSize == 39 && settings.annotationStyle(for: .text).fontSize == oldFont, "Defaults-only drag previews without writing preferences")
        model.selectTool(.arrow)
        require(settings.annotationStyle(for: .text).fontSize == 39 && model.currentToolStyle.lineWidth == 3, "Tool switch commits the outgoing gesture without changing the next tool")
        model.selectTool(.rectangle)
        require(ToolPropertyBarView.size(for: model, availableWidth: 640) == CGSize(width: 385, height: 26), "Rectangle controls reserve the tightened single-row bounds")
        model.selectTool(.number)
        let compact = ToolPropertyBarView.size(for: model, availableWidth: 640)
        model.toolPropertyDetailsExpanded = true
        require(ToolPropertyBarView.size(for: model, availableWidth: 640).height == compact.height + 50, "Detailed number colors reserve their own hit area")
        for tool in [AnnotationType.rectangle, .ellipse, .arrow, .pen, .text, .number, .mosaic, .blur] {
            model.selectTool(tool)
            for width: CGFloat in [200, 400, 640] {
                let rows = ToolPropertyBarView.rows(for: model, availableWidth: width)
                require(rows.flatMap { $0 }.filter { $0 == .actions }.count == 1, "Each layout keeps exactly one reset entry")
                for row in rows {
                    let usable = width - ToolPropertyBarView.inset * 2
                    let occupied = row.reduce(CGFloat(0)) { $0 + min($1.width, usable) } + CGFloat(max(0, row.count - 1)) * ToolPropertyBarView.spacing
                    require(occupied <= usable, "All property controls fit their reserved row")
                }
            }
        }
        require(CompactPropertySlider.parsed(" 7.5 ", range: 1...20) == 7.5, "Exact input supports intermediate values")
        require(CompactPropertySlider.parsed("999", range: 1...20) == 20, "Exact input is bounded by the supported range")
        require(CompactPropertySlider.parsed("nan", range: 1...20) == nil && CompactPropertySlider.parsed("", range: 1...20) == nil, "Invalid drafts cannot reach annotations")
        let inputID = UUID(); model.beginToolPropertyValueEditing(inputID)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
        let cancellation = model.toolPropertyInputCancellation
        require(model.performEditorShortcut(escape, textResponder: true) && model.toolPropertyInputCancellation != cancellation && model.state == .editing, "Escape cancels a property draft without cancelling the capture")
        model.reset()
        require(!model.toolPropertyDetailsExpanded, "New sessions start with compact common controls")
        for tool in [AnnotationType.rectangle, .text, .arrow] {
            settings.setAnnotationStyle(.factory(for: tool), for: tool)
        }
        print("PASS: compact layout, precise drafts, slider live preview, grouped undo and final-value persistence")
    }
}
