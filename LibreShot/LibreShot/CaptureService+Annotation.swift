import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

extension CaptureService {
    /// Composites annotations onto the provided image.
    /// - Parameters:
    ///   - image: The background image (full screen).
    ///   - annotations: List of annotations to draw.
    /// - Returns: A new NSImage with annotations drawn.
    func composite(image: NSImage, annotations: [Annotation], displayID: CGDirectDisplayID? = nil) -> NSImage {
        _ = displayID
        let baseImage = applyAnnotationEffects(image: image, annotations: annotations, cropRect: nil)
        return renderCompositeImage(baseImage: baseImage, annotations: annotations)
    }

    func compositeCropped(image: NSImage, annotations: [Annotation], cropRect: CGRect, displayID: CGDirectDisplayID? = nil) -> NSImage {
        _ = displayID
        if annotations.isEmpty { return image }
        let baseImage = applyAnnotationEffects(image: image, annotations: annotations, cropRect: cropRect)
        let localAnnotations = annotations.compactMap { annotation -> Annotation? in
            if !annotationIntersectsCrop(annotation, cropRect: cropRect) {
                return nil
            }
            var localAnnotation = annotation
            localAnnotation.startPoint = CGPoint(x: annotation.startPoint.x - cropRect.origin.x, y: annotation.startPoint.y - cropRect.origin.y)
            localAnnotation.endPoint = CGPoint(x: annotation.endPoint.x - cropRect.origin.x, y: annotation.endPoint.y - cropRect.origin.y)
            localAnnotation.points = annotation.points.map { CGPoint(x: $0.x - cropRect.origin.x, y: $0.y - cropRect.origin.y) }
            return localAnnotation
        }
        
        return renderCompositeImage(baseImage: baseImage, annotations: localAnnotations)
    }

    private func annotationIntersectsCrop(_ annotation: Annotation, cropRect: CGRect) -> Bool {
        switch annotation.type {
        case .rectangle, .ellipse, .text, .number:
            let rect: CGRect
            if annotation.type == .text {
                rect = annotation.textBoundingRect
            } else if annotation.type == .number {
                let radius = annotation.numberRadius
                rect = CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2)
            } else {
                let x = min(annotation.startPoint.x, annotation.endPoint.x)
                let y = min(annotation.startPoint.y, annotation.endPoint.y)
                let width = abs(annotation.endPoint.x - annotation.startPoint.x)
                let height = abs(annotation.endPoint.y - annotation.startPoint.y)
                rect = CGRect(x: x, y: y, width: width, height: height)
            }
            return rect.intersects(cropRect)
        case .mosaic, .blur, .pen, .arrow:
            let xs = annotation.points.map { $0.x } + [annotation.startPoint.x, annotation.endPoint.x]
            let ys = annotation.points.map { $0.y } + [annotation.startPoint.y, annotation.endPoint.y]
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return false }
            let padding = (annotation.type == .mosaic || annotation.type == .blur) ? annotation.lineWidth / 2 : 0
            let rect = CGRect(x: minX - padding, y: minY - padding, width: maxX - minX + padding * 2, height: maxY - minY + padding * 2)
            return rect.intersects(cropRect)
        }
    }

    private func renderCompositeImage(baseImage: NSImage, annotations: [Annotation]) -> NSImage {
        guard let bitmapRep = bitmapRep(from: baseImage, opaque: false),
              let cgImage = bitmapRep.cgImage else {
            return baseImage
        }
        
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let logicalSize = baseImage.size
        let scaleX = logicalSize.width > 0 ? pixelSize.width / logicalSize.width : 1
        let scaleY = logicalSize.height > 0 ? pixelSize.height / logicalSize.height : 1
        
        guard let bitmapContext = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return baseImage
        }
        
        bitmapContext.interpolationQuality = .high
        bitmapContext.draw(cgImage, in: CGRect(origin: .zero, size: pixelSize))
        bitmapContext.saveGState()
        bitmapContext.scaleBy(x: scaleX, y: scaleY)
        bitmapContext.translateBy(x: 0, y: logicalSize.height)
        bitmapContext.scaleBy(x: 1, y: -1)
        drawVectorAnnotations(annotations, in: bitmapContext)
        bitmapContext.restoreGState()
        drawTextAnnotations(annotations, in: bitmapContext, scaleX: scaleX, scaleY: scaleY, logicalSize: logicalSize)
        
        guard let outputImage = bitmapContext.makeImage() else {
            return baseImage
        }
        
        return NSImage(cgImage: outputImage, size: logicalSize)
    }
    
    private func drawVectorAnnotations(_ annotations: [Annotation], in context: CGContext) {
        for annotation in annotations {
            context.setStrokeColor(NSColor(annotation.color).cgColor)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            let path = CGMutablePath()
            switch annotation.type {
            case .pen:
                if let first = annotation.points.first {
                    path.move(to: first)
                    for point in annotation.points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
            case .rectangle:
                let x = min(annotation.startPoint.x, annotation.endPoint.x)
                let y = min(annotation.startPoint.y, annotation.endPoint.y)
                let width = abs(annotation.endPoint.x - annotation.startPoint.x)
                let height = abs(annotation.endPoint.y - annotation.startPoint.y)
                path.addRect(CGRect(x: x, y: y, width: width, height: height))
            case .arrow:
                let start = annotation.startPoint
                let end = annotation.endPoint
                path.move(to: start)
                path.addLine(to: end)
                
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowLength: CGFloat = 15.0
                let arrowAngle: CGFloat = .pi / 6
                let p1 = CGPoint(
                    x: end.x - arrowLength * cos(angle - arrowAngle),
                    y: end.y - arrowLength * sin(angle - arrowAngle)
                )
                let p2 = CGPoint(
                    x: end.x - arrowLength * cos(angle + arrowAngle),
                    y: end.y - arrowLength * sin(angle + arrowAngle)
                )
                
                path.move(to: end)
                path.addLine(to: p1)
                path.move(to: end)
                path.addLine(to: p2)
            case .ellipse:
                let x = min(annotation.startPoint.x, annotation.endPoint.x)
                let y = min(annotation.startPoint.y, annotation.endPoint.y)
                let width = abs(annotation.endPoint.x - annotation.startPoint.x)
                let height = abs(annotation.endPoint.y - annotation.startPoint.y)
                path.addEllipse(in: CGRect(x: x, y: y, width: width, height: height))
            case .number:
                let radius = annotation.numberRadius
                path.addEllipse(in: CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2))
            case .mosaic, .blur, .text:
                continue
            }
            
            context.addPath(path)
            context.strokePath()
        }
    }
    
    private func drawTextAnnotations(_ annotations: [Annotation], in context: CGContext, scaleX: CGFloat, scaleY: CGFloat, logicalSize: CGSize) {
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        
        for annotation in annotations where annotation.type == .text || annotation.type == .number {
            let text = annotation.text as NSString
            let fontSize = annotation.fontSize * scaleY
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: annotation.type == .number ? .semibold : .regular),
                .foregroundColor: NSColor(annotation.color)
            ]
            let size = text.size(withAttributes: attributes)
            let drawPoint: CGPoint
            if annotation.type == .number {
                // 序号文字居中于圆圈
                drawPoint = CGPoint(
                    x: annotation.startPoint.x * scaleX - size.width / 2,
                    y: logicalSize.height * scaleY - (annotation.startPoint.y * scaleY) - size.height / 2
                )
            } else {
                drawPoint = CGPoint(
                    x: annotation.startPoint.x * scaleX,
                    y: logicalSize.height * scaleY - (annotation.startPoint.y * scaleY) - size.height
                )
            }
            text.draw(at: drawPoint, withAttributes: attributes)
        }
        
        NSGraphicsContext.restoreGraphicsState()
    }

    private func applyAnnotationEffects(image: NSImage, annotations: [Annotation], cropRect: CGRect?) -> NSImage {
        guard annotations.contains(where: { $0.type == .mosaic || $0.type == .blur }),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let offset = cropRect?.origin ?? .zero
        let local = annotations.map { annotation -> Annotation in
            var a = annotation
            a.startPoint.x -= offset.x; a.startPoint.y -= offset.y
            a.endPoint.x -= offset.x; a.endPoint.y -= offset.y
            a.points = a.points.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
            return a
        }
        guard let output = AnnotationEffectRenderer.render(source: source, logicalSize: image.size, annotations: local) else { return image }
        return NSImage(cgImage: output, size: image.size)
    }
}

/// The same native-pixel pipeline serves live previews and exported images.
/// Every effect samples the immutable source: overlapping equal-strength brush marks
/// do not repeatedly blur already blurred pixels.
enum AnnotationEffectRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(source: CGImage, logicalSize: CGSize, annotations: [Annotation], outputRect: CGRect? = nil) -> CGImage? {
        guard logicalSize.width > 0, logicalSize.height > 0 else { return nil }
        let sx = CGFloat(source.width) / logicalSize.width
        let sy = CGFloat(source.height) / logicalSize.height
        let scale = max(sx, sy)
        let original = CIImage(cgImage: source)
        let extent = original.extent
        var output = original
        for a in annotations where a.type == .mosaic || a.type == .blur {
            let r = a.selectionBounds
            let region = CGRect(x: r.minX * sx, y: extent.height - r.maxY * sy,
                                width: r.width * sx, height: r.height * sy).integral.intersection(extent)
            guard !region.isEmpty else { continue }
            let filtered: CIImage
            let mask: CIImage
            if a.type == .mosaic {
                let block = max(4, min(64, a.mosaicBlockSize)) * scale
                guard let pixels = averageBlocks(image: original, region: region, block: block, extent: extent) else { return nil }
                filtered = pixels
                // Exact geometry, not the integral processing bounds.
                let exact = CGRect(x: r.minX * sx, y: extent.height - r.maxY * sy, width: r.width * sx, height: r.height * sy)
                mask = CIImage(color: .white).cropped(to: exact)
            } else {
                let radius = max(2, min(32, a.blurRadius)) * scale
                // Enough neighbouring source pixels for the blur; clamp only at image edges.
                let sample = region.insetBy(dx: -ceil(radius * 3), dy: -ceil(radius * 3)).intersection(extent)
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = original.clampedToExtent().cropped(to: sample).clampedToExtent()
                blur.radius = Float(radius)
                guard let result = blur.outputImage,
                      let brush = brushMask(a, region: region, sx: sx, sy: sy, imageHeight: extent.height) else { return nil }
                filtered = result.cropped(to: region)
                mask = brush
            }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = filtered
            blend.backgroundImage = output
            blend.maskImage = mask.composited(over: CIImage(color: .black).cropped(to: extent))
            guard let result = blend.outputImage else { return nil }
            output = result.cropped(to: extent)
        }
        return context.createCGImage(output, from: outputRect?.intersection(extent) ?? extent)
    }

    /// Average every pixel in each globally aligned block, including source pixels
    /// outside the annotation. Resizing a rectangle never shifts its block grid.
    private static func averageBlocks(image: CIImage, region: CGRect, block: CGFloat, extent: CGRect) -> CIImage? {
        let step = max(1, Int(block.rounded()))
        let grid = CGRect(x: floor(region.minX / CGFloat(step)) * CGFloat(step),
                          y: floor(region.minY / CGFloat(step)) * CGFloat(step),
                          width: ceil(region.maxX / CGFloat(step)) * CGFloat(step) - floor(region.minX / CGFloat(step)) * CGFloat(step),
                          height: ceil(region.maxY / CGFloat(step)) * CGFloat(step) - floor(region.minY / CGFloat(step)) * CGFloat(step)).intersection(extent)
        guard let cg = context.createCGImage(image, from: grid) else { return nil }
        let w = cg.width, h = cg.height, row = w * 4
        var bytes = [UInt8](repeating: 0, count: row * h)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ok = bytes.withUnsafeMutableBytes { data -> Bool in
            guard let bitmap = CGContext(data: data.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                         bytesPerRow: row, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Align to image origin even when the topmost block is truncated.
            var y = 0
            while y < h {
                let globalTop = Int(grid.maxY) - y
                let bh = min(h - y, (globalTop - 1) % step + 1)
                var x = 0
                while x < w {
                    let bw = min(w - x, step - (Int(grid.minX) + x) % step)
                    var sum = [Int](repeating: 0, count: 4)
                    for yy in y..<(y + bh) { for xx in x..<(x + bw) {
                        let i = yy * row + xx * 4
                        for c in 0..<4 { sum[c] += Int(data[i + c]) }
                    } }
                    let n = bw * bh
                    let average = sum.map { UInt8(($0 + n / 2) / n) }
                    for yy in y..<(y + bh) { for xx in x..<(x + bw) {
                        let i = yy * row + xx * 4
                        for c in 0..<4 { data[i + c] = average[c] }
                    } }
                    x += bw
                }
                y += bh
            }
            return true
        }
        guard ok, let provider = CGDataProvider(data: Data(bytes) as CFData),
              let result = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: row,
                                   space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return CIImage(cgImage: result).transformed(by: CGAffineTransform(translationX: grid.minX, y: grid.minY)).cropped(to: region)
    }

    private static func brushMask(_ a: Annotation, region: CGRect, sx: CGFloat, sy: CGFloat, imageHeight: CGFloat) -> CIImage? {
        guard let bitmap = CGContext(data: nil, width: Int(region.width), height: Int(region.height), bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        bitmap.setFillColor(gray: 0, alpha: 1); bitmap.fill(CGRect(origin: .zero, size: region.size))
        bitmap.translateBy(x: -region.minX, y: -region.minY)
        bitmap.setStrokeColor(gray: 1, alpha: 1)
        bitmap.setFillColor(gray: 1, alpha: 1)
        bitmap.setLineWidth(a.lineWidth * max(sx, sy)); bitmap.setLineCap(.round); bitmap.setLineJoin(.round)
        if let first = a.points.first {
            bitmap.move(to: CGPoint(x: first.x * sx, y: imageHeight - first.y * sy))
            for p in a.points.dropFirst() { bitmap.addLine(to: CGPoint(x: p.x * sx, y: imageHeight - p.y * sy)) }
            if a.points.count == 1 {
                let radius = a.lineWidth * max(sx, sy) / 2
                bitmap.fillEllipse(in: CGRect(x: first.x * sx - radius, y: imageHeight - first.y * sy - radius, width: radius * 2, height: radius * 2))
            } else { bitmap.strokePath() }
        } else {
            let r = CGRect(from: a.startPoint, to: a.endPoint)
            bitmap.fill(CGRect(x: r.minX * sx, y: imageHeight - r.maxY * sy, width: r.width * sx, height: r.height * sy))
        }
        guard let cg = bitmap.makeImage() else { return nil }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: region.minX, y: region.minY))
    }
}
