import AppKit
import Foundation

/// Public generated pixels prove that a fixed header redraw does not erase an
/// independently moving pane. Exact exports use independently known strip rows.
@main
struct LongCaptureMatcherBoundaryChecks {
    struct Scenario {
        let name: String
        let first: CGImage
        let next: CGImage
        let expected: CGImage?
    }

    static func main() {
        var results: [[String: Any]] = []
        func check(_ okay: Bool, _ label: String, details: String = "") {
            results.append(["name": label, "passed": okay, "details": details])
            print("\(okay ? "PASS" : "FAIL"): \(label)\(details.isEmpty ? "" : ": " + details)")
        }
        var scenarios: [Scenario] = [
            Scenario(name: "fixed textured header and sidebar retain exact 120px motion",
                     first: fixture(offset: 0), next: fixture(offset: 120), expected: expected(offset: 120)),
            Scenario(name: "uniform 4x4 header redraw retains exact 120px body motion",
                     first: fixture(offset: 0), next: fixture(offset: 120, redraw: true), expected: expected(offset: 120)),
        ]
        for (width, height, shift) in [(1, 2, 1), (2, 16, 1), (2, 20, 1), (2, 30, 1), (2, 60, 72), (4, 60, 72)] {
            scenarios.append(Scenario(name: "independent \(width)x\(height) textured prefix pane moves\(shift) beside body120",
                                      first: fixture(offset: 0, pane: (width, height, 0)),
                                      next: fixture(offset: 120, pane: (width, height, shift)), expected: nil))
        }
        scenarios += [
            Scenario(name: "8px second body pane cannot disappear beside dominant motion",
                     first: fixture(offset: 0, rightOffset: 0, splitX: 472),
                     next: fixture(offset: 120, rightOffset: 72, splitX: 472), expected: nil),
            Scenario(name: "two broad body panes with conflicting displacements reject",
                     first: fixture(offset: 0, rightOffset: 0),
                     next: fixture(offset: 120, rightOffset: 72, redraw: true), expected: nil),
            Scenario(name: "independent vertical body motions reject",
                     first: vertical(top: 0, bottom: 0), next: vertical(top: 120, bottom: 72), expected: nil),
            Scenario(name: "a real 1500px gap cannot become a connected prefix",
                     first: fixture(offset: 0), next: fixture(offset: 1500, redraw: true), expected: nil),
            Scenario(name: "periodic body cannot fabricate a unique 7px seam",
                     first: fixture(offset: 0, periodic: true),
                     next: fixture(offset: 7, redraw: true, periodic: true), expected: nil),
        ]
        for s in scenarios {
            let accumulator = LongCaptureFrameAccumulator()
            _ = accumulator.process(frame: .init(image: s.first, timestamp: 0))
            let progress = accumulator.process(frame: .init(image: s.next, timestamp: 0.1))
            do {
                let image = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)
                let okay = s.expected.flatMap { expected in image.map { samePixels($0, expected) } } ?? false
                check(okay, s.name, details: "export \(image?.width ?? 0)x\(image?.height ?? 0)")
            } catch LongCaptureError.incompleteCapture {
                check(s.expected == nil && progress?.warning != nil, s.name, details: "explicit incomplete capture")
            } catch { check(false, s.name, details: "unexpected \(error.localizedDescription)") }
            if s.expected == nil {
                _ = accumulator.process(frame: .init(image: s.next, timestamp: 0.2))
                do { _ = try accumulator.renderFinalImage(); check(false, "\(s.name): repeated failure cannot export") }
                catch LongCaptureError.incompleteCapture { check(true, "\(s.name): repeated failure cannot export") }
                catch { check(false, "\(s.name): repeat returned unexpected \(error.localizedDescription)") }
            }
        }

        // Local patch support must continue beyond the first successful seam;
        // only observed new suffix rows may enter the retained document.
        let continuing = LongCaptureFrameAccumulator()
        _ = continuing.process(frame: .init(image: fixture(offset: 0), timestamp: 0))
        _ = continuing.process(frame: .init(image: fixture(offset: 120, redraw: true), timestamp: 0.1))
        let continued = continuing.process(frame: .init(image: fixture(offset: 240, redraw: true), timestamp: 0.2))
        do {
            let output = try continuing.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)
            check(continued?.warning == nil && output.map { samePixels($0, expected(offset: 240)) } == true,
                  "fixed-header redraw permits a second exact seam without repeated content")
        } catch { check(false, "second header-redraw seam", details: error.localizedDescription) }

        let failed = results.filter { ($0["passed"] as? Bool) == false }.count
        let report: [String: Any] = ["suite": "LongCaptureMatcherBoundaryChecks", "assertions": results.count,
            "passed": results.count - failed, "failed": failed, "results": results,
            "scope": "offline generated public RGBA pixels; no desktop or user images",
            "prefix_policy": "supported uniform 4x4 repaint exports exactly; independently moving texture, gaps and ambiguity reject"]
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_MATCHER_BOUNDARY_QA_OUTPUT"] {
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch { print("FAIL: write QA evidence: \(error)"); exit(1) }
        }
        print("RESULT: \(results.count - failed)/\(results.count) passed; \(failed) failures")
        if failed > 0 { exit(1) }
    }

    static func value(_ x: Int, _ y: Int) -> UInt8 {
        var bits = UInt32(truncatingIfNeeded: y * 480 + x + 1)
        bits ^= bits >> 16; bits &*= 0x7feb352d; bits ^= bits >> 15
        bits &*= 0x846ca68b; bits ^= bits >> 16
        return UInt8(20 + bits % 210)
    }

    static func image(_ p: [UInt8], height: Int = 480) -> CGImage {
        CGImage(width: 480, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 480 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(p) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func pixels(_ color: (Int, Int) -> UInt8) -> CGImage {
        var p = [UInt8](repeating: 255, count: 480 * 480 * 4)
        for y in 0..<480 { for x in 0..<480 {
            let v = color(x, y), i = (y * 480 + x) * 4
            p[i] = v; p[i + 1] = v; p[i + 2] = v
        } }
        return image(p)
    }

    static func fixture(offset: Int, rightOffset: Int? = nil, splitX: Int = 290,
                        redraw: Bool = false, periodic: Bool = false,
                        pane: (width: Int, height: Int, offset: Int)? = nil) -> CGImage {
        pixels { x, y in
            if let pane, y < pane.height && (200..<(200 + pane.width)).contains(x) {
                return value(x, y + pane.offset)
            }
            if redraw && (25..<29).contains(y) && (200..<204).contains(x) { return 250 }
            if y < 60 || x < 100 { return value(x, y) }
            let displacement = x < splitX ? offset : (rightOffset ?? offset)
            return value(x, periodic ? (y + displacement) % 24 : y + displacement)
        }
    }

    static func vertical(top: Int, bottom: Int) -> CGImage {
        pixels { x, y in
            if y < 60 || x < 100 { return value(x, y) }
            return value(x, y + (y < 240 ? top : bottom))
        }
    }

    static func expected(offset: Int) -> CGImage {
        var bytes = Array(fixture(offset: 0).dataProvider!.data! as Data)
        for cumulativeOffset in stride(from: 120, through: offset, by: 120) {
            let frame = Array(fixture(offset: cumulativeOffset).dataProvider!.data! as Data)
            bytes += Array(frame[(360 * 480 * 4)..<frame.count])
        }
        return image(bytes, height: 480 + offset)
    }

    static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height, a.bitsPerComponent == b.bitsPerComponent,
              a.bitsPerPixel == b.bitsPerPixel, a.bitmapInfo == b.bitmapInfo,
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
        for y in 0..<a.height {
            if memcmp(ap + y * a.bytesPerRow, bp + y * b.bytesPerRow, a.width * 4) != 0 { return false }
        }
        return true
    }
}
