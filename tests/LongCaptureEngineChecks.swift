import AppKit
import Foundation

/// End-to-end quality checks over generated public pixels. This binary does not
/// launch the app, capture a display, access the clipboard, or read user images.
@main
struct LongCaptureEngineChecks {
    @MainActor static func main() {
        var results: [[String: Any]] = []
        func check(_ condition: Bool, _ label: String) {
            results.append(["name": label, "passed": condition])
            print("\(condition ? "PASS" : "FAIL"): \(label)")
        }
        func feed(_ accumulator: LongCaptureFrameAccumulator, _ image: CGImage, _ index: Int) -> LongCaptureProgress? {
            accumulator.process(frame: .init(image: image, timestamp: Double(index) / 10))
        }
        func exact(_ accumulator: LongCaptureFrameAccumulator, _ expected: CGImage, _ label: String) {
            do {
                guard let actual = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    check(false, "\(label): missing CGImage"); return
                }
                check(samePixels(actual, expected), label)
            } catch {
                check(false, "\(label): \(error.localizedDescription)")
            }
        }
        func incomplete(_ accumulator: LongCaptureFrameAccumulator, _ label: String) {
            do { _ = try accumulator.renderFinalImage(); check(false, label) }
            catch LongCaptureError.incompleteCapture { check(true, label) }
            catch { check(false, "\(label): unexpected \(error.localizedDescription)") }
        }
        func exactOrIncomplete(_ accumulator: LongCaptureFrameAccumulator, _ expected: CGImage, _ label: String) {
            do {
                guard let actual = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    check(false, "\(label): missing CGImage"); return
                }
                check(samePixels(actual, expected), "\(label): successful export must be exact")
            } catch LongCaptureError.incompleteCapture {
                check(true, "\(label): conservative incomplete capture")
            } catch {
                check(false, "\(label): unexpected \(error.localizedDescription)")
            }
        }

        // The same sequence exercises small and large translations in one
        // document, so a wrong seam cannot be hidden by restarting the matcher.
        let offsets = [0, 1, 3, 123, 243]
        let stitcher = LongCaptureStitcher()
        for (index, offset) in offsets.enumerated() {
            let result = stitcher.append(frame: .init(image: document(offset: offset), timestamp: Double(index) / 10))
            check(result.accepted, "stitcher accepts known cumulative offset \(offset)")
            check(stitcher.totalPixelHeight == 480 + offset, "stitcher height follows known offset \(offset)")
        }
        if let actual = stitcher.renderFinalImage()?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            check(samePixels(actual, document(offset: 0, height: 723)),
                  "stitcher renders every pixel exactly once after 1/2/120/120px motion")
        } else {
            check(false, "stitcher renders every pixel exactly once after 1/2/120/120px motion")
        }
        let connected = LongCaptureFrameAccumulator()
        for (index, offset) in offsets.enumerated() {
            let progress = feed(connected, document(offset: offset), index)
            check(progress?.warning == nil, "accumulator accepts known cumulative offset \(offset)")
        }
        _ = feed(connected, document(offset: 243), 6)
        exact(connected, document(offset: 0, height: 723),
              "accumulator and duplicate endpoint preserve exact 723px document")

        let revisit = LongCaptureFrameAccumulator()
        for (index, offset) in [0, 120, 240, 180, 120, 240, 360].enumerated() {
            let progress = feed(revisit, document(offset: offset), index)
            check(progress?.warning == nil, "reverse revisit sequence remains connected at offset \(offset)")
        }
        exact(revisit, document(offset: 0, height: 840),
              "reverse revisits then forward progress contain no repeated or missing rows")

        // A known compositor-like change: one uniform color pair at exactly the
        // same location, 126px tall, with distinctive stable structure above and
        // below in those columns. It must preserve the connected frontier.
        let local = LongCaptureFrameAccumulator()
        for (index, offset) in [0, 120, 240].enumerated() {
            _ = feed(local, document(offset: offset, flatPatch: true), index)
        }
        let redraw = oneLevelTallRedraw(document(offset: 240, flatPatch: true))
        let localProgress = feed(local, redraw, 3)
        check(localProgress?.warning == nil && localProgress?.appendedPixelHeight == 720,
              "126px tall same-position one-color redraw preserves connected frontier")
        exact(local, document(offset: 0, height: 720, flatPatch: true),
              "finishing on tall local redraw preserves previously connected pixels")
        _ = feed(local, document(offset: 360, flatPatch: true), 4)
        exact(local, document(offset: 0, height: 840, flatPatch: true),
              "forward motion after tall redraw resumes from the true frontier")

        for lowContrast in [false, true] {
            let sparse = LongCaptureFrameAccumulator()
            _ = feed(sparse, sparseWithSidebar(pointY: 300, lowContrast: lowContrast), 0)
            _ = feed(sparse, sparseWithSidebar(pointY: 299, lowContrast: lowContrast), 1)
            _ = feed(sparse, sparseWithSidebar(pointY: 299, lowContrast: lowContrast), 2)
            incomplete(sparse, "\(lowContrast ? "one-level" : "high-contrast") sparse motion beside fixed sidebar cannot be swallowed")
        }

        let gap = LongCaptureFrameAccumulator()
        _ = feed(gap, document(offset: 0), 0)
        _ = feed(gap, document(offset: 120), 1)
        for index in 2...3 {
            _ = feed(gap, document(offset: 1500), index)
        }
        incomplete(gap, "repeated real gap beyond viewport cannot export accepted prefix")
        _ = feed(gap, document(offset: 120), 4)
        _ = feed(gap, document(offset: 240), 5)
        exact(gap, document(offset: 0, height: 720),
              "returning to exact frontier after gap restores complete document")

        let ambiguous = LongCaptureFrameAccumulator()
        _ = feed(ambiguous, periodic(offset: 0), 0)
        _ = feed(ambiguous, periodic(offset: 7), 1)
        _ = feed(ambiguous, periodic(offset: 7), 2)
        incomplete(ambiguous, "repeated ambiguous periodic content cannot fabricate a seam")

        let stableFooter = LongCaptureFrameAccumulator()
        for (index, offset) in [0, 120, 240, 360].enumerated() {
            _ = feed(stableFooter, document(offset: offset, footer: 20), index)
        }
        exact(stableFooter, document(offset: 0, height: 840, footer: 20),
              "constant 20px footer appears exactly once without losing document pixels")

        // Dynamic footer safety is intentionally success-or-explicit-rejection.
        // A first implementation may refuse changed geometry. Any success must
        // match the complete known document plus only the final footer.
        for (label, footerHeights) in [
            ("footer grows 0 to20", [0, 0, 20, 20]),
            ("footer grows20 to40", [20, 20, 40, 40])
        ] {
            let dynamicFooter = LongCaptureFrameAccumulator()
            for (index, offset) in [0, 120, 240, 360].enumerated() {
                _ = feed(dynamicFooter, document(offset: offset, footer: footerHeights[index]), index)
            }
            exactOrIncomplete(dynamicFooter, document(offset: 0, height: 840, footer: footerHeights.last!),
                              "\(label) cannot silently export a wrong image")
        }

        let unfinished = LongCaptureFrameAccumulator()
        _ = feed(unfinished, document(offset: 0), 0)
        _ = feed(unfinished, document(offset: 120), 1)
        _ = feed(unfinished, document(offset: 120, seed: 99), 2)
        incomplete(unfinished, "stopping with final unrelated unmatched frame never exports connected prefix")

        let failed = results.filter { ($0["passed"] as? Bool) == false }.count
        let report: [String: Any] = [
            "suite": "LongCaptureEngineChecks",
            "assertions": results.count,
            "passed": results.count - failed,
            "failed": failed,
            "results": results,
            "scope": "generated public pixels; no desktop, clipboard, app, or private images",
            "dynamic_footer_policy": "exact export or incompleteCapture; wrong successful image fails",
        ]
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_ENGINE_QA_OUTPUT"] {
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch {
                print("FAIL: write QA evidence: \(error)"); exit(1)
            }
        }
        print("RESULT: \(results.count - failed)/\(results.count) passed; \(failed) failures")
        if failed > 0 { exit(1) }
    }

    static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func value(x: Int, y: Int, seed: Int = 0) -> UInt8 {
        var bits = UInt32(truncatingIfNeeded: y * 480 + x + 1) ^ (UInt32(seed) &* 0x9e3779b9)
        bits ^= bits >> 16; bits &*= 0x7feb352d; bits ^= bits >> 15
        bits &*= 0x846ca68b; bits ^= bits >> 16
        return UInt8(20 + bits % 210)
    }

    static func document(offset: Int, height: Int = 480, footer: Int = 0, flatPatch: Bool = false, seed: Int = 0) -> CGImage {
        let width = 480
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let worldY = y + offset
                var v = value(x: x, y: worldY, seed: seed)
                if flatPatch && (400..<526).contains(worldY) && (200..<216).contains(x) { v = 160 }
                if footer > 0 && y >= height - footer { v = 90 }
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        return image(pixels, width: width, height: height)
    }

    static func oneLevelTallRedraw(_ original: CGImage) -> CGImage {
        var pixels = Array(original.dataProvider!.data! as Data)
        for y in 160..<286 {
            for x in 200..<216 {
                let i = (y * original.width + x) * 4
                for channel in 0..<3 { pixels[i + channel] += 1 }
            }
        }
        return image(pixels, width: original.width, height: original.height)
    }

    static func sparseWithSidebar(pointY: Int, lowContrast: Bool) -> CGImage {
        let width = 480, height = 480
        var pixels = [UInt8](repeating: 245, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = x < 140 ? value(x: x, y: y) : ((x == 300 && y == pointY) ? (lowContrast ? 244 : 40) : 245)
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        return image(pixels, width: width, height: height)
    }

    static func periodic(offset: Int) -> CGImage {
        let width = 480, height = 480
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = (7..<16).contains((y + offset) % 24) && (40..<300).contains(x) ? 45 : 245
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        return image(pixels, width: width, height: height)
    }

    static func rgba(_ source: CGImage) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: source.width * source.height * 4)
        let context = CGContext(data: &result, width: source.width, height: source.height, bitsPerComponent: 8,
                                bytesPerRow: source.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return result
    }

    static func samePixels(_ actual: CGImage, _ expected: CGImage) -> Bool {
        actual.width == expected.width && actual.height == expected.height && rgba(actual) == rgba(expected)
    }
}

