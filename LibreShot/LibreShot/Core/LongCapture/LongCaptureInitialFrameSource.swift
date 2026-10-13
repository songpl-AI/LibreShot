import AppKit

/// Copy only the frozen selection, retaining its original pixel layout/profile.
/// A CGImage crop alone may keep the entire display preview's storage alive.
nonisolated enum LongCaptureInitialFrameSource {
    static func selection(from image: CGImage, region: LongCaptureRegion,
                          maximumBytes: Int = 64 * 1024 * 1024) -> CGImage? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.decode == nil, maximumBytes > 0, let colorSpace = image.colorSpace,
              let rect = LongCaptureImageSampling.pixelRect(width: image.width, height: image.height,
                  screenRect: region.screenRect, screenFrame: region.screenFrame),
              let width = Int(exactly: rect.width), let height = Int(exactly: rect.height),
              width > 0, height > 0, width <= maximumBytes / 4,
              height <= maximumBytes / (width * 4),
              image.width <= Int.max / 4, image.bytesPerRow >= image.width * 4,
              image.height <= Int.max / image.bytesPerRow,
              let data = image.dataProvider?.data,
              CFDataGetLength(data) >= image.bytesPerRow * image.height,
              let source = CFDataGetBytePtr(data) else { return nil }
        defer { withExtendedLifetime(data) {} }
        let rowBytes = width * 4
        let x = Int(rect.minX), y = Int(rect.minY)
        var pixels = Data(count: rowBytes * height)
        pixels.withUnsafeMutableBytes { destination in
            guard let base = destination.baseAddress else { return }
            for row in 0..<height {
                memcpy(base.advanced(by: row * rowBytes),
                       source + (y + row) * image.bytesPerRow + x * 4, rowBytes)
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: image.bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: image.renderingIntent)
    }
}
