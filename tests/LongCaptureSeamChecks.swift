import AppKit

/// Independent public pixel sequences. No app, desktop, clipboard or user files.
@main
struct LongCaptureSeamChecks {
    private struct Patch {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    static func main() {
        var results: [[String: Any]] = []
        func check(_ passed: Bool, _ name: String) {
            results.append(["name": name, "passed": passed])
            print("\(passed ? "PASS" : "FAIL"): \(name)")
        }
        func send(_ accumulator: LongCaptureFrameAccumulator, offset: Int, index: Int,
                  footer: Int = 0, patches: [Patch] = []) -> LongCaptureProgress? {
            accumulator.process(frame: .init(image: fixture(offset: offset, footer: footer, patches: patches),
                                              timestamp: Double(index) / 10))
        }
        func exact(_ accumulator: LongCaptureFrameAccumulator, offsets: [Int], footers: [Int], _ name: String) {
            do {
                guard let output = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    check(false, "\(name): missing CGImage"); return
                }
                check(samePixels(output, expected(offsets: offsets, footers: footers)), name)
            } catch { check(false, "\(name): \(error.localizedDescription)") }
        }
        func incomplete(_ accumulator: LongCaptureFrameAccumulator, _ name: String) {
            do { _ = try accumulator.renderFinalImage(); check(false, name) }
            catch LongCaptureError.incompleteCapture { check(true, name) }
            catch { check(false, "\(name): unexpected \(error.localizedDescription)") }
        }
        func exactOrIncomplete(_ accumulator: LongCaptureFrameAccumulator,
                               offsets: [Int], footers: [Int], _ name: String) {
            do {
                guard let output = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    check(false, "\(name): missing CGImage"); return
                }
                check(samePixels(output, expected(offsets: offsets, footers: footers)),
                      "\(name): any successful output must match every known pixel")
            } catch LongCaptureError.incompleteCapture {
                check(true, "\(name): explicit incomplete capture")
            } catch { check(false, "\(name): unexpected \(error.localizedDescription)") }
        }

        // Fixed texture outside the moving pane must neither vote for motion
        // nor change the row background used to compare its aligned pixels.
        let clean = LongCaptureFrameAccumulator()
        for (index, offset) in [0, 120, 240].enumerated() {
            let progress = send(clean, offset: offset, index: index)
            check(progress?.warning == nil && progress?.appendedPixelHeight == 480 + offset,
                  "textured fixed sidebar and 60px header preserve offset \(offset)")
        }
        exact(clean, offsets: [0, 120, 240], footers: [0, 0, 0],
              "fixed sidebar/header output preserves known body and copied sidebar pixels")

        let reverse = LongCaptureFrameAccumulator()
        for (index, offset) in [0, 120, 240, 180, 120, 360].enumerated() {
            let progress = send(reverse, offset: offset, index: index)
            check(progress?.warning == nil, "reverse revisit beside fixed sidebar remains connected at \(offset)")
        }
        exact(reverse, offsets: [0, 120, 240, 360], footers: [0, 0, 0, 0],
              "reverse revisit leaves the committed forward frontier and exact 840px output")

        // A caret/hover can remain at the same screen location while the body
        // scrolls. Alignment exposes both the old and new small repaint patch.
        let caret = Patch(x: 200, y: 250, width: 4, height: 4)
        for footer in [0, 20] {
            let local = LongCaptureFrameAccumulator()
            _ = send(local, offset: 0, index: 0, footer: footer)
            for (index, offset) in [120, 240].enumerated() {
                let progress = send(local, offset: offset, index: index + 1, footer: footer, patches: [caret])
                check(progress?.warning == nil && progress?.appendedPixelHeight == 480 + offset,
                      "same-screen 4x4 repaint survives consecutive 120px motion with footer \(footer), offset \(offset)")
            }
            exact(local, offsets: [0, 120, 240], footers: [footer, footer, footer],
                  "two transient repaint locations preserve the known output and single footer \(footer)")
        }

        // The header can repaint while the body moves; its pixels at zero
        // displacement must remain within the same bounded transient budget.
        let header = LongCaptureFrameAccumulator()
        _ = send(header, offset: 0, index: 0)
        _ = send(header, offset: 120, index: 1, patches: [Patch(x: 200, y: 25, width: 4, height: 4)])
        _ = send(header, offset: 240, index: 2, patches: [Patch(x: 200, y: 25, width: 4, height: 4)])
        exact(header, offsets: [0, 120, 240], footers: [0, 0, 0],
              "fixed-header repaint concurrent with motion preserves the exact known document")

        // Local tolerance is restricted to a pair of isolated transient patches,
        // far enough from the seam to leave its entering rows independently valid.
        let three = LongCaptureFrameAccumulator()
        _ = send(three, offset: 0, index: 0)
        let threeProgress = send(three, offset: 120, index: 1, patches: [
            Patch(x: 200, y: 150, width: 2, height: 2),
            Patch(x: 300, y: 220, width: 2, height: 2),
            Patch(x: 400, y: 290, width: 2, height: 2)
        ])
        check(threeProgress?.warning != nil && threeProgress?.appendedPixelHeight == 480,
              "three separated repaint patches cannot use the two-patch motion tolerance")
        incomplete(three, "three unsupported patches never export an accepted prefix")

        let edge = LongCaptureFrameAccumulator()
        _ = send(edge, offset: 0, index: 0)
        let edgeProgress = send(edge, offset: 120, index: 1,
                                patches: [Patch(x: 200, y: 350, width: 4, height: 4)])
        check(edgeProgress?.warning != nil && edgeProgress?.appendedPixelHeight == 480,
              "repaint within 16px of the overlap seam cannot excuse changed entering pixels")
        incomplete(edge, "changed pixels near the seam remain explicitly incomplete")

        let oversized = LongCaptureFrameAccumulator()
        _ = send(oversized, offset: 0, index: 0)
        let oversizedProgress = send(oversized, offset: 120, index: 1,
                                     patches: [Patch(x: 200, y: 200, width: 13, height: 10)])
        check(oversizedProgress?.warning != nil && oversizedProgress?.appendedPixelHeight == 480,
              "130 changed overlap pixels remain outside the bounded repaint tolerance")
        incomplete(oversized, "over-budget repaint never exports an accepted prefix")

        for footers in [[0, 0, 20, 20], [20, 20, 40, 40], [20, 20, 0, 0]] {
            let dynamic = LongCaptureFrameAccumulator()
            let offsets = [0, 120, 240, 360]
            for (index, offset) in offsets.enumerated() {
                _ = send(dynamic, offset: offset, index: index, footer: footers[index])
            }
            exactOrIncomplete(dynamic, offsets: offsets, footers: footers,
                              "dynamic footer \(footers) cannot silently save duplicated or missing rows")
        }

        for finalFooter in [0, 40] {
            let changedReverse = LongCaptureFrameAccumulator()
            for (index, offset) in [0, 120, 240].enumerated() {
                _ = send(changedReverse, offset: offset, index: index, footer: 20)
            }
            let progress = send(changedReverse, offset: 120, index: 3, footer: finalFooter)
            check(progress?.warning != nil,
                  "reverse revisit with changed footer 20 to \(finalFooter) cannot bypass geometry validation")
            incomplete(changedReverse,
                       "changed reverse footer \(finalFooter) cannot export a stale accepted footer")
        }

        let failed = results.filter { ($0["passed"] as? Bool) == false }.count
        let report: [String: Any] = ["suite": "LongCaptureSeamChecks", "assertions": results.count,
                                     "passed": results.count - failed, "failed": failed,
                                     "results": results,
                                     "scope": "generated public pixels; no desktop or app; expected full pixels are built independently"]
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_SEAM_QA_OUTPUT"] {
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch { print("FAIL: write QA evidence: \(error)"); exit(1) }
        }
        print("RESULT: \(results.count - failed)/\(results.count) passed; \(failed) failures")
        if failed > 0 { exit(1) }
    }

    private static func value(x: Int, y: Int) -> UInt8 {
        var bits = UInt32(truncatingIfNeeded: y * 480 + x + 1)
        bits ^= bits >> 16; bits &*= 0x7feb352d; bits ^= bits >> 15
        bits &*= 0x846ca68b; bits ^= bits >> 16
        return UInt8(20 + bits % 210)
    }

    private static func fixture(offset: Int, footer: Int, patches: [Patch]) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: 480 * 480 * 4)
        for y in 0..<480 {
            for x in 0..<480 {
                var v = value(x: x, y: y + offset)
                if y < 60 || x < 100 { v = value(x: x, y: y) }
                if footer > 0 && y >= 480 - footer { v = 90 }
                let i = (y * 480 + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        for patch in patches {
            for y in patch.y..<(patch.y + patch.height) {
                for x in patch.x..<(patch.x + patch.width) {
                    let i = (y * 480 + x) * 4
                    pixels[i] = 250; pixels[i + 1] = 250; pixels[i + 2] = 250
                }
            }
        }
        return image(pixels, height: 480)
    }

    /// Build the reference from the independently known document coordinates,
    /// copying only newly revealed rows and the last footer. No matcher/store API.
    private static func expected(offsets: [Int], footers: [Int]) -> CGImage {
        var pixels: [UInt8] = []
        var worldEnd = 0
        for (index, offset) in offsets.enumerated() {
            let source = fixture(offset: offset, footer: footers[index], patches: [])
            let data = Array(source.dataProvider!.data! as Data)
            let bodyEnd = 480 - footers[index]
            let newWorldEnd = offset + bodyEnd
            let addedRows = newWorldEnd - worldEnd
            let sourceStart = index == 0 ? 0 : bodyEnd - addedRows
            pixels.append(contentsOf: data[(sourceStart * 480 * 4)..<(bodyEnd * 480 * 4)])
            worldEnd = newWorldEnd
        }
        let footer = footers.last!
        if footer > 0 {
            let finalFrame = fixture(offset: offsets.last!, footer: footer, patches: [])
            let data = Array(finalFrame.dataProvider!.data! as Data)
            pixels.append(contentsOf: data[((480 - footer) * 480 * 4)..<data.count])
        }
        return image(pixels, height: pixels.count / (480 * 4))
    }

    private static func image(_ pixels: [UInt8], height: Int) -> CGImage {
        CGImage(width: 480, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 480 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func canonicalBytes(_ source: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let context = CGContext(data: &bytes, width: source.width, height: source.height,
                                bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return bytes
    }

    private static func samePixels(_ output: CGImage, _ reference: CGImage) -> Bool {
        output.width == reference.width && output.height == reference.height &&
            canonicalBytes(output) == canonicalBytes(reference)
    }
}
