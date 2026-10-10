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
            for width: CGFloat in [240, 400] {
                for annotation in [rounded, colorfulNumber] {
                    second.selectTool(nil); second.selectedAnnotationID = annotation.id
                    let size = ToolPropertyBarView.size(for: second, availableWidth: width)
                    let hosting = NSHostingView(rootView: ToolPropertyBarView(viewModel: second, availableWidth: width).padding(12).environment(\.colorScheme, .light))
                    let bounds = CGRect(x: 0, y: 0, width: size.width + 24, height: size.height + 24)
                    let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = hosting; window.orderFrontRegardless()
                    hosting.frame = bounds; window.layoutIfNeeded(); hosting.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
                    let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("\(annotation.type.rawValue)-\(Int(width)).png"))
                    window.orderOut(nil)
                }
            }
        }
        print("PASS: radius migration, resizing, hit testing, independent number inks, undo/reset and persistence")
        print("PASS: automatic properties, legacy gear migration, narrow widths and edge placement")
        print("PASS: independent tool defaults, legacy migration, drawing, selected editing, undo/reset and relaunch persistence")
    }
}
