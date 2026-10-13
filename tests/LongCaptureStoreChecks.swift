import AppKit
import Darwin
import Foundation

/// Store-only regression and independent memory experiments over generated
/// canonical pixels. No capture, clipboard, app, or private image access.
@main
struct LongCaptureStoreChecks {
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? "checks"
        if mode == "memory-old" || mode == "memory-bounded" {
            memoryExperiment(mode: mode)
            return
        }
        if mode.hasPrefix("overflow-") {
            overflowProbe(mode: mode)
            return
        }
        regressionChecks()
    }

    static func canonical(width: Int = 32, height: Int = 32, documentY: Int = 0) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let worldY = y + documentY
                bytes[i] = UInt8((x * 13 + worldY * 7) % 251)
                bytes[i + 1] = UInt8((x * 5 + worldY * 19) % 251)
                bytes[i + 2] = UInt8((x * 17 + worldY * 3) % 251)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func alteredRow(_ image: CGImage, row: Int) -> CGImage {
        var bytes = Array(image.dataProvider!.data! as Data)
        bytes[row * image.bytesPerRow] ^= 0x7F
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.bytesPerRow, space: image.colorSpace!,
                       bitmapInfo: image.bitmapInfo, provider: CGDataProvider(data: Data(bytes) as CFData)!,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func exact(_ a: CGImage?, _ b: CGImage) -> Bool {
        guard let a, a.width == b.width, a.height == b.height,
              a.bytesPerRow == b.bytesPerRow,
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data else { return false }
        return (ad as Data) == (bd as Data)
    }

    static func spoolDirectories() -> Set<URL> {
        Set((try? FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory,
                                                         includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("LibreShot-LongCapture-") } ?? [])
    }

    static func files(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    static func succeeds(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true } catch { return false }
    }

    static func rejects(_ expected: LongCaptureDocumentStoreError, _ operation: () throws -> Void) -> Bool {
        do { try operation(); return false }
        catch let error as LongCaptureDocumentStoreError { return error == expected }
        catch { return false }
    }

    static func regressionChecks() {
        var rows: [[String: Any]] = []
        func check(_ passed: Bool, _ label: String) {
            rows.append(["name": label, "passed": passed])
            print("\(passed ? "PASS" : "FAIL"): \(label)")
        }
        var limits = LongCaptureLimits()
        limits.residentDocumentBytes = 4096
        limits.maximumOutputBytes = 256 * 1024
        let beforeDirectories = spoolDirectories()
        var store: LongCaptureDocumentStore? = LongCaptureDocumentStore(limits: limits)
        for index in 0..<3 {
            check(succeeds { try store!.append(canonical(documentY: index * 32), at: index * 32) },
                  "append known canonical strip \(index)")
        }
        check(store!.residentBytes <= 4096 && store!.residentBytes + store!.spilledBytes == 12_288,
              "small budget bounds resident accounting while retaining all strip bytes")
        check(store!.count == 3 && store!.spilledBytes >= 8192, "small budget spills old strips")
        for index in 0..<3 {
            check(exact(store!.image(at: index), canonical(documentY: index * 32)),
                  "resident or spooled strip \(index) reloads exact pixels")
        }
        let ownDirectories = spoolDirectories().subtracting(beforeDirectories)
        check(ownDirectories.count == 1, "forced spill creates one isolated spool directory")
        let directory = ownDirectories.first
        if let directory {
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
            check((attributes?[.posixPermissions] as? NSNumber)?.intValue == 0o700,
                  "spool directory is private mode0700")
        }
        check(store!.image(at: -1) == nil && store!.image(at: 3) == nil,
              "invalid strip indexes return nil")

        let visible = canonical(height: 64, documentY: 16)
        check(store!.firstDifferentRow(from: visible, documentStart: 16, imageStart: 0, rowCount: 64) == -1,
              "partial-row equality spans spooled and resident strips without final bitmap")
        check(store!.firstDifferentRow(from: alteredRow(visible, row: 29), documentStart: 16, imageStart: 0, rowCount: 64) == 45,
              "partial-row comparison returns first differing global row")
        check(store!.firstDifferentRow(from: visible, documentStart: 16, imageStart: 1, rowCount: 64) == nil,
              "row window outside source rejects safely")
        check(store!.firstDifferentRow(from: visible, documentStart: -1, imageStart: 0, rowCount: 4) == nil,
              "negative document start rejects safely")
        check(store!.firstDifferentRow(from: visible, documentStart: 95, imageStart: 0, rowCount: 2) == nil,
              "partial-row coverage beyond stored document rejects safely")

        do {
            let rendered = try store!.render(height: 96)
            check(exact(rendered, canonical(height: 96)), "final render reads spooled strips and resident pixels losslessly once")
            let withFooter = try store!.render(height: 104, footer: canonical(height: 8, documentY: 96))
            check(exact(withFooter, canonical(height: 104)), "footer render places exactly one footer after complete document")
        } catch { check(false, "lossless renderer: \(error)") }
        check(rejects(.invalidPlacement) { _ = try store!.render(height: 95) } &&
              rejects(.invalidPlacement) { _ = try store!.render(height: 97) },
              "renderer rejects incomplete or excess document coverage")
        check(rejects(.invalidImage) { _ = try store!.render(height: 104, footer: canonical(width: 31, height: 8)) },
              "renderer rejects footer width mismatch")

        let oldCount = store!.count, oldResident = store!.residentBytes, oldSpilled = store!.spilledBytes
        check(rejects(.invalidPlacement) { try store!.append(canonical(), at: -1) }, "negative append placement is rejected")
        check(store!.count == oldCount && store!.residentBytes == oldResident && store!.spilledBytes == oldSpilled &&
              exact(store!.image(at: 0), canonical()),
              "rejected append preserves committed document and accounting")

        let geometry = LongCaptureDocumentStore(limits: limits)
        try! geometry.append(canonical(), at: 0)
        check(rejects(.invalidPlacement) { try geometry.append(canonical(width: 31, documentY: 32), at: 32) },
              "mixed-width append rejects incompatible document geometry")
        check(rejects(.invalidPlacement) { try geometry.append(canonical(documentY: 16), at: 16) },
              "overlapping append rejects incompatible document geometry")
        check(rejects(.invalidPlacement) { try geometry.replace(with: [
            .init(image: canonical(documentY: 32), yOffset: 32),
            .init(image: canonical(), yOffset: 0)
        ]) }, "unordered replacement rejects invalid geometry")
        check(rejects(.invalidPlacement) { try geometry.replace(with: [
            .init(image: canonical(), yOffset: 0),
            .init(image: canonical(documentY: 16), yOffset: 16)
        ]) }, "overlapping replacement rejects invalid geometry")
        check(rejects(.invalidPlacement) { try geometry.append(canonical(documentY: 40), at: 40) },
              "append rejects a gap beyond accepted frontier")
        check(rejects(.invalidPlacement) { try geometry.replace(with: [
            .init(image: canonical(), yOffset: 0), .init(image: canonical(documentY: 40), yOffset: 40)
        ]) }, "replacement rejects document gap")
        let firstOffset = LongCaptureDocumentStore(limits: limits)
        check(rejects(.invalidPlacement) { try firstOffset.append(canonical(), at: 1) },
              "first strip must start at global row zero")
        for dataLength in [4095, 4097] {
            let malformed = CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: CGDataProvider(data: Data(repeating: 255, count: dataLength) as CFData)!,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            if let malformed {
                let invalidStore = LongCaptureDocumentStore(limits: limits)
                check(rejects(.invalidImage) { try invalidStore.append(malformed, at: 0) } && invalidStore.count == 0,
                      "provider length \(dataLength) rejects without committing or reading beyond bytes")
                check(store!.firstDifferentRow(from: malformed, documentStart: 0, imageStart: 0, rowCount: 32) == nil,
                      "partial-row comparison rejects noncanonical provider length \(dataLength)")
            } else { check(true, "CoreGraphics itself rejects provider length \(dataLength)") }
        }
        check(geometry.count == 1 && exact(geometry.image(at: 0), canonical()),
              "rejected geometry preserves original committed strip")

        var frameLimit = limits
        frameLimit.maximumFrameBytes = 4096
        let frameStore = LongCaptureDocumentStore(limits: frameLimit)
        check(rejects(.frameLimit) { try frameStore.append(canonical(height: 33), at: 0) },
              "strip allocation above maximumFrameBytes rejects safely")

        var segmentLimit = limits
        segmentLimit.maximumSegments = 1
        let capped = LongCaptureDocumentStore(limits: segmentLimit)
        check(succeeds { try capped.append(canonical(), at: 0) } && rejects(.segmentLimit) { try capped.append(canonical(documentY: 32), at: 32) } && capped.count == 1,
              "segment limit rejects extra append without losing first commit")

        let defaults = LongCaptureDocumentStore()
        check(defaults.limits.residentDocumentBytes == 32 * 1024 * 1024 &&
              defaults.limits.maximumOutputBytes == 128 * 1024 * 1024,
              "default document and final-render budgets are32MiB and128MiB")
        check(defaults.permits(width: 1024, height: 32768) &&
              !defaults.permits(width: 1024, height: 32769),
              "final-render byte geometry accepts exact cap and rejects one extra row")
        check(!defaults.permits(width: 0, height: 1) && !defaults.permits(width: 1, height: 0) &&
              !defaults.permits(width: -1, height: 1) && !defaults.permits(width: Int.max, height: 2),
              "invalid and overflow-prone dimensions reject safely")

        var invalidLimits = limits
        invalidLimits.residentDocumentBytes = -1
        let invalidConfiguration = LongCaptureDocumentStore(limits: invalidLimits)
        check(!invalidConfiguration.permits(width: 1, height: 1) &&
              rejects(.invalidLimits) { try invalidConfiguration.append(canonical(), at: 0) },
              "invalid configuration rejects without allocation")
        var outputLimits = limits
        outputLimits.maximumOutputBytes = 4096
        let outputCapped = LongCaptureDocumentStore(limits: outputLimits)
        try! outputCapped.append(canonical(), at: 0)
        check(rejects(.outputLimit) { try outputCapped.append(canonical(height: 1, documentY: 32), at: 32) } &&
              outputCapped.totalHeight == 32 && exact(outputCapped.image(at: 0), canonical()),
              "output resource limit preserves committed height and pixels")

        if let directory {
            if let diskName = files(in: directory).first {
                let file = directory.appendingPathComponent(diskName)
                do {
                    let original = try Data(contentsOf: file)
                    try original.dropLast().write(to: file, options: .atomic)
                    check(rejects(.storageFailure) { _ = try store!.render(height: 96) },
                          "truncated spool fails final render instead of silently returning partial image")
                    check(store!.firstDifferentRow(from: canonical(height: 96), documentStart: 0, imageStart: 0, rowCount: 96) == nil,
                          "truncated spool fails covered row read safely")
                    try original.write(to: file, options: .atomic)
                    check(exact(try? store!.render(height: 96), canonical(height: 96)),
                          "restored spool bytes recover exact committed document")
                } catch { check(false, "truncated spool injection: \(error)") }
            }
            let fileNames = files(in: directory)
            // Restrict mutation to the directory created by this test; restore its
            // mode before inspecting the old committed file data.
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
                let failedWrite = rejects(.storageFailure) { try store!.append(canonical(documentY: 96), at: 96) }
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                check(failedWrite, "spool write failure rejects append")
                check(store!.count == oldCount && store!.residentBytes == oldResident && store!.spilledBytes == oldSpilled &&
                      files(in: directory) == fileNames && exact(store!.image(at: 0), canonical()),
                      "failed spool transaction preserves committed pixels and cleans staged files")
            } catch {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                check(false, "spool failure injection setup: \(error)")
            }
            check(succeeds { try store!.replace(with: [.init(image: canonical(height: 16), yOffset: 0)]) },
                  "replacement commits new known document")
            check(store!.count == 1 && store!.residentBytes == 2048 && store!.spilledBytes == 0 &&
                  files(in: directory).isEmpty && exact(store!.image(at: 0), canonical(height: 16)),
                  "replacement removes obsolete spool files and resets exact accounting")
            check(succeeds { try store!.replace(with: []) } && store!.count == 0 && store!.residentBytes == 0 && store!.spilledBytes == 0,
                  "empty replacement clears committed document")
        }
        store = nil
        check(ownDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
              "store deinit removes its own spool directory")
        let beforeLiveSpool = spoolDirectories()
        var allDiskLimits = limits
        allDiskLimits.residentDocumentBytes = 0
        var liveSpool: LongCaptureDocumentStore? = LongCaptureDocumentStore(limits: allDiskLimits)
        check(succeeds { try liveSpool!.append(canonical(), at: 0) } && liveSpool!.residentBytes == 0 &&
              liveSpool!.spilledBytes == 4096, "zero resident budget preserves lossless document entirely on disk")
        let liveDirectories = spoolDirectories().subtracting(beforeLiveSpool)
        check(liveDirectories.count == 1 && liveDirectories.allSatisfy { !files(in: $0).isEmpty },
              "live deinit fixture contains real spool files")
        liveSpool = nil
        check(liveDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) },
              "deinit without explicit replacement removes live spool files and directory")
        withExtendedLifetime(geometry) {}

        let failed = rows.filter { ($0["passed"] as? Bool) == false }.count
        write(["suite": "LongCaptureStoreChecks", "assertions": rows.count, "passed": rows.count - failed,
               "failed": failed, "results": rows], environmentKey: "LIBRESHOT_STORE_QA_OUTPUT")
        print("RESULT: \(rows.count - failed)/\(rows.count) passed; \(failed) failures")
        if failed > 0 { exit(1) }
    }

    static func overflowProbe(mode: String) {
        let store = LongCaptureDocumentStore()
        let source = canonical()
        let safe: Bool
        switch mode {
        case "overflow-append":
            safe = rejects(.invalidPlacement) { try store.append(source, at: Int.max) }
        case "overflow-image-window":
            safe = store.firstDifferentRow(from: source, documentStart: 0, imageStart: Int.max, rowCount: 32) == nil
        case "overflow-document-window":
            safe = store.firstDifferentRow(from: source, documentStart: Int.max, imageStart: 0, rowCount: 32) == nil
        default:
            safe = false
        }
        print("\(safe ? "PASS" : "FAIL"): \(mode) rejects overflow without trap")
        if !safe { exit(1) }
    }

    static func footprint() -> (current: UInt64, lifetimePeak: Int64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(status == KERN_SUCCESS)
        return (info.phys_footprint, info.ledger_phys_footprint_peak)
    }

    static func memoryExperiment(mode: String) {
        let width = 640, height = 256, checkpoints = Set([0, 20, 50, 100, 200])
        var samples: [[String: Any]] = []
        var inMemory: [CGImage] = []
        let store = LongCaptureDocumentStore()
        func sample(_ count: Int) {
            let memory = footprint()
            let retained = inMemory.reduce(0) { $0 + $1.bytesPerRow * $1.height }
            samples.append(["segment_count": count, "physical_footprint_bytes": memory.current,
                            "lifetime_physical_peak_bytes": memory.lifetimePeak,
                            "retained_inmemory_pixel_bytes": retained,
                            "store_resident_pixel_bytes": store.residentBytes,
                            "store_spilled_disk_bytes": store.spilledBytes,
                            "document_known_pixel_bytes": count * width * height * 4])
            print("MEMORY,\(mode),segments=\(count),physicalMiB=\(Double(memory.current) / 1048576),lifetimePeakMiB=\(Double(memory.lifetimePeak) / 1048576),residentBytes=\(store.residentBytes),diskBytes=\(store.spilledBytes)")
            fflush(stdout)
        }
        sample(0)
        for index in 0..<200 {
            autoreleasepool {
                // Every channel of every pixel is written before it is retained,
                // so reserve-only virtual allocations cannot fake the comparison.
                let pixels = canonical(width: width, height: height, documentY: index * height)
                if mode == "memory-old" { inMemory.append(pixels) }
                else { try! store.append(pixels, at: index * height) }
            }
            if checkpoints.contains(index + 1) { sample(index + 1) }
        }
        write(["experiment": "independent process old-inmemory vs bounded store",
               "mode": mode, "pid": ProcessInfo.processInfo.processIdentifier,
               "width": width, "strip_height": height, "samples": samples,
               "measure": "task_vm_info physical footprint and kernel lifetime footprint peak",
               "limits": "generated touched pixels; no final bitmap; disk/mapping accounting is not RAM"],
              environmentKey: "LIBRESHOT_STORE_MEMORY_OUTPUT")
        withExtendedLifetime(inMemory) {}
        withExtendedLifetime(store) {}
    }

    static func write(_ report: [String: Any], environmentKey: String) {
        guard let path = ProcessInfo.processInfo.environment[environmentKey] else { return }
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch { print("FAIL: evidence write \(error)"); exit(1) }
    }
}

