import AppKit
import Foundation

/// Synthetic safety boundaries only. Distributed multicolor one-level redraws
/// deliberately remain unsupported until real capture evidence can distinguish
/// them from independent, clipped, low-contrast movement.
@main
struct LongCaptureStationaryQuantizationChecks {
    static let points = [(24, 70), (96, 150), (180, 230), (264, 310), (336, 390),
                         (48, 90), (120, 170), (204, 250), (288, 330)]

    @MainActor static func main() {
        var failures = 0, assertions = 0
        func check(_ condition: Bool, _ label: String) {
            assertions += 1
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            if !condition { failures += 1 }
        }
        func rejected(_ first: CGImage, _ next: CGImage, _ label: String) {
            let matcher = LongCaptureOverlapMatcher()
            check(!matcher.isStationaryRedraw(previous: first, current: next), label)
        }
        func incomplete(_ first: CGImage, _ next: CGImage, _ label: String) {
            let accumulator = LongCaptureFrameAccumulator()
            _ = accumulator.process(frame: .init(image: first, timestamp: 0))
            let progress = accumulator.process(frame: .init(image: next, timestamp: 0.1))
            check(progress?.warning != nil && progress?.acceptedFrameCount == 1 &&
                  progress?.appendedPixelHeight == first.height,
                  "\(label) does not advance the committed document")
            do {
                _ = try accumulator.renderFinalImage()
                check(false, "\(label) cannot silently export only the old frontier")
            } catch LongCaptureError.incompleteCapture {
                check(true, "\(label) cannot silently export only the old frontier")
            } catch {
                check(false, "\(label) reports incompleteCapture rather than another error")
            }
        }

        let base = document(seed: 13)
        let redraw = sparseMultiColorRedraw(base)
        rejected(base, redraw, "unsupported distributed multicolor one-level redraw remains conservative")
        incomplete(base, redraw, "unsupported distributed redraw")

        // Nine one-pixel clipped panes expose rows of independently scrolling
        // low-contrast content. Each has the same first row as its background;
        // row 1 differs by R+1 and sometimes G+1. Advancing these panes by one
        // pixel yields exactly the same two frames as the synthetic repaint.
        let panesBefore = clippedPaneFrame(background: base, offset: 0)
        let panesAfter = clippedPaneFrame(background: base, offset: 1)
        check(pixels(panesBefore) == pixels(base) && pixels(panesAfter) == pixels(redraw),
              "a genuine 1px clipped-pane advance is pixel-identical to the multicolor repaint pair")
        rejected(panesBefore, panesAfter,
                 "same-column unique static anchors cannot authorize ambiguous clipped-pane movement")

        let pointBefore = movingPointFrame(background: base, pointY: 200, pointX: 120)
        let pointAfter = movingPointFrame(background: base, pointY: 201, pointX: 120)
        rejected(pointBefore, pointAfter,
                 "a sparse real 1px movement with same-column static anchors is not stationary")
        incomplete(pointBefore, pointAfter, "sparse real 1px movement")

        for x in [160, 180, 360] {
            let sidebar = sidebarFrame()
            rejected(movingPointFrame(background: sidebar, pointY: 200, pointX: x),
                     movingPointFrame(background: sidebar, pointY: 201, pointX: x),
                     "fixed sidebar cannot witness a moving pane at x=\(x)")
        }

        let periodicBefore = periodic(offset: 0)
        let periodicAfter = periodic(offset: 24)
        rejected(periodicBefore, periodicAfter,
                 "periodic rows with one-level distinguishing markers remain motion-ambiguous")
        incomplete(periodicBefore, periodicAfter, "periodic one-level-marker movement")
        rejected(periodicBefore, sparseMultiColorRedraw(periodicBefore),
                 "distributed redraw over periodic body remains unsupported")

        let empty = document(seed: 0, blank: true)
        rejected(empty, sparseMultiColorRedraw(empty),
                 "a blank body provides no stationary structure for distributed changes")
        rejected(base, change(base, at: [(120, 200)], deltas: [0, 0, 0, -1]),
                 "a local one-level alpha change is outside compositor RGB quantization")
        rejected(base, change(base, at: points, deltas: [0, 0, 0, -1]),
                 "distributed one-level alpha changes remain unsupported")
        rejected(base, change(base, at: points, deltas: [12, 8, 0, 0]),
                 "multicolor changes larger than one level remain unsupported")

        for (label, deltas) in [("negative", [-1, 0, 0, 0]),
                                ("opposite RGB signs", [1, -1, 0, 0])] {
            rejected(base, change(base, at: points, deltas: deltas),
                     "distributed \(label) changes do not gain a wider edit budget")
        }

        let stripe = flatStripe(base)
        let stripePoints = (200..<204).flatMap { y in (24..<456).map { ($0, y) } }
        let stripeRedraw = change(stripe, at: stripePoints, deltas: [1, 0, 0, 0])
        let knownMatcher = LongCaptureOverlapMatcher()
        check(knownMatcher.isStationaryRedraw(previous: stripe, current: stripeRedraw),
              "the existing uniform flat-color RGB quantization path still accepts its narrow evidence")
        let known = LongCaptureFrameAccumulator()
        _ = known.process(frame: .init(image: stripe, timestamp: 0))
        let knownProgress = known.process(frame: .init(image: stripeRedraw, timestamp: 0.1))
        check(knownProgress?.warning == nil && knownProgress?.acceptedFrameCount == 1 &&
              knownProgress?.appendedPixelHeight == stripe.height,
              "supported uniform redraw preserves total height and accepted frame count")
        check((try? known.renderFinalImage()) != nil,
              "supported uniform redraw remains exportable")

        print("RESULT: \(assertions - failures)/\(assertions) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    static func image(_ pixels: [UInt8], width: Int = 480, height: Int = 480) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pixels(_ image: CGImage) -> [UInt8] {
        // Exact fixture bytes: drawing through CGContext could color-convert or
        // invert the row orientation, changing the intended ±1 evidence.
        Array(image.dataProvider!.data! as Data)
    }

    static func document(seed: Int, blank: Bool = false) -> CGImage {
        let width = 480, height = 480
        var bytes = [UInt8](repeating: 245, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            var bits = UInt32(truncatingIfNeeded: y * width + x + seed * 17)
            bits ^= bits >> 16; bits &*= 0x7feb352d; bits ^= bits >> 15
            let value: UInt8 = blank ? 245 : UInt8(32 + bits % 190)
            let i = (y * width + x) * 4
            bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = 255
        }}
        return image(bytes)
    }

    static func change(_ source: CGImage, at points: [(Int, Int)], deltas: [Int]) -> CGImage {
        var bytes = pixels(source)
        for (x, y) in points { for channel in 0..<4 {
            let i = (y * source.width + x) * 4 + channel
            bytes[i] = UInt8(clamping: Int(bytes[i]) + deltas[channel])
        }}
        return image(bytes, width: source.width, height: source.height)
    }

    static func sparseMultiColorRedraw(_ source: CGImage) -> CGImage {
        var current = source
        for (index, point) in points.enumerated() {
            current = change(current, at: [point], deltas: [1, index.isMultiple(of: 2) ? 1 : 0, 0, 0])
        }
        return current
    }

    static func clippedPaneFrame(background: CGImage, offset: Int) -> CGImage {
        var bytes = pixels(background)
        // Each pane is a 1x1 viewport onto a 1x2 document. Only the selected
        // document row is composited; the document's other row is clipped.
        for (index, point) in points.enumerated() {
            let i = (point.1 * background.width + point.0) * 4
            let row0 = Array(bytes[i..<(i + 4)])
            let row1 = [row0[0] + 1, row0[1] + (index.isMultiple(of: 2) ? 1 : 0), row0[2], row0[3]]
            let rows = [row0, row1]
            for channel in 0..<4 { bytes[i + channel] = rows[offset][channel] }
        }
        return image(bytes)
    }

    static func movingPointFrame(background: CGImage, pointY: Int, pointX: Int) -> CGImage {
        var bytes = pixels(background)
        for y in 190..<210 { for channel in 0..<3 {
            bytes[(y * background.width + pointX) * 4 + channel] = 245
        }}
        for channel in 0..<3 { bytes[(pointY * background.width + pointX) * 4 + channel] = 244 }
        return image(bytes)
    }

    static func sidebarFrame() -> CGImage {
        var bytes = pixels(document(seed: 0, blank: true))
        let rich = pixels(document(seed: 19))
        for y in 0..<480 { for x in 0..<160 { for channel in 0..<4 {
            let i = (y * 480 + x) * 4 + channel
            bytes[i] = rich[i]
        }}}
        return image(bytes)
    }

    static func periodic(offset: Int) -> CGImage {
        var bytes = pixels(document(seed: 0, blank: true))
        for y in 0..<480 { for x in 40..<350 {
            let value: UInt8 = ((y + offset) % 24 < 8) ? 80 : 245
            for channel in 0..<3 { bytes[(y * 480 + x) * 4 + channel] = value }
        }}
        for worldY in [50, 146, 242, 338, 434] {
            let y = worldY - offset
            if (0..<480).contains(y) {
                for channel in 0..<3 { bytes[(y * 480 + 110) * 4 + channel] = 244 }
            }
        }
        return image(bytes)
    }

    static func flatStripe(_ source: CGImage) -> CGImage {
        var bytes = pixels(source)
        for y in 200..<204 { for x in 24..<456 {
            let i = (y * source.width + x) * 4
            bytes[i] = 100; bytes[i + 1] = 110; bytes[i + 2] = 120
        }}
        return image(bytes)
    }
}
