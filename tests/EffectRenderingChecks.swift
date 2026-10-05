import AppKit
import SwiftUI

@main
struct EffectRenderingChecks {
    static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let c = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let width = 240, height = 160
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in stride(from: 0, to: width, by: 2) {
            c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        let source = c.makeImage()!, size = CGSize(width: width, height: height)
        var mosaic = Annotation(type: .mosaic, color: .red)
        mosaic.startPoint = CGPoint(x: 32, y: 32); mosaic.endPoint = CGPoint(x: 160, y: 128)
        mosaic.mosaicBlockSize = 16
        let result = AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: [mosaic])!
        let p = pixels(result), input = pixels(source)
        let middle = (80 * width + 80) * 4
        precondition((125...130).contains(Int(p[middle])), "blocks must average stripes rather than sample black or white")
        precondition(p[0..<4].elementsEqual(input[0..<4]), "outside mask stays unchanged")
        var resized = mosaic; resized.startPoint.x = 35; resized.endPoint.x = 175
        let q = pixels(AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: [resized])!)
        precondition(p[middle..<(middle + 4)].elementsEqual(q[middle..<(middle + 4)]), "resizing must keep grid stable")
        print("PASS: block averages, fixed grid, unaffected exterior")

        var blur = Annotation(type: .blur, color: .red)
        blur.points = [CGPoint(x: 50, y: 80), CGPoint(x: 180, y: 80)]
        blur.startPoint = blur.points[0]; blur.endPoint = blur.points[1]
        blur.lineWidth = 36; blur.blurRadius = 12
        let blurred = AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: [blur])!
        let b = pixels(blurred)
        precondition((120...200).contains(Int(b[middle])), "blur must soften pixels without a black tint")
        precondition(b[0..<4].elementsEqual(input[0..<4]))
        let twice = pixels(AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: [blur, blur])!)
        precondition(abs(Int(twice[middle]) - Int(b[middle])) <= 1, "equal-strength overlapping strokes must not repeatedly blur")
        precondition(b[(40 * width + 100) * 4] == input[(40 * width + 100) * 4], "brush width stays separate from blur radius")
        print("PASS: actual blur, width/strength separation, overlap stability")

        let crop = CGRect(x: 32, y: 32, width: 144, height: 96)
        let tile = AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: [mosaic], outputRect: crop)!
        precondition(pixels(tile) == pixels(result.cropping(to: crop)!))
        precondition(tile.width == 144 && tile.height == 96)
        print("PASS: ROI preview matches full-resolution output")

        let service = CaptureService.shared
        let exported = service.composite(image: NSImage(cgImage: source, size: size), annotations: [mosaic]).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        precondition(pixels(exported) == pixels(result), "actual export must use the same pixels")
        let offset = CGPoint(x: 25, y: 19)
        var global = mosaic
        global.startPoint.x += offset.x; global.startPoint.y += offset.y
        global.endPoint.x += offset.x; global.endPoint.y += offset.y
        let shifted = service.compositeCropped(image: NSImage(cgImage: source, size: size), annotations: [global], cropRect: CGRect(origin: offset, size: size)).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        precondition(pixels(shifted) == pixels(result), "crop offsets must not change effect coordinates")
        let retinaSize = CGSize(width: width / 2, height: height / 2)
        var retina = mosaic; retina.startPoint = CGPoint(x: 16, y: 16); retina.endPoint = CGPoint(x: 80, y: 64); retina.mosaicBlockSize = 8
        precondition(pixels(AnnotationEffectRenderer.render(source: source, logicalSize: retinaSize, annotations: [retina])!) == pixels(result))
        print("PASS: production export, nonzero crop origin and Retina scale")

        let tall = CGContext(data: nil, width: 160, height: 6000, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        tall.setFillColor(CGColor(gray: 1, alpha: 1)); tall.fill(CGRect(x: 0, y: 0, width: 160, height: 6000))
        var bottom = blur; bottom.points = [CGPoint(x: 20, y: 5900), CGPoint(x: 100, y: 5900)]; bottom.startPoint = bottom.points[0]; bottom.endPoint = bottom.points[1]
        let longPreview = AnnotationEffectRenderer.render(source: tall.makeImage()!, logicalSize: CGSize(width: 160, height: 6000), annotations: [bottom], outputRect: CGRect(x: 0, y: 70, width: 140, height: 60))!
        precondition(longPreview.width == 140 && longPreview.height == 60)
        print("PASS: long-image preview allocates only requested output region")

        let translucent = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        translucent.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); translucent.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        var a = mosaic; a.startPoint = CGPoint(x: 8, y: 8); a.endPoint = CGPoint(x: 32, y: 32)
        let transparentResult = pixels(AnnotationEffectRenderer.render(source: translucent.makeImage()!, logicalSize: CGSize(width: 40, height: 40), annotations: [a])!)
        precondition((126...130).contains(Int(transparentResult[(20 * 40 + 20) * 4 + 3])), "effects must preserve alpha")
        print("PASS: premultiplied transparency")

        let suite = "LibreShot.Effects.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let m = OverlayViewModel(settings: SettingsService(defaults: defaults))
        m.selectionRect = CGRect(origin: .zero, size: size); m.state = .editing
        m.updatePreviewImage(source); m.selectTool(.blur)
        m.setEffectValue(60, parameter: "width"); m.setEffectValue(8, parameter: "radius")
        m.startDrawing(at: CGPoint(x: 40, y: 80)); m.updateDrawing(to: CGPoint(x: 180, y: 80)); m.endDrawing()
        precondition(m.annotations[0].lineWidth == 60 && m.annotations[0].blurRadius == 8)
        m.selectedAnnotationID = m.annotations[0].id
        m.setEffectValue(20, parameter: "radius"); precondition(m.annotations[0].blurRadius == 20)
        m.undoLastAnnotation(); precondition(m.annotations[0].blurRadius == 8 && m.selectedBlurRadius == 8)
        let deadline = Date().addingTimeInterval(4)
        while m.effectPreview == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        precondition(m.effectPreview != nil, "live effect must finish")
        let rect = m.effectPreviewRect
        let full = AnnotationEffectRenderer.render(source: source, logicalSize: size, annotations: m.annotations)!
        precondition(pixels(m.effectPreview!) == pixels(full.cropping(to: rect)!))
        m.reset()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(m.effectPreview == nil && m.previewImage == nil, "stale rendering must not restore a closed session")
        print("PASS: production gestures, parameter editing/undo, async preview and session cleanup")

        let output = URL(fileURLWithPath: "/tmp/libreshot-effects-qa")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, image) in [("source", source), ("mosaic", result), ("blur", blurred)] {
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
        }
        print("PASS: visual samples exported to /tmp/libreshot-effects-qa")
    }
}
