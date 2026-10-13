import AppKit
import Darwin
import ImageIO

@main struct PinnedImageMemoryChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        if let mode = CommandLine.arguments.dropFirst().first {
            try await profile(mode)
            return
        }
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL"): \(message)")
            if !value { failures += 1 }
        }
        let suite = "LibreShot.PinnedChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        settings.useRoundedCorners = true
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let service = AlreadyStyledExportService(settings: settings, pasteboard: board)
        for space in [CGColorSpace(name: CGColorSpace.sRGB)!, CGColorSpace(name: CGColorSpace.displayP3)!] {
            let source = colorImage(space: space)
            let expected = rgbaPixels(source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            let controller = PinnedImageWindowController(image: source, exportService: service)
            controller.handleCopy()
            check(board.pasteboardItems?.count == 1, "pinned copy keeps one image item")
            let png = board.data(forType: .png)
            let tiff = board.data(forType: .tiff)
            check(png != nil && tiff != nil, "pinned copy immediately provides PNG and TIFF")
            check(png.map { rgbaPixels(NSBitmapImageRep(data: $0)!.cgImage!) } == expected,
                  "pinned PNG preserves normalized color and alpha pixels")
            check(tiff.map { rgbaPixels(NSBitmapImageRep(data: $0)!.cgImage!) } == expected,
                  "pinned lossless TIFF agrees with PNG pixels")
            check(tiff.map { tiffCompression($0) } == 5, "pinned TIFF uses lossless LZW compression")
            let saved = controller.pngDataForSave()
            check(saved.map { rgbaPixels(NSBitmapImageRep(data: $0)!.cgImage!) } == expected,
                  "pinned save uses the same pixels as copy")
            check(saved.map { NSBitmapImageRep(data: $0)!.size } == source.size,
                  "pinned save preserves Retina logical size")
            controller.close()
            check(controller.pngDataForSave() == nil, "closed pinned window cannot export an old image")
            check(controller.window?.contentView == nil, "closed pinned window releases its hosting view")
        }

        // Exercise the actual default exporter: the input is already styled by its caller.
        // A second rounded-corner pass would remove these visible square corner pixels.
        let source = colorImage(space: CGColorSpace(name: CGColorSpace.sRGB)!)
        let controller = PinnedImageWindowController(image: source)
        check(controller.pngDataForSave().map { rgbaPixels(NSBitmapImageRep(data: $0)!.cgImage!) }
              == rgbaPixels(source.cgImage(forProposedRect: nil, context: nil, hints: nil)!),
              "default pinned exporter does not apply the outline again")
        controller.close()

        for nativeClose in [false, true] {
            let retained = autoreleasepool { () -> (PinnedImageWindowController, WeakImage, WeakToken) in
                let image = colorImage(space: CGColorSpace(name: CGColorSpace.sRGB)!)
                let token = CallbackToken()
                let controller = PinnedImageWindowController(image: image,
                    onCopyAction: { _ = token }, onSaveAction: { _ = token },
                    onSaveAsAction: { _ = token }, onEditAction: { _ = token })
                return (controller, WeakImage(image), WeakToken(token))
            }
            var closed = 0
            retained.0.onClose = { closed += 1 }
            autoreleasepool {
                if nativeClose { retained.0.window?.close() } else { retained.0.close() }
            }
            try await Task.sleep(for: .milliseconds(50))
            check(retained.1.value == nil, "\(nativeClose ? "native" : "controller") close releases source NSImage with controller retained")
            check(retained.2.value == nil, "\(nativeClose ? "native" : "controller") close releases export and edit callbacks")
            check(closed == 1, "close completion runs once")
            retained.0.close()
            check(closed == 1, "repeated close is idempotent")
        }

        // Closing a long-preview must release callbacks, but a selected save action
        // still runs once after close. Copy callbacks similarly retain their old order.
        var copied = 0
        let preview = PinnedImageWindowController(image: source, displayMode: .longCapturePreview,
                                                  onCopyAction: { copied += 1 })
        preview.handleCopy()
        check(copied == 1 && preview.window?.contentView == nil, "long-preview copy callback runs once and closes")
        preview.handleCopy()
        check(copied == 1, "closed preview cannot invoke a released copy callback")
        for saveAs in [false, true] {
            var didClose = false
            var savedAfterClose = false
            let preview = PinnedImageWindowController(image: source, displayMode: .longCapturePreview,
                onSaveAction: { savedAfterClose = didClose }, onSaveAsAction: { savedAfterClose = didClose })
            preview.onClose = { didClose = true }
            if saveAs { preview.handleSaveAs() } else { preview.handleSave() }
            check(didClose, "long-preview \(saveAs ? "save-as" : "save") closes before dispatching its action")
            try await Task.sleep(for: .milliseconds(50))
            check(savedAfterClose, "long-preview \(saveAs ? "save-as" : "save") retains the selected action through teardown")
        }
        if failures > 0 { exit(1) }
    }

    @MainActor private static func profile(_ mode: String) async throws {
        precondition(["old-save", "new-save", "new-copy"].contains(mode))
        let suite = "LibreShot.PinnedProfile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let service = AlreadyStyledExportService(settings: SettingsService(defaults: defaults), pasteboard: board)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        report(mode, "baseline")
        let image = noiseImage()
        let controller = PinnedImageWindowController(image: image, exportService: service)
        report(mode, "fixture-and-window-ready")
        for batch in 1...3 {
            for operation in 1...10 {
                autoreleasepool {
                    if mode == "old-save" {
                        // Preserve the exact pre-fix pinned-save encoder as an A/B control.
                        let tiff = image.tiffRepresentation!
                        let bitmap = NSBitmapImageRep(data: tiff)!
                        let png = bitmap.representation(using: .png, properties: [:])!
                        try! png.write(to: directory.appendingPathComponent("\(batch)-\(operation).png"))
                    } else if mode == "new-save" {
                        try! controller.pngDataForSave()!.write(to: directory.appendingPathComponent("\(batch)-\(operation).png"))
                    } else {
                        controller.handleCopy()
                    }
                }
            }
            report(mode, "batch_\(batch)_operations")
            try await Task.sleep(for: .seconds(15))
            report(mode, "batch_\(batch)_idle15")
        }
        controller.close()
        if mode == "new-copy" { precondition(board.data(forType: .png) != nil && board.data(forType: .tiff) != nil) }
    }

    private static func colorImage(space: CGColorSpace) -> NSImage {
        let width = 64, height = 40
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y*width+x)*4
                let alpha: UInt8 = x == 0 && y == 0 ? 0 : ((x+y)%5 == 0 ? 128 : 255)
                bytes[i] = UInt8(x*3*Int(alpha)/255)
                bytes[i+1] = UInt8(y*5*Int(alpha)/255)
                bytes[i+2] = UInt8(70*Int(alpha)/255)
                bytes[i+3] = alpha
            }
        }
        return image(width: width, height: height, bytes: bytes, space: space)
    }

    private static func noiseImage() -> NSImage {
        let width = 2400, height = 1400
        var bytes = [UInt8](repeating: 255, count: width*height*4)
        var seed: UInt32 = 0x1022026
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for c in 0..<3 { seed = seed &* 1664525 &+ 1013904223; bytes[i+c] = UInt8(truncatingIfNeeded: seed >> 24) }
        }
        return image(width: width, height: height, bytes: bytes, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    private static func image(width: Int, height: Int, bytes: [UInt8], space: CGColorSpace) -> NSImage {
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: width*4, space: space,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                         shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: width/2, height: height/2))
    }

    private static func rgbaPixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: context.bytesPerRow*image.height)
    }

    private static func tiffCompression(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] else { return nil }
        return (tiff[kCGImagePropertyTIFFCompression as String] as? NSNumber)?.intValue
    }

    private static func report(_ mode: String, _ stage: String) {
        var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        } }
        precondition(result == KERN_SUCCESS)
        print("SAMPLE,\(mode),\(stage),\(String(format: "%.3f", Double(info.phys_footprint) / 1048576))")
        fflush(stdout)
    }
}

private final class AlreadyStyledExportService: CaptureService {
    override func styledImage(_ image: NSImage) -> NSImage { image }
}
private final class CallbackToken {}
private final class WeakImage { weak var value: NSImage?; init(_ value: NSImage) { self.value = value } }
private final class WeakToken { weak var value: CallbackToken?; init(_ value: CallbackToken) { self.value = value } }
