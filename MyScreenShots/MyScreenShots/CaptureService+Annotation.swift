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
        let baseImage = applyAnnotationEffects(image: image, annotations: annotations, cropRect: nil)
        // Create a new image with the same size
        let newImage = NSImage(size: baseImage.size)
        
        newImage.lockFocus()
        // 1. Draw the original image
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size),
                   from: NSRect(origin: .zero, size: baseImage.size),
                   operation: .copy, 
                   fraction: 1.0)
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return image
        }
        
        // 2. Setup Coordinate System for Annotations
        context.saveGState()
        
        // Calculate scale factor (Retina pixels vs Logical points)
        let scaleX: CGFloat
        let scaleY: CGFloat
        
        // Find the target screen
        var targetScreen: NSScreen?
        if let id = displayID {
            targetScreen = NSScreen.screens.first { 
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id 
            }
        }
        // Fallback to main if not found or id is nil
        if targetScreen == nil {
            targetScreen = NSScreen.main
        }
        
        if let screen = targetScreen {
            scaleX = baseImage.size.width / screen.frame.width
            scaleY = baseImage.size.height / screen.frame.height
        } else {
            scaleX = 1.0
            scaleY = 1.0
        }
        
        // Transform:
        // 1. Scale up to match pixels
        context.scaleBy(x: scaleX, y: scaleY)
        
        // 2. Flip vertically: Move origin to top-left
        let heightInPoints = baseImage.size.height / scaleY
        context.translateBy(x: 0, y: heightInPoints)
        context.scaleBy(x: 1.0, y: -1.0)
        
        // 3. Draw Annotations
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
                // Create CGRect manually to avoid ambiguity/extension issues
                let x = min(annotation.startPoint.x, annotation.endPoint.x)
                let y = min(annotation.startPoint.y, annotation.endPoint.y)
                let width = abs(annotation.endPoint.x - annotation.startPoint.x)
                let height = abs(annotation.endPoint.y - annotation.startPoint.y)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                path.addRect(rect)
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
                let rect = CGRect(x: x, y: y, width: width, height: height)
                path.addEllipse(in: rect)
            case .mosaic, .blur:
                continue
            case .text:
                // Text is drawn separately below via string drawing
                continue
            }
            
            context.addPath(path)
            context.strokePath()
        }
        
        
        context.restoreGState()
        
        // 4. Draw Text Annotations in standard coordinate system
        // We restored GState, so we are back to NSImage default (y-up, origin bottom-left).
        // need to convert annotation coordinates (y-down, origin top-left) to this system.
        
        for annotation in annotations where annotation.type == .text {
            let text = annotation.text as NSString
            let finalFontSize = annotation.fontSize * scaleX
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: finalFontSize),
                .foregroundColor: NSColor(annotation.color)
            ]
            let size = text.size(withAttributes: attributes)
            
            // Calculate position
            // Annotation y is from top.
            // Image y is from bottom.
            // We want top of text to be at annotation.y
            // So bottom of text should be at: (ImageHeight - (annotation.y * scale) - textHeight)
            
            let drawPoint = CGPoint(
                x: annotation.startPoint.x * scaleX,
                y: baseImage.size.height - (annotation.startPoint.y * scaleY) - size.height
            )
            
            text.draw(at: drawPoint, withAttributes: attributes)
        }
        
        // Context state is already restored to base
        newImage.unlockFocus()
        
        return newImage
    }

    func compositeCropped(image: NSImage, annotations: [Annotation], cropRect: CGRect, displayID: CGDirectDisplayID? = nil) -> NSImage {
        _ = displayID
        if annotations.isEmpty { return image }
        let baseImage = applyAnnotationEffects(image: image, annotations: annotations, cropRect: cropRect)
        let newImage = NSImage(size: baseImage.size)
        newImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size),
                   from: NSRect(origin: .zero, size: baseImage.size),
                   operation: .copy,
                   fraction: 1.0)

        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return image
        }

        context.saveGState()
        context.translateBy(x: 0, y: image.size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        for annotation in annotations {
            if !annotationIntersectsCrop(annotation, cropRect: cropRect) { continue }
            context.setStrokeColor(NSColor(annotation.color).cgColor)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let path = CGMutablePath()
            switch annotation.type {
            case .pen:
                let localPoints = annotation.points.map { CGPoint(x: $0.x - cropRect.origin.x, y: $0.y - cropRect.origin.y) }
                if let first = localPoints.first {
                    path.move(to: first)
                    for point in localPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
            case .rectangle:
                let start = CGPoint(x: annotation.startPoint.x - cropRect.origin.x, y: annotation.startPoint.y - cropRect.origin.y)
                let end = CGPoint(x: annotation.endPoint.x - cropRect.origin.x, y: annotation.endPoint.y - cropRect.origin.y)
                let x = min(start.x, end.x)
                let y = min(start.y, end.y)
                let width = abs(end.x - start.x)
                let height = abs(end.y - start.y)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                path.addRect(rect)
            case .arrow:
                let start = CGPoint(x: annotation.startPoint.x - cropRect.origin.x, y: annotation.startPoint.y - cropRect.origin.y)
                let end = CGPoint(x: annotation.endPoint.x - cropRect.origin.x, y: annotation.endPoint.y - cropRect.origin.y)
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
                let start = CGPoint(x: annotation.startPoint.x - cropRect.origin.x, y: annotation.startPoint.y - cropRect.origin.y)
                let end = CGPoint(x: annotation.endPoint.x - cropRect.origin.x, y: annotation.endPoint.y - cropRect.origin.y)
                let x = min(start.x, end.x)
                let y = min(start.y, end.y)
                let width = abs(end.x - start.x)
                let height = abs(end.y - start.y)
                let rect = CGRect(x: x, y: y, width: width, height: height)
                path.addEllipse(in: rect)
            case .mosaic, .blur:
                continue
            case .text:
                continue
            }

            context.addPath(path)
            context.strokePath()
        }

        context.restoreGState()

        for annotation in annotations where annotation.type == .text {
            if !annotationIntersectsCrop(annotation, cropRect: cropRect) { continue }
            let text = annotation.text as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: annotation.fontSize),
                .foregroundColor: NSColor(annotation.color)
            ]
            let size = text.size(withAttributes: attributes)
            let localX = annotation.startPoint.x - cropRect.origin.x
            let localY = annotation.startPoint.y - cropRect.origin.y
            let drawPoint = CGPoint(
                x: localX,
                y: baseImage.size.height - localY - size.height
            )
            text.draw(at: drawPoint, withAttributes: attributes)
        }

        newImage.unlockFocus()
        return newImage
    }

    private func annotationIntersectsCrop(_ annotation: Annotation, cropRect: CGRect) -> Bool {
        switch annotation.type {
        case .rectangle, .ellipse, .text:
            let rect: CGRect
            if annotation.type == .text {
                let width = CGFloat(annotation.text.count) * annotation.fontSize * 0.6
                let height = annotation.fontSize * 1.5
                rect = CGRect(x: annotation.startPoint.x, y: annotation.startPoint.y, width: width, height: height)
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

    private func applyAnnotationEffects(image: NSImage, annotations: [Annotation], cropRect: CGRect?) -> NSImage {
        let hasEffects = annotations.contains { $0.type == .mosaic || $0.type == .blur }
        if !hasEffects { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height
        var currentImage = CIImage(cgImage: cgImage)
        let fullExtent = currentImage.extent
        // Use shared context to save memory
        let context = self.context
        for annotation in annotations {
            if annotation.type != .mosaic && annotation.type != .blur { continue }
            var localPoints: [CGPoint]
            var localStart: CGPoint
            var localEnd: CGPoint
            if let crop = cropRect {
                localPoints = annotation.points.map { CGPoint(x: $0.x - crop.minX, y: $0.y - crop.minY) }
                localStart = CGPoint(x: annotation.startPoint.x - crop.minX, y: annotation.startPoint.y - crop.minY)
                localEnd = CGPoint(x: annotation.endPoint.x - crop.minX, y: annotation.endPoint.y - crop.minY)
            } else {
                localPoints = annotation.points
                localStart = annotation.startPoint
                localEnd = annotation.endPoint
            }
            if let crop = cropRect {
                let clampedPoints = localPoints.map { CGPoint(x: min(max($0.x, 0), crop.width), y: min(max($0.y, 0), crop.height)) }
                let clampedStart = CGPoint(x: min(max(localStart.x, 0), crop.width), y: min(max(localStart.y, 0), crop.height))
                let clampedEnd = CGPoint(x: min(max(localEnd.x, 0), crop.width), y: min(max(localEnd.y, 0), crop.height))
                localPoints = clampedPoints
                localStart = clampedStart
                localEnd = clampedEnd
            }
            let pointsForBounds = localPoints.isEmpty ? [localStart, localEnd] : localPoints
            let xs = pointsForBounds.map { $0.x }
            let ys = pointsForBounds.map { $0.y }
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }
            let boundsRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let effectRect: CGRect
            if annotation.type == .mosaic {
                effectRect = boundsRect
            } else {
                let half = annotation.lineWidth / 2
                effectRect = boundsRect.insetBy(dx: -half, dy: -half)
            }
            if effectRect.width <= 1 || effectRect.height <= 1 { continue }
            let pixelWidth = effectRect.width * scaleX
            let pixelHeight = effectRect.height * scaleY
            let pixelX = effectRect.minX * scaleX
            let pixelY = fullExtent.height - (effectRect.maxY * scaleY)
            let pixelRect = CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight).intersection(fullExtent)
            if pixelRect.isEmpty { continue }
            let strokeScale = max(annotation.lineWidth * max(scaleX, scaleY), 1)
            let filtered: CIImage
            if annotation.type == .mosaic {
                let blockSize = max(annotation.lineWidth * 0.8, 10)
                let pixelBlockSize = blockSize * max(scaleX, scaleY)
                let filter = CIFilter.pixellate()
                filter.inputImage = currentImage
                filter.scale = Float(max(pixelBlockSize, 8))
                filter.center = CGPoint(x: pixelRect.midX, y: pixelRect.midY)
                filtered = filter.outputImage?.cropped(to: fullExtent) ?? currentImage
            } else {
                let filter = CIFilter.gaussianBlur()
                filter.inputImage = currentImage.clampedToExtent()
                filter.radius = Float(max(strokeScale * 4.2, 36))
                filtered = filter.outputImage?.cropped(to: fullExtent) ?? currentImage
            }
            let mask: CIImage
            if annotation.type == .mosaic {
                mask = makeEffectMask(extent: fullExtent, rect: pixelRect)
            } else if pointsForBounds.count >= 2 {
                mask = makeBrushMask(extent: fullExtent, points: pointsForBounds, lineWidth: annotation.lineWidth, scaleX: scaleX, scaleY: scaleY)
            } else {
                mask = makeEffectMask(extent: fullExtent, rect: pixelRect)
            }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = filtered
            blend.backgroundImage = currentImage
            blend.maskImage = mask
            if let output = blend.outputImage?.cropped(to: fullExtent) {
                currentImage = output
            }
        }
        guard let outputCG = context.createCGImage(currentImage, from: fullExtent) else { return image }
        return NSImage(cgImage: outputCG, size: image.size)
    }

    private func makeEffectMask(extent: CGRect, rect: CGRect) -> CIImage {
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        let highlight = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: rect)
        return highlight.composited(over: base)
    }

    private func makeBrushMask(extent: CGRect, points: [CGPoint], lineWidth: CGFloat, scaleX: CGFloat, scaleY: CGFloat) -> CIImage {
        let width = Int(extent.width)
        let height = Int(extent.height)
        if width <= 0 || height <= 0 {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let cgContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        }
        cgContext.setFillColor(gray: 0, alpha: 1)
        cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        cgContext.setStrokeColor(gray: 1, alpha: 1)
        cgContext.setLineWidth(max(lineWidth * max(scaleX, scaleY), 1))
        cgContext.setLineCap(.round)
        cgContext.setLineJoin(.round)
        let heightPixels = extent.height
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: CGPoint(x: first.x * scaleX, y: heightPixels - first.y * scaleY))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * scaleX, y: heightPixels - point.y * scaleY))
            }
        }
        cgContext.addPath(path)
        cgContext.strokePath()
        guard let maskImage = cgContext.makeImage() else {
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        }
        return CIImage(cgImage: maskImage).cropped(to: extent)
    }
}
