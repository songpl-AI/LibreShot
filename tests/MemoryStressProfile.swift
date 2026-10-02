import AppKit
import Darwin

/// Repeated production operations with isolated defaults and a private pasteboard.
/// The review threshold detects substantial retained growth after the first batch;
/// staying below it is not proof that the process has no leaks or meets a footprint target.
@main struct MemoryStressProfile {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let scenario = CommandLine.arguments.dropFirst().first ?? "editor-copy"
        precondition(["editor-copy", "ocr", "copy-only", "editor-only", "render-only", "png-only", "png-copy", "tiff-only", "bitmap-tiff-only", "lzw-tiff-only"].contains(scenario))
        let batches = Int(ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_BATCHES"] ?? "5")!
        precondition(batches >= 3 && batches <= 20)
        let idle = Int(ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_IDLE"] ?? "60")!
        precondition(idle == 15 || idle == 60)
        let suite = "LibreShot.MemoryStress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let service = CaptureService(settings: settings, pasteboard: board)
        report(scenario, "baseline")
        let image: NSImage
        if ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_FIXTURE"] == "noise" {
            image = noiseImage()
        } else {
            image = textImage()
        }
        report(scenario, "fixture_\(Int(image.size.width))x\(Int(image.size.height))_points")
        var settled: [Double] = []
        let perBatch = scenario == "ocr" ? 5 : 10
        for batch in 1...batches {
            for _ in 0..<perBatch {
                if scenario == "ocr" {
                    let text = try await OCRService.shared.recognizeText(from: image)
                    precondition(!text.isEmpty, "Actual Vision recognition must succeed")
                } else {
                    autoreleasepool {
                        if ["png-only", "png-copy", "tiff-only", "bitmap-tiff-only", "lzw-tiff-only"].contains(scenario) {
                            let png = service.pngData(from: image)!
                            if scenario == "png-copy" { board.clearContents(); board.setData(png, forType: .png) }
                            if scenario == "tiff-only" {
                                precondition(NSImage(data: png)!.tiffRepresentation != nil)
                            }
                            if scenario == "bitmap-tiff-only" {
                                precondition(NSBitmapImageRep(data: png)!.representation(using: .tiff, properties: [:]) != nil)
                            }
                            if scenario == "lzw-tiff-only" {
                                precondition(NSBitmapImageRep(data: png)!.representation(using: .tiff,
                                    properties: [.compressionMethod: NSNumber(value: NSBitmapImageRep.TIFFCompression.lzw.rawValue)]) != nil)
                            }
                        } else if scenario == "copy-only" {
                            service.copyToClipboard(image)
                        } else {
                            let editor = ImageEditorWindowController(image: image, settings: settings)
                            if scenario == "editor-copy" { service.copyToClipboard(editor.renderedImage()) }
                            if scenario == "render-only" { _ = editor.renderedImage() }
                            editor.close()
                            precondition(editor.window?.contentView == nil)
                            precondition(editor.model.previewImage == nil)
                            precondition(editor.model.annotations.isEmpty)
                        }
                    }
                }
            }
            report(scenario, "batch_\(batch)_operations_\(batch * perBatch)")
            var previous = 0
            for seconds in [1, 5, 15, 60].filter({ $0 <= idle }) {
                try await Task.sleep(for: .seconds(seconds - previous))
                let value = report(scenario, "batch_\(batch)_idle_\(seconds)s")
                if seconds == idle { settled.append(value) }
                previous = seconds
            }
        }
        let final = report(scenario, "final_idle_\(idle)s")
        if scenario == "editor-copy" || scenario == "copy-only" {
            precondition(board.data(forType: .png) != nil, "Private clipboard survives all idle intervals")
        }
        let delta = final - settled[0]
        print("RESULT \(scenario): first_batch_idle\(idle)=\(settled[0]), final_idle\(idle)=\(final), retained_delta=\(delta) MiB; batches=\(settled)")
        if ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_PRESSURE_RELIEF"] == "1" {
            let relieved = malloc_zone_pressure_relief(nil, 0)
            print("DIAGNOSTIC: allocator pressure relief returned \(relieved) bytes; production does not call this")
            try await Task.sleep(for: .seconds(1))
            report(scenario, "diagnostic_allocator_relief")
            if scenario == "copy-only" || scenario == "editor-copy" {
                precondition(board.data(forType: .png) != nil && board.data(forType: .tiff) != nil)
            }
        }
        // An investigative alarm, not a universal product acceptance target.
        if delta > 32 {
            print("REVIEW: retained growth exceeded 32 MiB after warm-up; investigate before calling stable")
            exit(2)
        }
        print("COMPLETE: \(batches * perBatch) actual operations; 32 MiB retained-growth review threshold not exceeded")
    }

    @MainActor private static func textImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 1200, height: 700))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1200, height: 700).fill()
        for row in 0..<15 {
            ("Memory fixture \(row) - screenshot editor lifecycle" as NSString).draw(
                at: CGPoint(x: 30, y: row * 40 + 20),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        return image
    }

    private static func noiseImage() -> NSImage {
        let width = 2400, height = 1400
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 0x1022026
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1664525 &+ 1013904223
                pixels[index + channel] = UInt8(truncatingIfNeeded: seed >> 24)
            }
        }
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                         shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: 1200, height: 700))
    }

    @discardableResult private static func report(_ scenario: String, _ stage: String) -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        let mib = Double(info.phys_footprint) / 1048576
        print("SAMPLE,\(Date().timeIntervalSince1970),\(getpid()),\(scenario),\(stage),\(String(format: "%.3f", mib))")
        fflush(stdout)
        return mib
    }
}

