import AppKit

enum LongCaptureImageSampling {
    nonisolated static func pixelRect(width: Int, height: Int, screenRect: CGRect, screenFrame: CGRect) -> CGRect? {
        guard width > 0, height > 0, screenFrame.width > 0, screenFrame.height > 0,
              screenFrame.origin.x.isFinite, screenFrame.origin.y.isFinite,
              screenFrame.width.isFinite, screenFrame.height.isFinite,
              screenRect.origin.x.isFinite, screenRect.origin.y.isFinite,
              screenRect.width.isFinite, screenRect.height.isFinite else { return nil }
        let scaleX = CGFloat(width) / screenFrame.width
        let scaleY = CGFloat(height) / screenFrame.height
        let x = (screenRect.origin.x - screenFrame.origin.x) * scaleX
        let relativeY = screenRect.origin.y - screenFrame.origin.y
        let y = (screenFrame.height - relativeY - screenRect.height) * scaleY
        let cropRect = CGRect(
            x: x,
            y: y,
            width: screenRect.width * scaleX,
            height: screenRect.height * scaleY
        )
        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        let finalRect = cropRect.integral.intersection(imageRect)
        guard !finalRect.isNull, !finalRect.isEmpty else { return nil }
        return finalRect
    }

    static func crop(image: CGImage, screenRect: CGRect, screenFrame: CGRect) -> CGImage? {
        guard let finalRect = pixelRect(width: image.width, height: image.height,
                                       screenRect: screenRect, screenFrame: screenFrame) else { return nil }
        guard let crop = image.cropping(to: finalRect),
              let context = CGContext(data: nil, width: crop.width, height: crop.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: crop.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return nil
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
    }
    
    static func scale(image: CGImage, to size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    
    static func grayscalePixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

