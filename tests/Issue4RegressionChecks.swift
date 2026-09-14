import AppKit
import SwiftUI

@main
struct Issue4RegressionChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        // The reader runs in a fresh process after the writer has exited.
        if CommandLine.arguments.count == 3 {
            let mode = CommandLine.arguments[1]
            let name = CommandLine.arguments[2]
            let board = NSPasteboard(name: .init(name))
            if mode == "--clipboard-write" {
                let defaults = UserDefaults(suiteName: name)!
                defer { defaults.removePersistentDomain(forName: name) }
                let settings = SettingsService(defaults: defaults)
                settings.useRoundedCorners = true
                let service = CaptureService(settings: settings, pasteboard: board)
                service.copyToClipboard(NSImage(cgImage: fixture(offset: 0, pattern: "unique"), size: NSSize(width: 240, height: 240)))
                return
            }
            if mode == "--clipboard-read" {
                defer { board.releaseGlobally() }
                guard let png = board.data(forType: .png).flatMap(NSBitmapImageRep.init(data:)),
                      let tiff = board.data(forType: .tiff).flatMap(NSBitmapImageRep.init(data:)),
                      let a = png.cgImage, let b = tiff.cgImage,
                      png.pixelsWide == 480, tiff.pixelsHigh == 480,
                      png.colorAt(x: 0, y: 0)?.alphaComponent == 0,
                      samePixels(a, b), board.pasteboardItems?.count == 1,
                      let images = board.readObjects(forClasses: [NSImage.self]) as? [NSImage],
                      images.count == 1, images[0].size == NSSize(width: 240, height: 240) else {
                    print("FAIL: clipboard formats survive writer process exit"); exit(1)
                }
                print("PASS: clipboard PNG, TIFF, alpha, Retina size and single-item AppKit reading survive writer process exit")
                return
            }
        }
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL"): \(message)")
            if !value { failures += 1 }
        }
        let suite = "LibreShot.Issue4.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let imageBoard = NSPasteboard(name: .init(suite))
        defer { imageBoard.releaseGlobally() }
        let service = CaptureService(settings: settings, pasteboard: imageBoard)
        let image = NSImage(cgImage: fixture(offset: 0, pattern: "unique"), size: NSSize(width: 240, height: 240))
        settings.useRoundedCorners = true
        let rounded = NSBitmapImageRep(data: service.pngData(from: image)!)!
        check(rounded.colorAt(x: 0, y: 0)!.alphaComponent == 0, "rounded PNG preserves transparent corners")
        check(rounded.pixelsWide == 480 && rounded.pixelsHigh == 480, "Retina output retains physical dimensions")
        settings.useRoundedCorners = false
        let square = NSBitmapImageRep(data: service.pngData(from: image)!)!
        check(square.colorAt(x: 0, y: 0)!.alphaComponent == 1, "square PNG keeps corners")
        for roundedCorners in [false, true] {
            settings.useRoundedCorners = roundedCorners
            service.copyToClipboard(image)
            let png = imageBoard.data(forType: .png).flatMap(NSBitmapImageRep.init(data:))
            let tiff = imageBoard.data(forType: .tiff).flatMap(NSBitmapImageRep.init(data:))
            check(imageBoard.pasteboardItems?.count == 1, "clipboard contains one image item")
            check(png?.pixelsWide == 480 && tiff?.pixelsHigh == 480, "clipboard PNG and TIFF retain physical dimensions")
            check(png?.cgImage != nil && tiff?.cgImage != nil && samePixels(png!.cgImage!, tiff!.cgImage!), "clipboard PNG and TIFF pixels agree, rounded=\(roundedCorners)")
            check(png?.colorAt(x: 0, y: 0)?.alphaComponent == (roundedCorners ? 0 : 1), "clipboard preserves corner alpha")
            let pasted = NSImage(pasteboard: imageBoard)
            check(pasted?.size == image.size, "AppKit clipboard reader preserves Retina logical size")
        }
        settings.useRoundedCorners = false
        let retentionStitcher = LongCaptureStitcher()
        var retainedSources: [WeakPixelStorage] = []
        for (i, offset) in [0, 72, 144].enumerated() {
            autoreleasepool {
                let source = fixture(offset: offset, pattern: "footer")
                let storage = PixelStorage(source.dataProvider!.data!)
                retainedSources.append(WeakPixelStorage(storage))
                let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(storage).toOpaque(), data: storage.bytes,
                                              size: storage.count, releaseData: { info, _, _ in
                    Unmanaged<PixelStorage>.fromOpaque(info!).release()
                })!
                let tracked = CGImage(width: source.width, height: source.height, bitsPerComponent: 8,
                                      bitsPerPixel: 8, bytesPerRow: source.width, space: source.colorSpace!,
                                      bitmapInfo: source.bitmapInfo, provider: provider, decode: nil,
                                      shouldInterpolate: false, intent: .defaultIntent)!
                check(retentionStitcher.append(frame: .init(image: tracked, timestamp: Double(i))).accepted, "tracked source frame accepted")
            }
        }
        check(retainedSources.dropLast().allSatisfy { $0.value == nil }, "stitcher releases historical full-frame backing stores")
        check(retainedSources.last?.value != nil, "stitcher retains latest full frame for matching")
        let retainedResult = retentionStitcher.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        check(samePixels(retainedResult, fixture(offset: 0, pattern: "footer", height: 624)), "released source frames remain lossless in final output")
        for pattern in ["unique", "rows", "fixed"] {
            let stitcher = LongCaptureStitcher()
            _ = stitcher.append(frame: LongCaptureFrame(image: fixture(offset: 0, pattern: pattern), timestamp: 1))
            _ = stitcher.append(frame: LongCaptureFrame(image: fixture(offset: 72, pattern: pattern), timestamp: 1.2))
            check(stitcher.totalPixelHeight == 552, "\(pattern): 72 px scroll appends exactly 72 px")
        }
        for shift in [5, 17, 71, 144] {
            let match = LongCaptureOverlapMatcher().match(previous: fixture(offset: 0, pattern: "rows"),
                                                          current: fixture(offset: shift, pattern: "rows"))
            check(match.map { 480 - $0.overlapHeight } == shift, "foreground matching preserves odd/small offset \(shift)")
        }
        let matcher = LongCaptureOverlapMatcher()
        check(matcher.match(previous: fixture(offset: 72, pattern: "rows"), current: fixture(offset: 0, pattern: "rows")) == nil,
              "reverse scroll does not append guessed content")
        check(matcher.match(previous: fixture(offset: 0, pattern: "rows"), current: fixture(offset: 0, pattern: "rows")) == nil,
              "duplicate frame does not extend output")
        check(matcher.match(previous: fixture(offset: 0, pattern: "blank"), current: fixture(offset: 72, pattern: "blank")) == nil,
              "blank content is not guessed")
        let footerStitcher = LongCaptureStitcher()
        for (i, offset) in [0, 72, 144].enumerated() {
            _ = footerStitcher.append(frame: LongCaptureFrame(image: fixture(offset: offset, pattern: "footer"), timestamp: Double(i)))
        }
        check(footerStitcher.totalPixelHeight == 624, "fixed footer sequence appends each scroll once")
        if let final = footerStitcher.renderFinalImage(), let cg = final.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cg)
            check(rep.pixelsHigh == 624, "final footer rendering retains output height")
            check(rep.colorAt(x: 300, y: 600)!.usingColorSpace(.deviceRGB)!.redComponent < 0.5,
                  "fixed footer appears at the final bottom")
        } else { check(false, "render stitched fixture") }
        let stitchedPixels = footerStitcher.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let expectedFooter = fixture(offset: 0, pattern: "footer", height: 624)
        check(samePixels(stitchedPixels, expectedFooter), "fixed-footer output has no missing/repeated content rows")
        let multi = LongCaptureStitcher()
        for (i, offset) in [0, 5, 22, 93, 237].enumerated() {
            _ = multi.append(frame: LongCaptureFrame(image: fixture(offset: offset, pattern: "rows"), timestamp: Double(i)))
        }
        let multiImage = multi.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        check(samePixels(multiImage, fixture(offset: 0, pattern: "rows", height: 717)), "multiple odd offsets render every content pixel once")
        check(matcher.match(previous: fixture(offset: 0, pattern: "unique"), current: fixture(offset: 900, pattern: "unique")) == nil,
              "frames without overlap are rejected")
        check(matcher.match(previous: fixture(offset: 0, pattern: "periodic"), current: fixture(offset: 7, pattern: "periodic")) == nil,
              "truly ambiguous repeated rows are rejected")
        // Keep vertical pixel resolution across wide/Retina captures and repeated text rows.
        for (width, height) in [(1400, 800), (2000, 1000), (2400, 480)] {
            for shift in [2, 5, 7, 17, 71, 144] {
                let match = matcher.match(previous: fixture(offset: 0, pattern: "rows", width: width, height: height),
                                          current: fixture(offset: shift, pattern: "rows", width: width, height: height))
                check(match.map { height - $0.overlapHeight } == shift,
                      "wide \(width)x\(height): exact \(shift)px scroll")
            }
        }
        for footer in [20, 32, 64] {
            let stitcher = LongCaptureStitcher()
            for (i, offset) in [0, 5, 77, 149].enumerated() {
                _ = stitcher.append(frame: .init(image: fixture(offset: offset, pattern: "footer", footer: footer), timestamp: Double(i)))
            }
            let actual = stitcher.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            check(samePixels(actual, fixture(offset: 0, pattern: "footer", height: 629, footer: footer)),
                  "\(footer)px footer appears only once, with no lost content")
        }
        let continuousAnalyzer = LongCaptureFrameDeduplicator()
        let continuousStitcher = LongCaptureStitcher()
        for i in 0...12 {
            let frame = LongCaptureFrame(image: fixture(offset: i * 72, pattern: "rows"), timestamp: 1 + Double(i) * 0.1)
            if case .accept = continuousAnalyzer.process(frame: frame), continuousStitcher.append(frame: frame).accepted {
                continuousAnalyzer.markAccepted(frame)
            }
        }
        check(continuousStitcher.totalPixelHeight == 1344, "continuous scrolling captures intermediate frames without pauses")
        let analyzer = LongCaptureFrameDeduplicator()
        let first = LongCaptureFrame(image: fixture(offset: 0, pattern: "rows"), timestamp: 1)
        analyzer.markAccepted(first)
        let moving = LongCaptureFrame(image: fixture(offset: 72, pattern: "rows"), timestamp: 1.1)
        if case .accept = analyzer.process(frame: moving) { check(true, "complete moving frame is proposed without waiting for a pause") }
        else { check(false, "complete moving frame is proposed without waiting for a pause") }
        let settled = LongCaptureFrame(image: moving.image, timestamp: 1.3)
        if case .accept = analyzer.process(frame: settled) { check(true, "settled frame is proposed") }
        else { check(false, "settled frame is proposed") }
        if case .accept = analyzer.process(frame: settled) { check(true, "rejected frame remains retryable") }
        else { check(false, "rejected frame remains retryable") }
        analyzer.markAccepted(settled)
        if case .ignore = analyzer.process(frame: .init(image: moving.image, timestamp: 1.6)) { check(true, "successful frame is deduplicated") }
        else { check(false, "successful frame is deduplicated") }

        let accumulator = LongCaptureFrameAccumulator()
        _ = accumulator.process(frame: first)
        let missed = LongCaptureFrame(image: fixture(offset: 900, pattern: "unique"), timestamp: 2)
        check(accumulator.process(frame: missed)?.warning != nil, "unmatched frame reports a retry warning")
        do {
            _ = try accumulator.renderFinalImage()
            check(false, "incomplete capture must not silently export the first frame")
        } catch LongCaptureError.incompleteCapture {
            check(true, "incomplete capture must not silently export the first frame")
        }
        check(accumulator.process(frame: first)?.warning == nil, "returning to accepted content clears the warning")
        _ = accumulator.process(frame: settled)
        check(try accumulator.renderFinalImage().size.height == 552, "retry after an unmatched frame preserves and completes the document")

        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_CAPTURE_FIXTURE"],
           let supplied = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let document = LongCaptureFrameAccumulator()
            let frameHeight = min(600, supplied.height / 2)
            let lastOffset = supplied.height - frameHeight
            let offsets = Array(stride(from: 0, to: lastOffset, by: 72)) + [lastOffset]
            for (i, offset) in offsets.enumerated() {
                let frame = supplied.cropping(to: CGRect(x: 0, y: offset, width: supplied.width, height: frameHeight))!
                _ = document.process(frame: .init(image: frame, timestamp: 1 + Double(i) * 0.1))
            }
            let output = try document.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)!
            check(samePixels(output, supplied), "supplied mixed-content image stitches pixel-for-pixel during continuous scrolling")
        }

        // Colored, wide-gamut frames exercise fragment copies and the final color conversion.
        for colorSpaceName in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let width = 480, height = 624
            let gray = fixture(offset: 0, pattern: "unique", width: width, height: height)
            let input = gray.dataProvider!.data! as Data
            var rgba = [UInt8](repeating: 255, count: width * height * 4)
            for i in 0..<input.count {
                rgba[i * 4] = input[i]
                rgba[i * 4 + 1] = 255 - input[i]
                rgba[i * 4 + 2] = input[i] / 2
            }
            let document = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: width * 4, space: CGColorSpace(name: colorSpaceName)!,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent)!
            let stitcher = LongCaptureStitcher()
            for (i, offset) in [0, 72, 144].enumerated() {
                let frame = document.cropping(to: CGRect(x: 0, y: offset, width: width, height: 480))!
                check(stitcher.append(frame: .init(image: frame, timestamp: Double(i))).accepted, "colored frame accepted")
            }
            let result = stitcher.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            check(samePixels(result, document), "fragment copies retain final pixels for \(colorSpaceName)")
        }
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let window = OverlayWindow(contentRect: model.selectionRect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.bindEditingActions(to: model)
        var actions: [CaptureAction] = []
        var savedText = ""
        model.onCapture = { _, annotations, action, _ in
            actions.append(action)
            savedText = annotations.last?.text ?? ""
        }
        func event(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, characters: key,
                            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
        }
        model.selectedTool = .text
        model.startTextInput(at: CGPoint(x: 20, y: 20))
        model.editingTextContent = "尚未提交的文字"
        check(window.performKeyEquivalent(with: event("s", code: 1, modifiers: .command)), "Command-S handled by capture window")
        check(actions.last == .save && savedText == "尚未提交的文字", "saving commits pending annotation text")
        _ = window.performKeyEquivalent(with: event("s", code: 1, modifiers: [.command, .shift]))
        check(actions.last == .saveAs, "Shift-Command-S dispatches Save As")
        window.keyDown(with: event("\r", code: 36, modifiers: []))
        check(actions.last == .copy, "Return completes screenshot")
        let count = actions.count
        model.selectedTool = .text
        model.startTextInput(at: CGPoint(x: 20, y: 50))
        window.keyDown(with: event("\r", code: 36, modifiers: []))
        check(actions.count == count, "Return during text editing does not finish screenshot")
        let board = NSPasteboard(name: .init(suite + ".translation"))
        OCRCopyButton.copy("译文测试", to: board)
        check(board.string(forType: .string) == "译文测试", "copy translation writes the supplied translation")
        let longImage = NSImage(cgImage: fixture(offset: 0, pattern: "rows", height: 2000), size: NSSize(width: 240, height: 1000))
        let editor = ImageEditorWindowController(image: longImage, settings: settings)
        editor.model.selectedTool = .text
        editor.model.startTextInput(at: CGPoint(x: 20, y: 900))
        editor.model.editingTextContent = "底部标注"
        let exported = editor.renderedImage()
        check(!editor.model.canResizeSelection && !editor.model.visibleToolbarItems.contains(.longCapture), "image editor locks document bounds and hides capture action")
        check(editor.model.annotations.last?.startPoint.y == 900 && !editor.model.isEditingText, "long image commits bottom text in document coordinates")
        let exportCG = exported.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        check(exportCG.height == 2000 && exported.size.height == 1000, "editor export retains original pixels and logical size")
        if let directory = ProcessInfo.processInfo.environment["LIBRESHOT_ISSUE4_QA"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try render(OCRResultView(text: String(repeating: "布局验证文本 ", count: 100)),
                       size: CGSize(width: 480, height: 440), path: directory + "/ocr.png")
            try render(ImageEditorView(model: editor.model, imageSize: longImage.size),
                       size: CGSize(width: 800, height: 600), path: directory + "/editor.png")
        }
        editor.close()
        if failures > 0 { exit(1) }
    }

    static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        func bytes(_ image: CGImage) -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return pixels
        }
        return bytes(a) == bytes(b)
    }

    @MainActor static func render<V: View>(_ view: V, size: CGSize, path: String) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }

    static func fixture(offset: Int, pattern: String, width: Int = 480, height: Int = 480, footer: Int = 64) -> CGImage {
        var pixels = [UInt8](repeating: 245, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let yy = y + offset
            if pattern == "blank" { continue }
            if pattern == "unique" {
                pixels[y * width + x] = UInt8(((yy / 8) * 71 + (x / 8) * 39 + (yy / 8) * (x / 8) * 11) % 220)
            } else {
                let row = pattern == "periodic" ? 0 : yy / 24, line = yy % 24
                if line >= 7 && line < 16 && x > 40 && x < 200 + (row % 7) * 11 {
                    pixels[y * width + x] = UInt8(45 + (row * 13) % 100)
                }
                if pattern == "footer" && y >= height - footer { pixels[y * width + x] = 90 }
                if pattern == "fixed" && (y < 60 || x < 140) {
                    pixels[y * width + x] = UInt8(180 + (x / 10 + y / 10) % 50)
                }
            }
        }}
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }
}

private final class PixelStorage {
    let bytes: UnsafeMutableRawPointer
    let count: Int
    init(_ data: CFData) {
        count = CFDataGetLength(data)
        bytes = .allocate(byteCount: count, alignment: 16)
        bytes.copyMemory(from: CFDataGetBytePtr(data)!, byteCount: count)
    }
    deinit { bytes.deallocate() }
}
private final class WeakPixelStorage {
    weak var value: PixelStorage?
    init(_ value: PixelStorage) { self.value = value }
}
