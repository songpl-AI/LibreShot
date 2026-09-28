import AppKit

@main
struct VisualWorkflowChecks {
    @MainActor static func main() async throws {
        let layout = ToolbarLayout(items: ToolbarItem.allCases, availableWidth: 660)
        precondition(layout.rows == [ToolbarItem.allCases] && layout.size.height == 42 && layout.size.width == 636,
                     "All enabled actions should fit on a single desktop-width row")
        print("PASS: full screenshot toolbar fits one row without a More menu")
        for width: CGFloat in [220, 300, 460, 620, 660, 1440] {
            let compact = ToolbarLayout(items: ToolbarItem.allCases, availableWidth: width)
            precondition(compact.size.width <= width && compact.rows.flatMap { $0 } == ToolbarItem.allCases)
            precondition(compact.rows.map(\.count).max()! - compact.rows.map(\.count).min()! <= 1)
            precondition(compact.rows.flatMap { $0 }.contains(.cancel) && compact.rows.flatMap { $0 }.contains(.complete))
        }
        print("PASS: narrow layouts wrap balanced rows without hiding enabled actions")
        let customized: [ToolbarItem] = [.pin, .ocr, .style, .select, .pen, .cancel, .complete, .translate]
        let allFit = ToolbarLayout(items: customized, availableWidth: 620)
        precondition(allFit.rows == [customized])
        let wrapped = ToolbarLayout(items: customized, availableWidth: 220)
        precondition(wrapped.rows == [[.pin, .ocr, .style, .select], [.pen, .cancel, .complete, .translate]],
                     "Custom order must remain intact across rows, including Style and Translate")
        print("PASS: customized order remains visible and stable when the toolbar wraps")

        let long = CGSize(width: 1400, height: 6200)
        let narrow = ImageEditorViewportLayout(imageSize: long, viewport: CGSize(width: 540, height: 600), mode: .fitWidth, zoom: 1)
        let wide = ImageEditorViewportLayout(imageSize: long, viewport: CGSize(width: 980, height: 600), mode: .fitWidth, zoom: 1)
        precondition(narrow.documentSize.width == 540 && wide.documentSize.width == 980)
        precondition(wide.zoom > narrow.zoom && narrow.imageOrigin.x == 20 && narrow.imageOrigin.y == 20)
        let fit = ImageEditorViewportLayout(imageSize: long, viewport: CGSize(width: 540, height: 600), mode: .fitImage, zoom: 1)
        precondition(fit.documentSize == CGSize(width: 540, height: 600) && fit.imageOrigin.x > 100)
        let small = ImageEditorViewportLayout(imageSize: CGSize(width: 220, height: 150), viewport: CGSize(width: 800, height: 600), mode: .fitImage, zoom: 1)
        precondition(small.zoom == 1 && small.imageOrigin == CGPoint(x: 290, y: 225))
        print("PASS: long images fit width after resize; full-image and small-image modes center without distortion")
        let colored = NSImage(size: CGSize(width: 400, height: 100))
        colored.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 400, height: 100).fill()
        ("Blue heading" as NSString).draw(at: CGPoint(x: 20, y: 38), withAttributes: [
            .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.systemBlue
        ])
        colored.unlockFocus()
        let cg = colored.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let region = OCRTextRegion(id: 1, text: "Blue heading", bounds: CGRect(x: 0.05, y: 0.25, width: 0.8, height: 0.45), confidence: 1)
        let result = try ImageTranslationRenderer.render(image: cg, regions: [.init(source: region, translation: "蓝色标题")], scale: CGFloat(cg.width) / 400)
        let bitmap = NSBitmapImageRep(cgImage: result.image)
        var bluePixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if c.blueComponent > c.redComponent + 0.3 && c.blueComponent > c.greenComponent + 0.1 { bluePixels += 1 }
            }
        }
        precondition(result.overflowIDs.isEmpty && bluePixels > 120, "Translated link/headline text must retain the source ink color")
        print("PASS: image translation retains the dominant source text color")

        if #available(macOS 26.0, *) {
            let suite = "LibreShot.Visual.Checks.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = OverlayViewModel(settings: SettingsService(defaults: defaults))
            model.state = .editing
            model.selectionRect = CGRect(x: 25, y: 20, width: 100, height: 60)
            model.updatePreviewImage(solidImage(width: 400, height: 240, color: .white), scale: 2)
            model.selectedTool = .text
            model.startTextInput(at: CGPoint(x: 40, y: 40))
            model.editingTextContent = "Keep this annotation"
            var captures = 0
            model.onCapture = { _, _, _, _ in captures += 1 }
            model.confirmImageTranslation()
            precondition(captures == 0 && model.state == .editing && model.translationSource?.size == CGSize(width: 100, height: 60))
            precondition(model.annotations.count == 1 && !model.isEditingText && !model.canExportSelection)
            model.confirmCopy()
            precondition(captures == 0, "Do not export incomplete or overflowing translations")
            let comparisonPoint = CGPoint(x: 100, y: 30)
            precondition(!model.canToggleTranslationPreview(from: comparisonPoint, to: comparisonPoint), "Incomplete translation cannot be compared")
            model.translatedSelection = solidImage(width: 200, height: 120, color: .systemBlue)
            model.translationCanExport = true
            precondition(!model.canToggleTranslationPreview(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10)))
            precondition(!model.canToggleTranslationPreview(from: comparisonPoint, to: CGPoint(x: 50, y: 68)), "Dragging should retain selection movement")
            precondition(model.canToggleTranslationPreview(from: comparisonPoint, to: comparisonPoint))
            let exported = NSBitmapImageRep(cgImage: model.imageForExport()!)
            precondition(exported.pixelsWide == 400 && exported.pixelsHigh == 240)
            precondition(exported.colorAt(x: 55, y: 45)!.blueComponent > 0.7)
            precondition(exported.colorAt(x: 55, y: 45)!.redComponent < 0.5)
            precondition(exported.colorAt(x: 55, y: 200)!.redComponent > 0.9, "Translation must not flip to the bottom or replace pixels outside the selection")
            model.toggleTranslationPreview()
            precondition(model.showsOriginalTranslation)
            let original = NSBitmapImageRep(cgImage: model.imageForExport()!)
            precondition(original.colorAt(x: 55, y: 45)!.redComponent > 0.9 && model.annotations.count == 1)
            model.confirmCopy()
            precondition(captures == 1)
            model.selectionRect.origin.x += 1
            precondition(model.translationSource == nil && model.translatedSelection == nil && model.canExportSelection)
            model.confirmImageTranslation()
            model.reset()
            precondition(model.translationSource == nil && !model.showsTranslationControls)
            print("PASS: translation stays in selection, preserves annotations/Retina coordinates, blocks incomplete exports, switches original and invalidates stale crops")
        }
    }

    static func solidImage(width: Int, height: Int, color: NSColor) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
