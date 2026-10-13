import AppKit
import Foundation

/// Offline coordinate and generated-pixel checks only. This does not start an
/// SCStream or prove the framework's native sourceRect capture behavior.
@main
struct LongCaptureStreamGeometryChecks {
    struct Case {
        let name: String
        let frame: CGRect
        let selection: CGRect
        let displayWidth: Int
        let displayHeight: Int
        let expectedPixels: CGRect
    }

    static func region(frame: CGRect, selection: CGRect) -> LongCaptureRegion {
        LongCaptureRegion(selectionRect: .zero, screenRect: selection,
                          screenFrame: frame, displayID: 0)
    }

    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= max(1, abs(a), abs(b)) * 1e-10
    }

    static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) &&
        near(a.size.width, b.size.width) && near(a.size.height, b.size.height)
    }

    static func generatedImage(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = UInt8((x * 13 + y * 7) % 251)
                pixels[index + 1] = UInt8((x * 5 + y * 19) % 251)
                pixels[index + 2] = UInt8((x * 17 + y * 3) % 251)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func canonicalBytes(_ image: CGImage) -> Data? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let made = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                            CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return made ? Data(pixels) : nil
    }

    static func main() {
        var results: [[String: Any]] = []
        func check(_ passed: Bool, _ name: String) {
            results.append(["name": name, "passed": passed])
            print("\(passed ? "PASS" : "FAIL"): \(name)")
        }
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let selection = CGRect(x: 100, y: 120, width: 300, height: 200)
        let cases = [
            Case(name: "1x", frame: frame, selection: selection, displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 400, width: 300, height: 200)),
            Case(name: "2x", frame: frame, selection: selection, displayWidth: 2560, displayHeight: 1440,
                 expectedPixels: CGRect(x: 200, y: 800, width: 600, height: 400)),
            Case(name: "fractional 1.5x expands edges", frame: frame,
                 selection: CGRect(x: 100.25, y: 120.25, width: 300.5, height: 199.5),
                 displayWidth: 1920, displayHeight: 1080,
                 expectedPixels: CGRect(x: 150, y: 600, width: 452, height: 300)),
            Case(name: "independent horizontal and vertical scales", frame: frame, selection: selection,
                 displayWidth: 1920, displayHeight: 1440,
                 expectedPixels: CGRect(x: 150, y: 800, width: 450, height: 400)),
            Case(name: "display left of primary", frame: frame.offsetBy(dx: -1280, dy: 0),
                 selection: selection.offsetBy(dx: -1280, dy: 0), displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 400, width: 300, height: 200)),
            Case(name: "display right of primary", frame: frame.offsetBy(dx: 1280, dy: 0),
                 selection: selection.offsetBy(dx: 1280, dy: 0), displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 400, width: 300, height: 200)),
            Case(name: "display above primary", frame: frame.offsetBy(dx: 0, dy: 720),
                 selection: selection.offsetBy(dx: 0, dy: 720), displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 400, width: 300, height: 200)),
            Case(name: "display below primary", frame: frame.offsetBy(dx: 0, dy: -720),
                 selection: selection.offsetBy(dx: 0, dy: -720), displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 400, width: 300, height: 200)),
            Case(name: "negative x with above-primary 2x display", frame: frame.offsetBy(dx: -1280, dy: 720),
                 selection: selection.offsetBy(dx: -1280, dy: 720), displayWidth: 2560, displayHeight: 1440,
                 expectedPixels: CGRect(x: 200, y: 800, width: 600, height: 400)),
            Case(name: "clamp left", frame: frame, selection: CGRect(x: -10, y: 120, width: 100, height: 200),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 0, y: 400, width: 90, height: 200)),
            Case(name: "clamp right", frame: frame, selection: CGRect(x: 1200, y: 120, width: 200, height: 200),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 1200, y: 400, width: 80, height: 200)),
            Case(name: "clamp top", frame: frame, selection: CGRect(x: 100, y: 650, width: 300, height: 100),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 0, width: 300, height: 70)),
            Case(name: "clamp bottom", frame: frame, selection: CGRect(x: 100, y: -50, width: 300, height: 100),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 670, width: 300, height: 50)),
            Case(name: "clamp all sides", frame: frame, selection: CGRect(x: -10, y: -10, width: 1300, height: 740),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 0, y: 0, width: 1280, height: 720)),
            Case(name: "tiny fractional selection retains one pixel", frame: frame,
                 selection: CGRect(x: 100.25, y: 120.25, width: 0.25, height: 0.25),
                 displayWidth: 1280, displayHeight: 720,
                 expectedPixels: CGRect(x: 100, y: 599, width: 1, height: 1))
        ]
        for item in cases {
            let region = region(frame: item.frame, selection: item.selection)
            guard let geometry = LongCaptureStreamGeometry(region: region, displayPixelWidth: item.displayWidth,
                                                           displayPixelHeight: item.displayHeight) else {
                check(false, "\(item.name) constructs valid geometry")
                continue
            }
            let old = LongCaptureImageSampling.pixelRect(width: item.displayWidth, height: item.displayHeight,
                                                        screenRect: item.selection, screenFrame: item.frame)
            let scaleX = CGFloat(item.displayWidth) / item.frame.width
            let scaleY = CGFloat(item.displayHeight) / item.frame.height
            let restored = CGRect(x: geometry.sourceRect.minX * scaleX, y: geometry.sourceRect.minY * scaleY,
                                  width: geometry.sourceRect.width * scaleX, height: geometry.sourceRect.height * scaleY)
            check(old == item.expectedPixels && near(restored, item.expectedPixels),
                  "\(item.name) preserves integral old crop and inverse relation")
            check(geometry.width == Int(item.expectedPixels.width) && geometry.height == Int(item.expectedPixels.height) &&
                  geometry.sourceRect.minX >= 0 && geometry.sourceRect.minY >= 0 &&
                  geometry.sourceRect.maxX <= item.frame.width + 1e-8 &&
                  geometry.sourceRect.maxY <= item.frame.height + 1e-8,
                  "\(item.name) output size and local bounds are valid")
        }

        let invalidSelections: [(String, CGRect)] = [
            ("empty width", CGRect(x: 0, y: 0, width: 0, height: 1)),
            ("empty height", CGRect(x: 0, y: 0, width: 1, height: 0)),
            ("negative raw width", CGRect(x: 1, y: 1, width: -1, height: 1)),
            ("negative raw height", CGRect(x: 1, y: 1, width: 1, height: -1)),
            ("NaN origin", CGRect(x: CGFloat.nan, y: 1, width: 1, height: 1)),
            ("infinite size", CGRect(x: 1, y: 1, width: CGFloat.infinity, height: 1)),
            ("endpoint overflow", CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                                         width: CGFloat.greatestFiniteMagnitude, height: 1)),
            ("outside left", CGRect(x: -20, y: 20, width: 10, height: 10)),
            ("outside right edge", CGRect(x: 1280, y: 20, width: 10, height: 10)),
            ("outside above", CGRect(x: 20, y: 721, width: 10, height: 10)),
            ("outside below edge", CGRect(x: 20, y: -10, width: 10, height: 10))
        ]
        for (name, rect) in invalidSelections {
            check(LongCaptureStreamGeometry(region: region(frame: frame, selection: rect),
                                            displayPixelWidth: 1280, displayPixelHeight: 720) == nil,
                  "reject \(name)")
        }
        for (name, rect) in [
            ("empty display frame", CGRect.zero),
            ("negative raw display frame", CGRect(x: 0, y: 0, width: -1280, height: 720)),
            ("NaN display frame", CGRect(x: 0, y: CGFloat.nan, width: 1280, height: 720)),
            ("overflowing display endpoint", CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0,
                                                    width: CGFloat.greatestFiniteMagnitude, height: 720)),
            ("overflowing scale", CGRect(x: 0, y: 0, width: CGFloat.leastNonzeroMagnitude, height: 720))
        ] {
            check(LongCaptureStreamGeometry(region: region(frame: rect, selection: selection),
                                            displayPixelWidth: 1280, displayPixelHeight: 720) == nil,
                  "reject \(name)")
        }
        for (width, height) in [(0, 720), (-1, 720), (1280, 0), (1280, -1)] {
            check(LongCaptureStreamGeometry(region: region(frame: frame, selection: selection),
                                            displayPixelWidth: width, displayPixelHeight: height) == nil,
                  "reject display size \(width)x\(height)")
        }

        // Simulate an ideal native selected buffer by copying generated display
        // pixels at the derived sourceRect. No ScreenCaptureKit resampling is run.
        for (index, item) in cases.enumerated() {
            autoreleasepool {
                let image = generatedImage(width: item.displayWidth, height: item.displayHeight)
                let region = region(frame: item.frame, selection: item.selection)
                guard let geometry = LongCaptureStreamGeometry(region: region, displayPixelWidth: item.displayWidth,
                                                               displayPixelHeight: item.displayHeight),
                      let oldCrop = LongCaptureImageSampling.crop(image: image, screenRect: item.selection,
                                                                 screenFrame: item.frame) else {
                    check(false, "synthetic pixels \(index) produce crops")
                    return
                }
                let scaleX = CGFloat(item.displayWidth) / item.frame.width
                let scaleY = CGFloat(item.displayHeight) / item.frame.height
                let pixels = CGRect(x: (geometry.sourceRect.minX * scaleX).rounded(),
                                    y: (geometry.sourceRect.minY * scaleY).rounded(),
                                    width: CGFloat(geometry.width), height: CGFloat(geometry.height))
                let native = image.cropping(to: pixels)
                let oldBytes = canonicalBytes(oldCrop)
                check(native?.width == oldCrop.width && native?.height == oldCrop.height &&
                      oldBytes != nil && native.flatMap(canonicalBytes) == oldBytes,
                      "synthetic pixels \(item.name) equal old full-display crop")
            }
        }

        let failed = results.filter { ($0["passed"] as? Bool) != true }.count
        let report: [String: Any] = ["suite": "long-capture-stream-geometry", "passed": results.count - failed,
                                     "failed": failed, "cases": results,
                                     "limitation": "Offline generated pixels only; no SCStream or desktop capture was run."]
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_CHECK_RESULTS"],
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        print("\(results.count - failed)/\(results.count) checks passed")
        if failed > 0 { exit(1) }
    }
}
