import AppKit
import Foundation

/// Generated public pixels and an injected clock only. This tests the trusted
/// frozen-preview seed contract; it does not start ScreenCaptureKit, capture a
/// display, operate a desktop, or establish that a particular app is at its top.
@main
struct LongCaptureInitialBaselineChecks {
    private static var checks = 0

    private final class Releases: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func released() { lock.withLock { value += 1 } }
    }

    @MainActor static func main() {
        let initial = document(offset: 0)
        selectionSnapshotDetachesSource()
        selectionCoordinatesPreservePixels()

        // The snapshot predates any live frame. A first live callback may already
        // contain integer or fractional rubber-band displacement, or never show
        // an exact return before normal forward scrolling begins.
        for (label, observations) in [
            ("integer then fractional bounce", [elastic(20), elastic(0.25), initial, document(offset: 120)]),
            ("fractional first callback", [elastic(0.25), initial, document(offset: 120)]),
            ("no exact return callback", [elastic(20), elastic(0.25), document(offset: 120)])
        ] {
            let accumulator = seeded(initial)
            for (index, image) in observations.enumerated() { feed(accumulator, image, index + 1) }
            exact(accumulator, document(offset: 0, height: 600),
                  "\(label) exports the 600px document without bounce whitespace or resampling")
        }

        let stationary = seeded(initial)
        feed(stationary, initial, 1)
        if let final = settled([(.init(image: initial, timestamp: 41.125), 0.1)], at: 0.35) {
            check(final.timestamp == 41.125, "no-scroll final observation keeps the real capture timestamp")
            _ = stationary.process(frame: final)
        }
        exact(stationary, initial, "no-scroll capture exports the exact frozen 480px selection")

        // A finish request during the recoil must observe the settled current
        // position, then ask the accumulator for connection proof exactly once.
        let finalBounce = seeded(initial)
        feed(finalBounce, document(offset: 120), 1)
        let returned = document(offset: 120)
        if let final = settled([
            (.init(image: elastic(20, offset: 120), timestamp: 100.0), 0.0),
            (.init(image: elastic(0.25, offset: 120), timestamp: 100.1), 0.1),
            (.init(image: returned, timestamp: 100.3), 0.3)
        ], at: 0.55) {
            check(final.timestamp == 100.3 && samePixels(final.image, returned),
                  "finish settlement selects the latest real returned position")
            _ = finalBounce.process(frame: final)
        }
        exact(finalBounce, document(offset: 0, height: 600),
              "settled final recoil preserves every connected document row exactly once")

        let gap = seeded(initial)
        feed(gap, document(offset: 120), 1)
        if let final = settled([(.init(image: document(offset: 1500), timestamp: 77), 0.0)], at: 0.25) {
            _ = gap.process(frame: final)
        }
        incomplete(gap, "a stable real gap cannot fall back to the trusted seed or accepted prefix")

        let dimensions = seeded(initial)
        feed(dimensions, document(offset: 0, width: 481), 1)
        incomplete(dimensions, "a live frame with different seed dimensions fails explicitly")

        let limits = LongCaptureFrameAccumulator(limits: .init(maximumFrameBytes: 4))
        do { _ = try limits.seed(image: initial); check(false, "an unusable seed must not start a document") }
        catch LongCaptureError.resourceLimit { check(true, "an unusable seed reports its resource failure") }
        catch { check(false, "unusable seed returned unexpected \(error)") }

        let duplicateSeed = seeded(initial)
        do { _ = try duplicateSeed.seed(image: initial); check(false, "a second seed must not replace the committed baseline") }
        catch LongCaptureError.noStableFrame { check(true, "a second seed is rejected without mutating the document") }
        catch { check(false, "duplicate seed returned unexpected \(error)") }
        exact(duplicateSeed, initial, "rejected reseeding preserves the original trusted selection")

        // The single-frontier engine cannot prove a revisit farther than one
        // viewport. A trusted initial image does not repair that separate limit.
        let deepReverse = seeded(initial)
        for (index, offset) in [120, 240, 360, 480, 600, 0].enumerated() {
            feed(deepReverse, document(offset: offset), index + 1)
        }
        incomplete(deepReverse, "a deep reverse outside current overlap remains explicit incomplete capture")

        print("RESULT: \(checks) deterministic initial-baseline checks passed")
    }

    @MainActor private static func seeded(_ image: CGImage) -> LongCaptureFrameAccumulator {
        let frame = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let region = LongCaptureRegion(selectionRect: frame, screenRect: frame, screenFrame: frame, displayID: 0)
        guard let snapshot = LongCaptureInitialFrameSource.selection(from: image, region: region) else {
            preconditionFailure("The generated frozen selection could not be detached")
        }
        let accumulator = LongCaptureFrameAccumulator()
        guard let progress = try? accumulator.seed(image: snapshot) else { preconditionFailure("Could not seed the document") }
        check(progress.acceptedFrameCount == 1 && progress.warning == nil,
              "trusted detached initial selection creates one committed baseline")
        return accumulator
    }

    private static func selectionSnapshotDetachesSource() {
        let width = 48, height = 64, stride = width * 4 + 16
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let release = Releases()
        var snapshot: CGImage?
        var expected = Data()
        autoreleasepool {
            let bytes = UnsafeMutableRawPointer.allocate(byteCount: stride * height, alignment: 16)
            bytes.initializeMemory(as: UInt8.self, repeating: 0xee, count: stride * height)
            let pixel = bytes.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * stride + x * 4
                    pixel[i] = UInt8((x * 13 + y * 7) % 200)
                    pixel[i + 1] = UInt8((x * 5 + y * 19) % 200)
                    pixel[i + 2] = UInt8((x * 17 + y * 3) % 200)
                    pixel[i + 3] = 255
                }
            }
            let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(release).toOpaque(), data: bytes,
                                          size: stride * height, releaseData: { context, pixels, _ in
                pixels.deallocate()
                Unmanaged<Releases>.fromOpaque(context!).takeRetainedValue().released()
            })!
            let preview = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: stride, space: colorSpace, bitmapInfo: info, provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            // Cocoa screenRect is bottom-left, so this selects original rows 28...51.
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            let region = LongCaptureRegion(selectionRect: .zero,
                                           screenRect: CGRect(x: 8, y: 12, width: 24, height: 24),
                                           screenFrame: frame, displayID: 0)
            for row in 28..<52 { expected.append(pixel + row * stride + 8 * 4, count: 24 * 4) }
            snapshot = LongCaptureInitialFrameSource.selection(from: preview, region: region)
            check(LongCaptureInitialFrameSource.selection(from: preview, region: region, maximumBytes: 1) == nil,
                  "a seed snapshot over its pixel-byte limit is rejected")
        }
        guard let snapshot else { preconditionFailure("The padded public selection could not be copied") }
        check(release.count == 1, "the copied selection no longer keeps the entire frozen-preview pixel provider alive")
        check(snapshot.width == 24 && snapshot.height == 24 && snapshot.bytesPerRow == 24 * 4 &&
              snapshot.bitmapInfo == info && snapshot.colorSpace.map { CFEqual($0, colorSpace) } == true &&
              snapshot.dataProvider?.data.map { $0 as Data } == expected,
              "selection copying preserves exact original BGRA pixels/profile and ignores preview row padding")
    }

    private static func selectionCoordinatesPreservePixels() {
        let preview = document(offset: 0, width: 48, height: 64)
        let frame = CGRect(x: 0, y: 0, width: 48, height: 64)
        let local = CGRect(x: 8, y: 12, width: 24, height: 24)
        let cases: [(String, CGRect, CGRect, CGRect)] = [
            ("fractional selection expands to full pixels", frame,
             CGRect(x: 8.25, y: 12.25, width: 23.5, height: 23.5), CGRect(x: 8, y: 28, width: 24, height: 24)),
            ("clipped selection at display edge", frame,
             CGRect(x: -4.25, y: 52.25, width: 16, height: 16), CGRect(x: 0, y: 0, width: 12, height: 12)),
            ("left display origin", frame.offsetBy(dx: -48, dy: 0), local.offsetBy(dx: -48, dy: 0),
             CGRect(x: 8, y: 28, width: 24, height: 24)),
            ("above display origin", frame.offsetBy(dx: -48, dy: 64), local.offsetBy(dx: -48, dy: 64),
             CGRect(x: 8, y: 28, width: 24, height: 24)),
            ("2x native selection", CGRect(x: 0, y: 0, width: 24, height: 32),
             CGRect(x: 4, y: 6, width: 12, height: 12), CGRect(x: 8, y: 28, width: 24, height: 24))
        ]
        let source = preview.dataProvider!.data! as Data
        for (label, screenFrame, screenRect, pixels) in cases {
            let region = LongCaptureRegion(selectionRect: .zero, screenRect: screenRect,
                                           screenFrame: screenFrame, displayID: 0)
            guard let snapshot = LongCaptureInitialFrameSource.selection(from: preview, region: region) else {
                check(false, "\(label): snapshot unavailable"); return
            }
            var expected = Data()
            for y in Int(pixels.minY)..<Int(pixels.maxY) {
                let offset = y * preview.bytesPerRow + Int(pixels.minX) * 4
                expected.append(source[offset..<(offset + Int(pixels.width) * 4)])
            }
            check(snapshot.width == Int(pixels.width) && snapshot.height == Int(pixels.height) &&
                  snapshot.dataProvider!.data! as Data == expected,
                  "\(label) preserves every original selected pixel")
        }
        let outside = LongCaptureRegion(selectionRect: .zero,
                                        screenRect: CGRect(x: 80, y: 80, width: 8, height: 8),
                                        screenFrame: frame, displayID: 0)
        check(LongCaptureInitialFrameSource.selection(from: preview, region: outside) == nil,
              "a selection completely outside the preview fails explicitly")
    }

    private static func feed(_ accumulator: LongCaptureFrameAccumulator, _ image: CGImage, _ index: Int) {
        _ = accumulator.process(frame: .init(image: image, timestamp: Double(index) / 10))
    }

    private static func settled(_ observations: [(LongCaptureFrame, Double)], at time: Double) -> LongCaptureFrame? {
        let settlement = LongCaptureFrameSettlement<LongCaptureFrame>(startedAt: 0, areEqual: {
            samePixels($0.image, $1.image)
        })!
        for (frame, receivedAt) in observations {
            guard case .waiting = settlement.observe(frame, receivedAt: receivedAt) else {
                check(false, "final observations must wait for their own quiet interval")
                return nil
            }
        }
        guard case .settled(let frame) = settlement.poll(at: time) else {
            check(false, "final frame must settle without another callback")
            return nil
        }
        check(true, "final frame settles using monotonic receipt time and one real payload")
        return frame
    }

    @MainActor private static func exact(_ accumulator: LongCaptureFrameAccumulator, _ expected: CGImage, _ label: String) {
        do {
            guard let actual = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                check(false, "\(label): missing bitmap"); return
            }
            check(samePixels(actual, expected), label)
        } catch { check(false, "\(label): \(error)") }
    }

    @MainActor private static func incomplete(_ accumulator: LongCaptureFrameAccumulator, _ label: String) {
        do { _ = try accumulator.renderFinalImage(); check(false, label) }
        catch LongCaptureError.incompleteCapture { check(true, label) }
        catch { check(false, "\(label): unexpected \(error)") }
    }

    private static func check(_ condition: Bool, _ label: String) {
        guard condition else { print("FAIL: \(label)"); exit(1) }
        checks += 1
        print("PASS: \(label)")
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func document(offset: Int, width: Int = 480, height: Int = 480) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var hash = UInt32(truncatingIfNeeded: (y + offset) * 480 + x + 1)
                hash ^= hash >> 16; hash &*= 0x7feb352d; hash ^= hash >> 15
                hash &*= 0x846ca68b; hash ^= hash >> 16
                let value = UInt8(20 + hash % 210)
                let i = (y * width + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value
            }
        }
        return image(bytes, width: width, height: height)
    }

    private static func elastic(_ shift: Double, offset: Int = 0) -> CGImage {
        let source = document(offset: offset), rowBytes = source.width * 4
        let original = Array(source.dataProvider!.data! as Data)
        var bytes = [UInt8](repeating: 255, count: rowBytes * source.height)
        for y in 0..<source.height {
            let sourceY = Double(y) - shift, lower = Int(floor(sourceY)), upper = lower + 1
            let fraction = sourceY - floor(sourceY)
            for x in 0..<source.width {
                for channel in 0..<3 {
                    let a = (0..<source.height).contains(lower) ? Int(original[lower * rowBytes + x * 4 + channel]) : 255
                    let b = (0..<source.height).contains(upper) ? Int(original[upper * rowBytes + x * 4 + channel]) : 255
                    bytes[y * rowBytes + x * 4 + channel] = UInt8((Double(a) * (1 - fraction) + Double(b) * fraction).rounded())
                }
            }
        }
        return image(bytes, width: source.width, height: source.height)
    }

    private static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        a.width == b.width && a.height == b.height && canonicalBytes(a) == canonicalBytes(b)
    }

    private static func canonicalBytes(_ image: CGImage) -> Data {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes {
            let context = CGContext(data: $0.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Data(bytes)
    }
}
