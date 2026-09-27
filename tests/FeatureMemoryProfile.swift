import AppKit
import Darwin
import Translation

@main
struct FeatureMemoryProfile {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let scenario = CommandLine.arguments.dropFirst().first ?? "ocr"
        report("\(scenario) baseline")

        switch scenario {
        case "ocr":
            try await runOCR()
        case "translation":
            if #available(macOS 26.0, *) { try await runTranslation() }
            else { fatalError("Translation requires macOS 26") }
        case "image-translation":
            if #available(macOS 26.0, *) { try await runImageTranslation() }
            else { fatalError("Translation requires macOS 26") }
        case "translation-window":
            if #available(macOS 26.0, *) { runTranslationWindow() }
            else { fatalError("Translation requires macOS 26") }
        case "translation-window-loop":
            if #available(macOS 26.0, *) { runTranslationWindowLoop() }
            else { fatalError("Translation requires macOS 26") }
        case "image-render":
            try runImageRender()
        case "long":
            runLongCaptureStitcher()
        default:
            fatalError("Unknown scenario: \(scenario)")
        }

        report("\(scenario) scope released")
        try await sampleIdle(scenario)
    }

    @MainActor private static func runOCR() async throws {
        let image = textImage()
        report("ocr fixture ready")
        for iteration in 1...5 {
            let text = try await OCRService.shared.recognizeText(from: image)
            precondition(!text.isEmpty)
            if iteration == 1 || iteration == 5 { report("ocr x\(iteration)") }
        }
    }

    @available(macOS 26.0, *)
    @MainActor private static func runTranslation() async throws {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            print("SKIP: English to Simplified Chinese model is not installed")
            return
        }
        let session = TranslationSession(installedSource: source, target: target)
        let paragraph = String(repeating: "Create an issue with a title, description and assigned user. ", count: 12)
        for iteration in 1...3 {
            let response = try await session.translate(paragraph)
            precondition(!response.targetText.isEmpty)
            report("translation x\(iteration)")
        }
    }

    @available(macOS 26.0, *)
    @MainActor private static func runImageTranslation() async throws {
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            print("SKIP: English to Simplified Chinese model is not installed")
            return
        }
        let image = textImage()
        let regions = try await OCRService.shared.recognizeRegions(from: image)
        precondition(!regions.isEmpty)
        report("image translation OCR complete")
        let controller = ImageTranslationWindowController(image: image)
        controller.model.loadRegions(regions)
        controller.window?.layoutIfNeeded()
        report("image translation window ready")
        controller.model.startTranslation()
        let session = TranslationSession(installedSource: source, target: target)
        await controller.model.translate(using: session, requestID: controller.model.activeRequestID)
        await controller.model.render()
        precondition(controller.model.translatedImage != nil)
        report("image translation rendered")
        controller.close()
        precondition(controller.window?.contentView == nil)
        report("image translation window closed")
    }

    @available(macOS 26.0, *)
    @MainActor private static func runTranslationWindow() {
        let controller = ImageTranslationWindowController(image: textImage())
        report("translation window constructed")
        controller.close()
        precondition(controller.window?.contentView == nil)
        report("translation window closed")
    }

    @available(macOS 26.0, *)
    @MainActor private static func runTranslationWindowLoop() {
        for iteration in 1...10 {
            autoreleasepool {
                let controller = ImageTranslationWindowController(image: textImage())
                controller.close()
                precondition(controller.window?.contentView == nil)
            }
            if iteration == 1 || iteration == 5 || iteration == 10 {
                report("translation window closed x\(iteration)")
            }
        }
    }

    private static func runImageRender() throws {
        let image = textImage()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let source = (0..<16).map { index in
            OCRTextRegion(id: index, text: "Create an issue and assign it to a project member",
                          bounds: CGRect(x: 0.04, y: 0.08 + CGFloat(index) * 0.054,
                                         width: 0.84, height: 0.04), confidence: 0.99)
        }
        report("image render fixture ready")
        let result = try ImageTranslationRenderer.render(image: cg, regions: source.map {
            TranslatedImageRegion(source: $0, translation: "创建问题并分配给项目成员")
        }, scale: 1)
        precondition(result.image.width == cg.width && result.image.height == cg.height)
        report("image render complete")
    }

    private static func runLongCaptureStitcher() {
        let stitcher = LongCaptureStitcher()
        for index in 0..<13 {
            autoreleasepool {
                let frame = LongCaptureFrame(image: scrollingFrame(offset: index * 72), timestamp: Double(index))
                precondition(stitcher.append(frame: frame).accepted)
            }
            if index == 0 || index == 6 || index == 12 { report("long accepted x\(index + 1)") }
        }
        let image = stitcher.renderFinalImage()
        precondition(image != nil && stitcher.totalPixelHeight == 1664)
        report("long final image rendered")
    }

    private static func textImage() -> NSImage {
        let size = CGSize(width: 1200, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()
        for row in 0..<16 {
            ("Create an issue and assign it to a project member \(row)" as NSString)
                .draw(at: CGPoint(x: 45, y: row * 44 + 35),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        return image
    }

    private static func scrollingFrame(offset: Int) -> CGImage {
        let width = 1400, height = 800
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let worldY = y + offset
            let row = worldY / 24, line = worldY % 24
            for x in 0..<width {
                let ink = line >= 7 && line < 16 && x > 40 && x < 200 + (row % 7) * 11
                let value = ink ? UInt8(45 + (row * 13) % 100) : UInt8(245)
                let position = (y * width + x) * 4
                pixels[position] = value
                pixels[position + 1] = value
                pixels[position + 2] = value
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                   CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func report(_ label: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(result == KERN_SUCCESS)
        print("MEMORY \(label): \(String(format: "%.1f", Double(info.phys_footprint) / 1048576)) MiB")
        fflush(stdout)
    }

    private static func sampleIdle(_ label: String) async throws {
        var previous = 0
        for seconds in [1, 5, 15, 60] {
            try await Task.sleep(for: .seconds(seconds - previous))
            report("\(label) idle \(seconds)s")
            previous = seconds
        }
    }
}
