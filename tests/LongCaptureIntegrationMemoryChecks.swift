import AppKit
import Foundation

/// Engine-level memory/lifecycle checks using only generated public RGBA pixels.
/// A spill budget bounds document strips, not the final bitmap or process RSS.
@main
struct LongCaptureIntegrationMemoryChecks {
    final class ProviderTracker {
        var releases: [Int: Int] = [:]
        func released(_ id: Int) { releases[id, default: 0] += 1 }
    }

    final class ProviderOwnership {
        let id: Int
        let tracker: ProviderTracker
        init(id: Int, tracker: ProviderTracker) { self.id = id; self.tracker = tracker }
    }

    static func main() {
        var results: [[String: Any]] = []
        func check(_ condition: Bool, _ label: String) {
            results.append(["name": label, "passed": condition])
            print("\(condition ? "PASS" : "FAIL"): \(label)")
        }
        @discardableResult
        func feed(_ accumulator: LongCaptureFrameAccumulator, offset: Int, index: Int,
                  height: Int = 480) -> LongCaptureProgress? {
            autoreleasepool {
                accumulator.process(frame: .init(image: document(offset: offset, height: height),
                                                  timestamp: Double(index) / 10))
            }
        }
        func exact(_ accumulator: LongCaptureFrameAccumulator, height: Int, _ label: String) {
            do {
                let actual = try accumulator.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)
                check(actual.map { samePixels($0, document(offset: 0, height: height)) } ?? false, label)
            } catch { check(false, "\(label): \(error.localizedDescription)") }
        }
        func resourceError(_ accumulator: LongCaptureFrameAccumulator, _ label: String) {
            do { _ = try accumulator.renderFinalImage(); check(false, label) }
            catch LongCaptureError.resourceLimit { check(true, label) }
            catch { check(false, "\(label): unexpected \(error.localizedDescription)") }
        }

        // Force every strip onto disk through the real accumulator. Exact final
        // pixels prove that spilling and mapping preserve coverage and ordering.
        var spillLimits = LongCaptureLimits()
        spillLimits.residentDocumentBytes = 0
        spillLimits.maximumOutputBytes = 4 * 1024 * 1024
        let directoriesBefore = spoolDirectories()
        var spilling: LongCaptureFrameAccumulator? = LongCaptureFrameAccumulator(limits: spillLimits)
        for (index, offset) in [0, 72, 144, 216].enumerated() {
            let progress = feed(spilling!, offset: offset, index: index)
            check(progress?.warning == nil && progress?.acceptedFrameCount == index + 1 &&
                  progress?.appendedPixelHeight == 480 + offset,
                  "forced-spill engine accepts exact offset \(offset)")
        }
        let ownedDirectories = spoolDirectories().subtracting(directoriesBefore)
        let ownedFiles = ownedDirectories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "rgba" }
        let storedBytes = ownedFiles.reduce(0) { total, file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            return total + ((attributes?[.size] as? NSNumber)?.intValue ?? 0)
        }
        check(ownedDirectories.count == 1 && ownedFiles.count == 4 && storedBytes == 480 * 696 * 4,
              "forced-spill creates lossless strips containing the complete document")
        check(ownedDirectories.allSatisfy {
            let attributes = try? FileManager.default.attributesOfItem(atPath: $0.path)
            return (attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700
        }, "engine spill directory is accessible only by its owner")
        exact(spilling!, height: 696, "forced-spill final image has exact dimensions and every original pixel")
        spilling = nil
        check(ownedDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
              "releasing the engine removes only its own spill directory")

        // Each input provider has independent malloc storage and a release
        // callback. No retained source crop may keep older screen buffers alive.
        let tracker = ProviderTracker()
        var lifecycle: LongCaptureFrameAccumulator? = LongCaptureFrameAccumulator(limits: spillLimits)
        for (index, offset) in [0, 72, 144, 216].enumerated() {
            let progress = autoreleasepool {
                lifecycle!.process(frame: .init(image: trackedDocument(offset: offset, id: index, tracker: tracker),
                                                timestamp: Double(index) / 10))
            }
            check(progress?.warning == nil && progress?.acceptedFrameCount == index + 1,
                  "tracked raw provider frame \(index) is accepted")
            check(tracker.releases == Dictionary(uniqueKeysWithValues: (0..<index).map { ($0, 1) }),
                  "after frontier \(index), every older raw provider is released exactly once")
        }
        exact(lifecycle!, height: 696, "released raw providers do not affect final lossless rendering")
        lifecycle = nil
        check(tracker.releases == [0: 1, 1: 1, 2: 1, 3: 1],
              "releasing accumulator releases the final raw provider exactly once")

        // Failed append transactions must remain failures when the same frame
        // repeats. Only returning to the exact accepted frontier restores export.
        var outputLimits = LongCaptureLimits()
        outputLimits.maximumOutputBytes = 480 * 512 * 4
        let output = LongCaptureFrameAccumulator(limits: outputLimits)
        _ = feed(output, offset: 0, index: 0)
        for index in 1...2 {
            let failed = feed(output, offset: 120, index: index)
            check(failed?.warning != nil && failed?.acceptedFrameCount == 1 && failed?.appendedPixelHeight == 480,
                  "output-limit retry \(index) preserves the accepted frontier")
            resourceError(output, "output-limit retry \(index) cannot silently export a successful prefix")
        }
        let outputRecovery = feed(output, offset: 0, index: 3)
        check(outputRecovery?.warning == nil, "exact frontier return clears the output-limit warning")
        let smaller = feed(output, offset: 16, index: 4)
        check(smaller?.warning == nil && smaller?.appendedPixelHeight == 496,
              "a smaller append after output-limit recovery remains usable")
        exact(output, height: 496, "output-limit recovery exports the complete smaller document")

        var frameLimits = LongCaptureLimits()
        frameLimits.maximumFrameBytes = 480 * 480 * 4
        let frameLimited = LongCaptureFrameAccumulator(limits: frameLimits)
        _ = feed(frameLimited, offset: 0, index: 0)
        for index in 1...2 {
            let failed = feed(frameLimited, offset: 72, index: index, height: 481)
            check(failed?.warning != nil && failed?.acceptedFrameCount == 1 && failed?.appendedPixelHeight == 480,
                  "oversized-frame retry \(index) leaves committed pixels unchanged")
            resourceError(frameLimited, "oversized-frame retry \(index) never silently exports the prefix")
        }
        _ = feed(frameLimited, offset: 0, index: 3)
        let validFrame = feed(frameLimited, offset: 72, index: 4)
        check(validFrame?.warning == nil && validFrame?.appendedPixelHeight == 552,
              "valid frame can continue after returning from a frame-limit failure")
        exact(frameLimited, height: 552, "frame-limit recovery retains every accepted pixel")
        frameLimits.maximumFrameBytes -= 1
        let initialFrameLimited = LongCaptureFrameAccumulator(limits: frameLimits)
        let initialFailure = feed(initialFrameLimited, offset: 0, index: 0)
        check(initialFailure?.warning != nil && initialFailure?.acceptedFrameCount == 0 &&
              initialFailure?.appendedPixelHeight == 0, "initial oversized frame commits no document")
        resourceError(initialFrameLimited, "initial oversized frame reports the resource error")

        var segmentLimits = LongCaptureLimits()
        segmentLimits.maximumSegments = 2
        let segmented = LongCaptureFrameAccumulator(limits: segmentLimits)
        _ = feed(segmented, offset: 0, index: 0)
        _ = feed(segmented, offset: 72, index: 1)
        for index in 2...3 {
            let failed = feed(segmented, offset: 144, index: index)
            check(failed?.warning != nil && failed?.acceptedFrameCount == 2 && failed?.appendedPixelHeight == 552,
                  "segment-limit retry \(index) preserves accepted coverage")
            resourceError(segmented, "segment-limit retry \(index) refuses a silent prefix")
        }
        let segmentRecovery = feed(segmented, offset: 72, index: 4)
        check(segmentRecovery?.warning == nil, "exact frontier return clears the segment-limit warning")
        exact(segmented, height: 552, "segment-limit recovery exports exactly the verified frontier")
        _ = feed(segmented, offset: 144, index: 5)
        resourceError(segmented, "frontier recovery never bypasses the segment limit")

        let failures = results.filter { ($0["passed"] as? Bool) == false }.count
        let report: [String: Any] = [
            "suite": "LongCaptureIntegrationMemoryChecks", "assertions": results.count,
            "passed": results.count - failures, "failed": failures, "results": results,
            "scope": "offline generated public pixels; no app, desktop, clipboard, or private images",
            "memory_evidence": "raw provider release callbacks and forced disk spill; does not measure full-app physical footprint",
            "forced_spill_bytes": storedBytes,
        ]
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_INTEGRATION_MEMORY_QA_OUTPUT"] {
            do {
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                    .write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch { print("FAIL: write QA evidence: \(error)"); exit(1) }
        }
        print("RESULT: \(results.count - failures)/\(results.count) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    static func spoolDirectories() -> Set<URL> {
        Set(((try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                                                          includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("LibreShot-LongCapture-") })
    }

    static func value(x: Int, y: Int) -> UInt8 {
        var bits = UInt32(truncatingIfNeeded: y * 480 + x + 1)
        bits ^= bits >> 16; bits &*= 0x7feb352d; bits ^= bits >> 15
        bits &*= 0x846ca68b; bits ^= bits >> 16
        return UInt8(20 + bits % 210)
    }

    static func pixels(offset: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: 480 * height * 4)
        for y in 0..<height { for x in 0..<480 {
            let v = value(x: x, y: y + offset), i = (y * 480 + x) * 4
            pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
        } }
        return pixels
    }

    static func image(provider: CGDataProvider, height: Int) -> CGImage {
        CGImage(width: 480, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 480 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func document(offset: Int, height: Int = 480) -> CGImage {
        image(provider: CGDataProvider(data: Data(pixels(offset: offset, height: height)) as CFData)!, height: height)
    }

    static func trackedDocument(offset: Int, id: Int, tracker: ProviderTracker) -> CGImage {
        let pixels = pixels(offset: offset, height: 480)
        let allocation = malloc(pixels.count)!
        _ = pixels.withUnsafeBytes { memcpy(allocation, $0.baseAddress!, pixels.count) }
        let info = Unmanaged.passRetained(ProviderOwnership(id: id, tracker: tracker)).toOpaque()
        let provider = CGDataProvider(dataInfo: info, data: allocation, size: pixels.count) { info, data, _ in
            let ownership = Unmanaged<ProviderOwnership>.fromOpaque(info!).takeRetainedValue()
            ownership.tracker.released(ownership.id)
            free(UnsafeMutableRawPointer(mutating: data))
        }!
        return image(provider: provider, height: 480)
    }

    static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              a.bitsPerComponent == b.bitsPerComponent, a.bitsPerPixel == b.bitsPerPixel,
              a.bitmapInfo == b.bitmapInfo, let ad = a.dataProvider?.data,
              let bd = b.dataProvider?.data, let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
        for y in 0..<a.height {
            if memcmp(ap + y * a.bytesPerRow, bp + y * b.bytesPerRow, a.width * 4) != 0 { return false }
        }
        return true
    }
}
