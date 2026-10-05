import AppKit
import SwiftUI

@main
struct Issue9RegressionChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var failures = 0
        func check(_ passed: Bool, _ label: String) {
            print("\(passed ? "PASS" : "FAIL"): \(label)")
            if !passed { failures += 1 }
        }
        // CGRequest can return false while authorization becomes observable on return.
        var authorized = false
        var loads = 0
        let marker = NSError(domain: "LibreShot.Issue9.AuthorizedLoad", code: 1)
        do {
            _ = try await ScreenCaptureAccess.content(preflight: { authorized }, request: {
                authorized = true
                return false
            }, load: { loads += 1; throw marker }, requestGate: ScreenCaptureRequestGate())
        } catch { }
        check(loads == 1, "new authorization is rechecked after the first system request")
        let suite = "LibreShot.Issue9.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        func model() -> OverlayViewModel {
            let vm = OverlayViewModel(settings: settings)
            vm.selectionRect = CGRect(x: 50, y: 50, width: 200, height: 160)
            vm.state = .editing
            return vm
        }
        for rounded in [false, true] {
            settings.useRoundedCorners = rounded
            let vm = model()
            let bitmap = render(OverlayView(viewModel: vm, showsToolbar: false).background(Color.white))
            let scale = CGFloat(bitmap.pixelsWide) / 320
            let corner = bitmap.colorAt(x: Int(52 * scale), y: Int(57 * scale))!.usingColorSpace(.deviceRGB)!
            check(rounded ? corner.redComponent < 0.85 : corner.redComponent > 0.9,
                  "selection preview reflects \(rounded ? "rounded" : "square") output corners")
        }
        for tool in [AnnotationType.rectangle, .ellipse, .arrow, .mosaic] {
            let vm = model()
            vm.selectedTool = tool
            vm.startDrawing(at: CGPoint(x: 90, y: 90))
            check(vm.currentAnnotation == nil, "\(tool): pointer down does not display a zero-size shape")
            vm.endDrawing()
            check(vm.annotations.isEmpty, "\(tool): click does not commit an invalid shape")
            vm.startDrawing(at: CGPoint(x: 90, y: 90))
            vm.updateDrawing(to: CGPoint(x: 92, y: 91))
            vm.endDrawing()
            check(vm.annotations.isEmpty, "\(tool): tiny pointer jitter does not create a shape")
            vm.startDrawing(at: CGPoint(x: 90, y: 90))
            vm.updateDrawing(to: CGPoint(x: 160, y: 140))
            vm.endDrawing()
            check(vm.annotations.count == 1 && vm.annotations[0].startPoint == CGPoint(x: 90, y: 90),
                  "\(tool): a real drag preserves its down position")
        }
        let continuous = model()
        let penSelection = model()
        var loop = Annotation(type: .pen, color: .red)
        loop.points = [CGPoint(x: 80, y: 80), CGPoint(x: 200, y: 80), CGPoint(x: 200, y: 160), CGPoint(x: 80, y: 160), CGPoint(x: 82, y: 82)]
        loop.startPoint = loop.points.first!; loop.endPoint = loop.points.last!
        penSelection.annotations = [loop]; penSelection.selectedAnnotationID = loop.id; penSelection.selectedTool = .pen
        let penBitmap = render(OverlayView(viewModel: penSelection, showsToolbar: false).background(Color.white))
        let penScale = CGFloat(penBitmap.pixelsWide) / 320
        var blueMaxX = 0, blueMaxY = 0
        for y in 65..<180 { for x in 65..<225 {
            let c = penBitmap.colorAt(x: Int(CGFloat(x) * penScale), y: Int(CGFloat(y) * penScale))!.usingColorSpace(.deviceRGB)!
            if c.blueComponent > c.redComponent + 0.1 {
                blueMaxX = max(blueMaxX, x); blueMaxY = max(blueMaxY, y)
            }
        } }
        check(blueMaxX >= 200 && blueMaxY >= 160, "closed freehand selection outline encloses every intermediate stroke point")
        _ = penSelection.handleSelectedShapeDrag(from: CGPoint(x: 140, y: 120), to: CGPoint(x: 160, y: 135), within: penSelection.selectionRect)
        penSelection.endSelectedShapeDrag()
        check(penSelection.annotations[0].points == loop.points.map { CGPoint(x: $0.x + 20, y: $0.y + 15) },
              "dragging the selected freehand bounding-box interior moves the whole stroke")
        penSelection.undoLastAnnotation()
        penSelection.annotations = [loop]; penSelection.selectedAnnotationID = loop.id
        _ = penSelection.handleSelectedShapeDrag(from: loop.points[0], to: CGPoint(x: 82, y: 81), within: penSelection.selectionRect)
        penSelection.endSelectedShapeDrag()
        check(penSelection.annotations == [loop], "small pointer jitter on selected stroke does not move it or create an undo entry")
        let penJitter = model(); penJitter.selectedTool = .pen
        penJitter.handleDrawingDrag(from: CGPoint(x: 90, y: 90), to: CGPoint(x: 92, y: 91)); penJitter.endDrawing()
        check(penJitter.annotations.isEmpty, "blank-space click jitter does not commit a new freehand stroke")
        penJitter.startDrawing(at: loop.startPoint)
        for point in loop.points.dropFirst() + [loop.startPoint] { penJitter.updateDrawing(to: point) }
        penJitter.endDrawing()
        check(penJitter.annotations.count == 1 && penJitter.annotations[0].points.count == 6,
              "a real closed freehand stroke remains valid when it returns to its starting point")
        let drawnLoop = penJitter.annotations[0]
        _ = penJitter.handleSelectedShapeDrag(from: loop.startPoint, to: CGPoint(x: 82, y: 81), within: penJitter.selectionRect)
        penJitter.endSelectedShapeDrag()
        penJitter.undoLastAnnotation()
        check(penJitter.annotations.isEmpty, "jitter does not add an undo step before undoing the original drawing")
        penJitter.annotations = [drawnLoop]; penJitter.selectedAnnotationID = drawnLoop.id
        _ = penJitter.handleSelectedShapeDrag(from: CGPoint(x: 140, y: 120), to: CGPoint(x: 160, y: 135), within: penJitter.selectionRect)
        _ = penJitter.handleSelectedShapeDrag(from: CGPoint(x: 140, y: 120), to: CGPoint(x: 140, y: 120), within: penJitter.selectionRect)
        penJitter.endSelectedShapeDrag()
        check(penJitter.annotations == [drawnLoop], "moving away and back restores the exact freehand points")
        check(penJitter.cursorStyle(at: CGPoint(x: 140, y: 120)) == .move,
              "freehand selection interior has the same move feedback as its visible stroke")
        continuous.selectedTool = .rectangle
        continuous.startDrawing(at: CGPoint(x: 80, y: 80))
        continuous.updateDrawing(to: CGPoint(x: 140, y: 120))
        continuous.endDrawing()
        check(continuous.selectedShapeRect != nil && continuous.selectedAnnotationID == continuous.annotations.first?.id,
              "newly completed rectangle immediately has resize handles")
        continuous.selectedTool = .arrow
        continuous.selectedAnnotationID = nil
        let border = CGPoint(x: 110, y: 80)
        _ = continuous.handleAnnotationPressChanged(from: border, to: border)
        _ = continuous.handleAnnotationPressEnded(from: border, to: border)
        continuous.clearAnnotationPress()
        check(continuous.selectedTool == .rectangle && continuous.selectedShapeRect != nil,
              "selecting an existing rectangle retains the rectangle tool")
        let before = continuous.annotations[0].startPoint
        check(continuous.handleSelectedShapeDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 110),
                                                 within: CGRect(x: 0, y: 0, width: 320, height: 260)),
              "selected rectangle moves while its drawing tool remains active")
        continuous.endSelectedShapeDrag()
        check(continuous.annotations[0].startPoint == CGPoint(x: before.x + 10, y: before.y + 10),
              "selected shape movement preserves absolute pointer-down offset")
        continuous.startDrawing(at: CGPoint(x: 180, y: 150))
        continuous.updateDrawing(to: CGPoint(x: 220, y: 190))
        continuous.endDrawing()
        check(continuous.annotations.count == 2 && continuous.selectedTool == .rectangle,
              "drawing can continue in empty space without reselecting the tool")
        let mosaic = model()
        mosaic.selectedTool = .mosaic
        mosaic.startDrawing(at: CGPoint(x: 140, y: 120))
        mosaic.updateDrawing(to: CGPoint(x: 80, y: 80))
        mosaic.endDrawing()
        let originalMosaic = mosaic.annotations[0]
        let mosaicRect = CGRect(x: 80, y: 80, width: 60, height: 40)
        check(mosaic.selectedShapeRect == mosaicRect && mosaic.selectedAnnotationID == originalMosaic.id,
              "reverse-drawn mosaic is immediately selected with resize handles")
        for handle in SelectionHandle.allCases {
            let point = handle.position(in: mosaicRect)
            let target = CGPoint(x: point.x + 10, y: point.y + 10)
            let expectedCursor: OverlayViewModel.CursorStyle
            switch handle {
            case .left, .right: expectedCursor = .horizontal
            case .top, .bottom: expectedCursor = .vertical
            case .topLeft, .bottomRight: expectedCursor = .diagonalDown
            case .topRight, .bottomLeft: expectedCursor = .diagonalUp
            }
            check(mosaic.cursorStyle(at: point) == expectedCursor, "mosaic \(handle) has directional hover feedback")
            check(mosaic.handleSelectedShapeDrag(from: point, to: target, within: mosaic.selectionRect),
                  "mosaic \(handle) accepts resizing with mosaic tool active")
            mosaic.endSelectedShapeDrag()
            let resized = mosaic.selectedShapeRect!
            let leftMoves = [.left, .topLeft, .bottomLeft].contains(handle)
            let rightMoves = [.right, .topRight, .bottomRight].contains(handle)
            let topMoves = [.top, .topLeft, .topRight].contains(handle)
            let bottomMoves = [.bottom, .bottomLeft, .bottomRight].contains(handle)
            check(resized.minX == mosaicRect.minX + (leftMoves ? 10 : 0)
                  && resized.maxX == mosaicRect.maxX + (rightMoves ? 10 : 0)
                  && resized.minY == mosaicRect.minY + (topMoves ? 10 : 0)
                  && resized.maxY == mosaicRect.maxY + (bottomMoves ? 10 : 0),
                  "mosaic \(handle) adjusts only its corresponding edges")
            mosaic.undoLastAnnotation()
            check(mosaic.annotations == [originalMosaic], "undo restores reverse-drawn mosaic after \(handle) resize")
        }
        let bottomRight = SelectionHandle.bottomRight.position(in: mosaicRect)
        _ = mosaic.handleSelectedShapeDrag(from: bottomRight, to: CGPoint(x: 500, y: 500), within: mosaic.selectionRect)
        mosaic.endSelectedShapeDrag()
        check(mosaic.selectedShapeRect?.maxX == mosaic.selectionRect.maxX
              && mosaic.selectedShapeRect?.maxY == mosaic.selectionRect.maxY,
              "mosaic resize stays inside the capture bounds")
        mosaic.undoLastAnnotation()
        _ = mosaic.handleSelectedShapeDrag(from: bottomRight, to: CGPoint(x: 0, y: 0), within: mosaic.selectionRect)
        mosaic.endSelectedShapeDrag()
        check(mosaic.selectedShapeRect?.size == CGSize(width: 12, height: 12),
              "mosaic resize cannot invert or collapse the effect region")
        mosaic.undoLastAnnotation()
        check(mosaic.cursorStyle(at: CGPoint(x: 100, y: 100)) == .move,
              "mosaic interior retains movement feedback")
        let selectedMosaicBitmap = render(OverlayView(viewModel: mosaic, showsToolbar: false).background(Color.white))
        mosaic.selectedAnnotationID = nil
        let unselectedMosaicBitmap = render(OverlayView(viewModel: mosaic, showsToolbar: false).background(Color.white))
        let mosaicScale = CGFloat(selectedMosaicBitmap.pixelsWide) / 320
        func mosaicPixel(_ bitmap: NSBitmapImageRep, _ point: CGPoint) -> NSColor {
            bitmap.colorAt(x: Int(point.x * mosaicScale), y: Int(point.y * mosaicScale))!.usingColorSpace(.deviceRGB)!
        }
        let handleColor = mosaicPixel(selectedMosaicBitmap, CGPoint(x: 110, y: 80))
        check(handleColor.blueComponent > handleColor.redComponent + 0.2,
              "selected mosaic renders solid blue circular handles")
        let haloPoint = CGPoint(x: 100, y: 75)
        check(mosaicPixel(selectedMosaicBitmap, haloPoint) == mosaicPixel(unselectedMosaicBitmap, haloPoint),
              "selected mosaic does not render the redundant outer blue halo")
        mosaic.selectedAnnotationID = originalMosaic.id
        _ = mosaic.handleSelectedShapeDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 110), within: mosaic.selectionRect)
        mosaic.endSelectedShapeDrag()
        check(mosaic.selectedShapeRect == mosaicRect.offsetBy(dx: 10, dy: 10), "mosaic interior still moves the entire effect")
        mosaic.undoLastAnnotation()
        mosaic.startDrawing(at: CGPoint(x: 180, y: 150))
        mosaic.updateDrawing(to: CGPoint(x: 220, y: 190))
        mosaic.endDrawing()
        check(mosaic.annotations.count == 2 && mosaic.selectedTool == .mosaic,
              "another mosaic can be drawn without switching tools after adjustment")
        let exportModel = model()
        exportModel.annotations = [originalMosaic]
        exportModel.selectedAnnotationID = originalMosaic.id
        exportModel.selectedTool = .mosaic
        _ = exportModel.handleSelectedShapeDrag(from: bottomRight, to: CGPoint(x: 170, y: 150), within: exportModel.selectionRect)
        exportModel.endSelectedShapeDrag()
        let exportContext = CGContext(data: nil, width: 320, height: 260, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<320 {
            exportContext.setFillColor(CGColor(gray: x.isMultiple(of: 2) ? 0 : 1, alpha: 1))
            exportContext.fill(CGRect(x: x, y: 0, width: 1, height: 260))
        }
        let exportSource = NSImage(cgImage: exportContext.makeImage()!, size: CGSize(width: 320, height: 260))
        let exportBoard = NSPasteboard(name: .init(suite))
        defer { exportBoard.releaseGlobally() }
        let exportService = CaptureService(settings: settings, pasteboard: exportBoard)
        var expectedMosaic = originalMosaic
        expectedMosaic.startPoint = CGPoint(x: 80, y: 80)
        expectedMosaic.endPoint = CGPoint(x: 170, y: 150)
        func exportedPixels(_ annotations: [Annotation]) -> Data {
            let image = exportService.composite(image: exportSource, annotations: annotations)
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!.dataProvider!.data! as Data
        }
        let adjustedPixels = exportedPixels(exportModel.annotations)
        check(adjustedPixels == exportedPixels([expectedMosaic]) && adjustedPixels != exportedPixels([originalMosaic]),
              "mosaic export uses the resized effect region rather than its original bounds")
        exportModel.selectedAnnotationID = nil
        check(adjustedPixels == exportedPixels(exportModel.annotations),
              "selection handles and blue feedback never enter mosaic export")
        exportModel.undoLastAnnotation()
        check(exportedPixels(exportModel.annotations) == exportedPixels([originalMosaic]),
              "undo restores the original mosaic export pixels")
        let deletion = model()
        var first = Annotation(type: .rectangle, color: .red)
        first.startPoint = CGPoint(x: 80, y: 80); first.endPoint = CGPoint(x: 140, y: 120)
        var second = Annotation(type: .ellipse, color: .blue)
        second.startPoint = CGPoint(x: 160, y: 100); second.endPoint = CGPoint(x: 220, y: 150)
        deletion.annotations = [first, second]
        deletion.selectedAnnotationID = first.id
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
                                      isARepeat: false, keyCode: 51)!
        check(!deletion.performEditorShortcut(delete, textResponder: true) && deletion.annotations.count == 2,
              "Delete in a text responder preserves annotations")
        check(deletion.performEditorShortcut(delete) && deletion.annotations.map(\.id) == [second.id],
              "Delete removes the selected annotation rather than the newest")
        deletion.undoLastAnnotation()
        check(deletion.annotations.map(\.id) == [first.id, second.id], "undo restores deleted annotation in its original layer")
        let arrowEdit = model()
        var arrow = Annotation(type: .arrow, color: .red)
        arrow.startPoint = CGPoint(x: 90, y: 100); arrow.endPoint = CGPoint(x: 180, y: 150)
        arrowEdit.annotations = [arrow]
        arrowEdit.selectedAnnotationID = arrow.id
        arrowEdit.selectedTool = .arrow
        check(arrowEdit.handleSelectedShapeDrag(from: arrow.startPoint, to: CGPoint(x: 80, y: 130),
                                                within: CGRect(x: 0, y: 0, width: 320, height: 260)), "arrow tail handle can be dragged")
        arrowEdit.endSelectedShapeDrag()
        check(arrowEdit.annotations[0].startPoint == CGPoint(x: 80, y: 130) && arrowEdit.annotations[0].endPoint == arrow.endPoint,
              "arrow endpoint adjustment preserves the opposite endpoint")
        arrowEdit.undoLastAnnotation()
        check(arrowEdit.annotations[0] == arrow, "undo restores arrow direction")
        check(continuous.cursorStyle(at: CGPoint(x: 50, y: 50)) == .diagonalDown,
              "crop corner gets a diagonal resize cursor before annotation handles")
        check(continuous.cursorStyle(at: CGPoint(x: 150, y: 50)) == .vertical,
              "crop top edge gets a vertical resize cursor")
        check(continuous.cursorStyle(at: CGPoint(x: 250, y: 130)) == .horizontal,
              "crop side gets a horizontal resize cursor")
        check(arrowEdit.cursorStyle(at: arrow.startPoint) == .move,
              "arrow endpoint gets a movable-handle cursor")
        let sourceContext = CGContext(data: nil, width: 320, height: 260, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        sourceContext.setFillColor(NSColor.white.cgColor)
        sourceContext.fill(CGRect(x: 0, y: 0, width: 320, height: 260))
        weak var editorSource: NSImage?
        let editor = autoreleasepool {
            let image = NSImage(cgImage: sourceContext.makeImage()!, size: CGSize(width: 320, height: 260))
            editorSource = image
            return ImageEditorWindowController(image: image, settings: settings)
        }
        editor.model.annotations = [first]
        check(editor.model.previewImage != nil, "editor fixture retains pixels while open")
        editor.close()
        check(editorSource == nil && editor.model.previewImage == nil && editor.model.annotations.isEmpty && editor.window?.contentView == nil,
              "closing a retained editor releases image and annotation state immediately")
        let firstMoved = model()
        firstMoved.selectedTool = .rectangle
        firstMoved.handleDrawingDrag(from: CGPoint(x: 90, y: 90), to: CGPoint(x: 170, y: 130))
        firstMoved.endDrawing()
        check(firstMoved.annotations.first?.startPoint == CGPoint(x: 90, y: 90), "first moved gesture callback preserves pointer-down coordinates")
        let arrowHead = arrowEdit.annotations[0].endPoint
        _ = arrowEdit.handleSelectedShapeDrag(from: arrowHead, to: arrowEdit.annotations[0].startPoint, within: CGRect(x: 0, y: 0, width: 320, height: 260))
        arrowEdit.endSelectedShapeDrag()
        check(arrowEdit.annotations[0].endPoint == arrowHead, "arrow cannot collapse to a zero-length endpoint")
        var label = Annotation(type: .text, color: .red)
        label.startPoint = CGPoint(x: 100, y: 100); label.text = "Resize text"
        let textResize = model()
        textResize.annotations = [label]; textResize.selectedAnnotationID = label.id; textResize.selectedTool = .text
        let textHandle = textResize.selectedTextResizeHandle!
        check(textResize.handleTextResizeDrag(from: textHandle, to: CGPoint(x: textHandle.x + 15, y: textHandle.y + 15)),
              "text resize remains available with the text tool active")
        textResize.endTextResize()
        check(textResize.annotations[0].fontSize > label.fontSize, "text handle changes font size")
        textResize.undoLastAnnotation()
        check(textResize.annotations[0] == label, "undo restores text before resizing")
        if let output = ProcessInfo.processInfo.environment["LIBRESHOT_ISSUE9_QA"] {
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
            let settingsBitmap = render(ToolbarSettingsView(settings: settings), size: CGSize(width: 560, height: 430))
            try opaque(settingsBitmap).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("toolbar-settings.png"))
            let overlayBitmap = render(OverlayView(viewModel: continuous, showsToolbar: false).background(Color.white))
            try overlayBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("annotation-handles.png"))
            try selectedMosaicBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("mosaic-handles.png"))
            try penBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("freehand-selection.png"))
        }
        guard failures == 0 else { exit(1) }
    }

    static func opaque(_ bitmap: NSBitmapImageRep) -> NSBitmapImageRep {
        // Export the transparent hosting-view snapshot on the window's light background.
        let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.draw(bitmap.cgImage!, in: rect)
        return NSBitmapImageRep(cgImage: context.makeImage()!)
    }

    @MainActor static func render<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 260)) -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if size.width > 320, let layer = hosting.layer {
            let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // NSHostingView's layer uses a top-left origin; CGContext uses bottom-left.
            context.translateBy(x: 0, y: CGFloat(bitmap.pixelsHigh))
            context.scaleBy(x: CGFloat(bitmap.pixelsWide) / size.width, y: -CGFloat(bitmap.pixelsHigh) / size.height)
            layer.render(in: context)
            window.close()
            return NSBitmapImageRep(cgImage: context.makeImage()!)
        }
        window.close()
        return bitmap
    }
}
