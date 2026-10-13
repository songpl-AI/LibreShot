import AppKit

/// The native-pixel selection expressed in ScreenCaptureKit's display-local,
/// top-left logical coordinates. Deriving it from the old integral pixel crop
/// keeps selection rounding and display-edge clipping consistent.
struct LongCaptureStreamGeometry {
    let sourceRect: CGRect
    let width: Int
    let height: Int

    init?(region: LongCaptureRegion, displayPixelWidth: Int, displayPixelHeight: Int) {
        let frame = region.screenFrame
        let selection = region.screenRect
        guard displayPixelWidth > 0, displayPixelHeight > 0,
              Self.isValid(frame), Self.isValid(selection) else { return nil }

        let scaleX = CGFloat(displayPixelWidth) / frame.size.width
        let scaleY = CGFloat(displayPixelHeight) / frame.size.height
        let pixelX = (selection.origin.x - frame.origin.x) * scaleX
        let pixelY = (frame.size.height - (selection.origin.y - frame.origin.y) - selection.size.height) * scaleY
        let pixelWidth = selection.size.width * scaleX
        let pixelHeight = selection.size.height * scaleY
        guard scaleX.isFinite, scaleY.isFinite, scaleX > 0, scaleY > 0,
              pixelX.isFinite, pixelY.isFinite, pixelWidth.isFinite, pixelHeight.isFinite,
              (pixelX + pixelWidth).isFinite, (pixelY + pixelHeight).isFinite,
              let pixels = LongCaptureImageSampling.pixelRect(
                width: displayPixelWidth, height: displayPixelHeight,
                screenRect: selection, screenFrame: frame
              ),
              let width = Int(exactly: pixels.size.width),
              let height = Int(exactly: pixels.size.height), width > 0, height > 0 else { return nil }

        let sourceRect = CGRect(x: pixels.origin.x / scaleX, y: pixels.origin.y / scaleY,
                                width: pixels.size.width / scaleX, height: pixels.size.height / scaleY)
        guard Self.isValid(sourceRect) else { return nil }
        self.sourceRect = sourceRect
        self.width = width
        self.height = height
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.size.width.isFinite && rect.size.height.isFinite &&
        rect.size.width > 0 && rect.size.height > 0 &&
        (rect.origin.x + rect.size.width).isFinite &&
        (rect.origin.y + rect.size.height).isFinite
    }
}
