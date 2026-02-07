import AppKit
import SwiftUI

extension CaptureService {
    /// Composites annotations onto the provided image.
    /// - Parameters:
    ///   - image: The background image (full screen).
    ///   - annotations: List of annotations to draw.
    /// - Returns: A new NSImage with annotations drawn.
    func composite(image: NSImage, annotations: [Annotation], displayID: CGDirectDisplayID? = nil) -> NSImage {
        // Create a new image with the same size
        let newImage = NSImage(size: image.size)
        
        newImage.lockFocus()
        // 1. Draw the original image
        image.draw(in: NSRect(origin: .zero, size: image.size), 
                   from: NSRect(origin: .zero, size: image.size), 
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
            scaleX = image.size.width / screen.frame.width
            scaleY = image.size.height / screen.frame.height
        } else {
            scaleX = 1.0
            scaleY = 1.0
        }
        
        // Transform:
        // 1. Scale up to match pixels
        context.scaleBy(x: scaleX, y: scaleY)
        
        // 2. Flip vertically: Move origin to top-left
        let heightInPoints = image.size.height / scaleY
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
                y: image.size.height - (annotation.startPoint.y * scaleY) - size.height
            )
            
            text.draw(at: drawPoint, withAttributes: attributes)
        }
        
        // Context state is already restored to base
        newImage.unlockFocus()
        
        return newImage
    }
}
