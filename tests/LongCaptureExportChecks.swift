import AppKit
import Foundation
import ImageIO

private final class ExportCountingService: CaptureService {
    var normalizationCalls = 0
    var unannotatedNormalizationCalls = 0
    var pngCalls = 0
    override func bitmapRep(from image: NSImage, opaque: Bool = false, reuseExportPixels: Bool = false) -> NSBitmapImageRep? {
        normalizationCalls += 1
        return super.bitmapRep(from: image, opaque: opaque, reuseExportPixels: reuseExportPixels)
    }
    override func normalizedUnannotatedImage(_ image: NSImage) -> NSImage {
        unannotatedNormalizationCalls += 1
        return super.normalizedUnannotatedImage(image)
    }
    override func pngData(from image: NSImage) -> Data? {
        pngCalls += 1
        return super.pngData(from: image)
    }
}

private final class PixelReleases: @unchecked Sendable {
    private let lock = NSLock()
    private var released = 0
    func mark() { lock.withLock { released += 1 } }
    var count: Int { lock.withLock { released } }
}

private final class PixelOwner {
    let releases: PixelReleases
    init(_ releases: PixelReleases) { self.releases = releases }
    deinit { releases.mark() }
}

@MainActor
private struct ExportFixture {
    let image: NSImage
    let pixels: CGImage
    let model: OverlayViewModel
    var backing: ImageEditorExportBacking?
    var source: ImageEditorLongCaptureSource?

    init(image: NSImage, settings: SettingsService, origin: ImageEditorImageOrigin = .longCaptureDocument,
         preview: CGImage? = nil) {
        self.image = image
        pixels = preview ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        model = OverlayViewModel(settings: settings)
        model.captureMode = .imageEditor
        model.state = .editing
        model.selectionRect = CGRect(origin: .zero, size: image.size)
        model.updatePreviewImage(pixels, scale: CGFloat(pixels.width) / image.size.width)
        backing = ImageEditorExportBacking(image: image, preview: pixels, origin: origin)
        source = ImageEditorLongCaptureSource(image: image, preview: pixels, origin: origin)
    }
}

private struct DecodedExport {
    let image: CGImage
    let metadata: NSDictionary
    let pngSemanticChunks: [Data]?
    init(_ data: Data) {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
        metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        if data.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) {
            var chunks: [Data] = [], offset = 8
            while offset + 12 <= data.count {
                let count = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
                precondition(offset + count + 12 <= data.count)
                let name = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii)!
                if name != "IDAT" && name != "IEND" {
                    chunks.append(data[(offset + 4)..<(offset + 8 + count)])
                }
                offset += count + 12
            }
            precondition(offset == data.count)
            pngSemanticChunks = chunks
        } else {
            pngSemanticChunks = nil
        }
    }
}

/// Calls the production backing certificate and renderer, without constructing
/// an NSWindow or invoking screen capture, OCR, or a translation Provider.
@main
struct LongCaptureExportChecks {
    private static var checks = 0
    private static var failures = 0

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let domain = "LibreShot.LongCaptureExport.Checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let board = NSPasteboard.withUniqueName(), referenceBoard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(domain, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: domain)
            board.releaseGlobally(); referenceBoard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = SettingsService(defaults: defaults)
        settings.useRoundedCorners = true
        require(settings.saveSaveDirectory(directory), "isolated temporary save directory")
        let service = ExportCountingService(settings: settings, pasteboard: board, directoryChooser: { _ in
            preconditionFailure("Headless checks must not open a permission panel")
        })
        let reference = ExportCountingService(settings: settings, pasteboard: referenceBoard, directoryChooser: { _ in
            preconditionFailure("Headless reference must not open a permission panel")
        })
        print("SCOPE: real DocumentStore strips/footer/forced spill; production renderer; private settings, directories and pasteboards; 0 windows, capture, OCR or Provider requests")

        try actionAndPixelChecks(settings, service, reference)
        try fractionalActionAndPixelChecks(settings, service, reference)
        try eligibilityChecks(settings, service, reference)
        try fractionalEligibilityChecks(settings, service, reference)
        try editingChecks(settings, service, reference)
        try translationChecks(settings, service, reference)
        try await clipboardAndSaveChecks(settings, service, reference, board, referenceBoard, directory)
        try await fractionalClipboardAndSaveChecks(settings, service, reference, board, referenceBoard, directory)
        try await backingReleaseCheck(settings, service)
        try await fractionalSourceReleaseCheck(settings, service)
        require(NSApp.windows.isEmpty, "all focused checks create zero windows")
        print("RESULT: \(checks - failures)/\(checks) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    private static func require(_ pass: Bool, _ label: String) {
        checks += 1
        if !pass { failures += 1 }
        print("\(pass ? "PASS" : "FAIL"): \(label)")
    }

    /// Actual native Store format and Engine wrapping; Session's logical-size
    /// calculation preserves physical pixels at 1x/2x, including odd dimensions.
    private static func storeImage(scale: CGFloat = 2, alpha: Bool = true,
                                   width: Int = 257, height: Int = 227,
                                   selectionWidth: CGFloat? = nil) throws -> NSImage {
        let footerHeight = max(1, height / 20), bodyHeight = height - footerHeight
        let image: CGImage = try autoreleasepool {
            var limits = LongCaptureLimits()
            limits.residentDocumentBytes = 0
            let store = LongCaptureDocumentStore(limits: limits)
            let firstRows = min(96, bodyHeight)
            for (y, rows) in [(0, firstRows), (firstRows, bodyHeight - firstRows)] where rows > 0 {
                try autoreleasepool {
                    try store.append(strip(width: width, height: rows, startY: y, alpha: alpha), at: y)
                }
            }
            precondition(store.residentBytes == 0 && store.spilledBytes == width * (height - footerHeight) * 4)
            return try store.render(height: height, footer: strip(width: width, height: footerHeight, startY: height - footerHeight, alpha: alpha))
        }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let logicalWidth = selectionWidth ?? CGFloat(width) / scale
        result.size = NSSize(width: logicalWidth, height: result.size.height * logicalWidth / result.size.width)
        return result
    }

    private static func strip(width: Int, height: Int, startY: Int, alpha: Bool) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height { for x in 0..<width {
            let gy = startY + y, offset = y * context.bytesPerRow + x * 4
            let a = alpha ? (x * 11 + gy * 17) % 256 : 255
            for (channel, value) in [(0, (x * 13 + gy * 3) % 256), (1, (gy * 7 + x) % 256), (2, (x * 5 + gy * 19) % 256)] {
                bytes[offset + channel] = UInt8(value * a / 255)
            }
            bytes[offset + 3] = UInt8(a)
        }}
        return context.makeImage()!
    }

    @MainActor private static func legacy(_ fixture: ExportFixture, base: CGImage?, service: CaptureService) -> NSImage {
        fixture.model.commitTextInput()
        let selected = base ?? fixture.model.imageForExport()
        let background = selected.map { NSImage(cgImage: $0, size: fixture.image.size) } ?? fixture.image
        return service.composite(image: background, annotations: fixture.model.annotations)
    }

    @MainActor @discardableResult
    private static func verify(_ fixture: ExportFixture, label: String, fast: Bool,
                               action: CaptureAction? = .save, base: CGImage? = nil,
                               service: ExportCountingService, reference: ExportCountingService,
                               normalizeOnce: Bool = false) -> NSImage {
        let inputBefore = rows(fixture.pixels)
        service.normalizationCalls = 0
        service.unannotatedNormalizationCalls = 0
        let actual = ImageEditorExportRenderer.render(image: fixture.image, model: fixture.model, base: base,
            action: action, backing: fixture.backing, source: fixture.source, service: service)
        let normalizationCalls = service.normalizationCalls
        let unannotatedCalls = service.unannotatedNormalizationCalls
        let expected = legacy(fixture, base: base, service: reference)
        let route = fast ? "certified original-pixel path" : (normalizeOnce ? "one normalization without empty composite draw" : "legacy composite fallback")
        require(normalizationCalls == (fast ? 0 : 1) && unannotatedCalls == (normalizeOnce ? 1 : 0), "\(label): \(route)")
        let old = DecodedExport(reference.pngData(from: expected)!)
        let new = DecodedExport(service.pngData(from: actual)!)
        require(exact(old, new) && actual.size == expected.size && rows(fixture.pixels) == inputBefore,
                "\(label): exact decoded native PNG pixels, alpha, ICC, metadata, dimensions and unchanged source")
        return actual
    }

    @MainActor private static func actionAndPixelChecks(_ settings: SettingsService, _ service: ExportCountingService,
                                                       _ reference: ExportCountingService) throws {
        for scale: CGFloat in [1, 2] { for rounded in [false, true] {
            settings.useRoundedCorners = rounded
            let fixture = ExportFixture(image: try storeImage(scale: scale), settings: settings)
            require(fixture.backing != nil, "actual Store footer/spill backing qualifies at \(scale)x")
            for action in [CaptureAction.save, .saveAs, .copy, .saveAndCopy] {
                verify(fixture, label: "\(action) \(scale)x rounded=\(rounded)", fast: true, action: action, service: service, reference: reference)
            }
            fixture.model.reset()
        }}
        settings.useRoundedCorners = true
        let fixture = ExportFixture(image: try storeImage(), settings: settings)
        for action: CaptureAction? in [nil, .pin, .ocr, .translate] {
            verify(fixture, label: "non-save-copy action \(String(describing: action))", fast: false, action: action, service: service, reference: reference)
        }
        fixture.model.reset()
    }

    @MainActor private static func fractionalActionAndPixelChecks(_ settings: SettingsService,
                                                                 _ service: ExportCountingService,
                                                                 _ reference: ExportCountingService) throws {
        let geometries: [(String, Int, Int, CGFloat)] = [
            ("original raw-bypass counterexample", 257, 111, 97.5),
            ("integral crop near 2x", 601, 407, 300),
            ("fractional selection near 2x", 602, 411, 300.25),
            ("integral crop near 1x", 301, 181, 300),
            ("3x remains normalized", 257, 111, CGFloat(257) / 3),
            ("2.5x remains normalized", 257, 111, 102.8)
        ]
        for (label, width, height, logicalWidth) in geometries {
            for alpha in [false, true] { for rounded in [false, true] {
                settings.useRoundedCorners = rounded
                let fixture = ExportFixture(image: try storeImage(alpha: alpha, width: width, height: height,
                                                                  selectionWidth: logicalWidth), settings: settings)
                require(fixture.backing == nil && fixture.source != nil,
                        "\(label) alpha=\(alpha): canonical source qualifies without weakening exact 1x/2x certificate")
                for action in [CaptureAction.save, .saveAs, .copy, .saveAndCopy] {
                    verify(fixture, label: "\(label) \(action) alpha=\(alpha) rounded=\(rounded)", fast: false,
                           action: action, service: service, reference: reference, normalizeOnce: true)
                }
                fixture.model.reset()
            }}
        }
        settings.useRoundedCorners = true
    }

    @MainActor private static func eligibilityChecks(_ settings: SettingsService, _ service: ExportCountingService,
                                                    _ reference: ExportCountingService) throws {
        func check(_ label: String, _ mutate: (inout ExportFixture) -> Void) throws {
            var fixture = ExportFixture(image: try storeImage(), settings: settings)
            mutate(&fixture)
            verify(fixture, label: label, fast: false, service: service, reference: reference)
            fixture.model.reset()
        }
        try check("unknown source") {
            $0.backing = ImageEditorExportBacking(image: $0.image, preview: $0.pixels, origin: .generic)
            $0.source = ImageEditorLongCaptureSource(image: $0.image, preview: $0.pixels, origin: .generic)
        }
        try check("non-editor mode") { $0.model.captureMode = .normal }
        try check("partial selection") { $0.model.selectionRect.size.height -= 1 }
        try check("changed logical size") { $0.image.size.width += 1 }
        try check("second NSImage representation") { $0.image.addRepresentation(NSBitmapImageRep(cgImage: $0.pixels)) }
        try check("replaced preview identity") { $0.model.updatePreviewImage(strip(width: 257, height: 227, startY: 10, alpha: true), scale: 2) }
        let explicit = ExportFixture(image: try storeImage(), settings: settings)
        let other = strip(width: 257, height: 227, startY: 30, alpha: true)
        verify(explicit, label: "supplied base takes precedence", fast: false, base: other, service: service, reference: reference)
        explicit.model.reset()

        for (label, space, bits, floating) in [
            ("Display P3", CGColorSpace(name: CGColorSpace.displayP3)!, 8, false),
            ("16-bit integer", CGColorSpace(name: CGColorSpace.sRGB)!, 16, false),
            ("32-bit float", CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, 32, true)
        ] {
            var info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            if floating { info.formUnion([.floatComponents, .byteOrder32Little]) }
            else if bits == 16 { info.formUnion(.byteOrder16Little) }
            let context = CGContext(data: nil, width: 120, height: 80, bitsPerComponent: bits,
                                    bytesPerRow: 0, space: space, bitmapInfo: info.rawValue)!
            context.setFillColor(CGColor(srgbRed: 0.15, green: 0.7, blue: 0.3, alpha: 0.6))
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
            let source = context.makeImage()!
            let fixture = ExportFixture(image: NSImage(cgImage: source, size: NSSize(width: 60, height: 40)), settings: settings, preview: source)
            require(fixture.backing == nil, "\(label): noncanonical backing is not certified")
            require(fixture.source == nil, "\(label): noncanonical source cannot take one-normalization path")
            verify(fixture, label: label, fast: false, service: service, reference: reference)
            fixture.model.reset()
        }
        let fractional = ExportFixture(image: try storeImage(scale: 1.5), settings: settings)
        require(fractional.backing == nil, "non-1x/2x logical ratio is not certified")
        require(fractional.source != nil, "known fractional long source retains independent normalization provenance")
        verify(fractional, label: "fractional scale keeps one required normalization", fast: false,
               service: service, reference: reference, normalizeOnce: true)
        fractional.model.reset()
    }

    @MainActor private static func fractionalEligibilityChecks(_ settings: SettingsService,
                                                              _ service: ExportCountingService,
                                                              _ reference: ExportCountingService) throws {
        func check(_ label: String, _ mutate: (inout ExportFixture) -> Void) throws {
            var fixture = ExportFixture(image: try storeImage(width: 601, height: 407, selectionWidth: 300),
                                        settings: settings)
            require(fixture.backing == nil && fixture.source != nil, "\(label): starts on single-normalization source")
            mutate(&fixture)
            verify(fixture, label: label, fast: false, service: service, reference: reference)
            fixture.model.reset()
        }
        try check("fractional generic provenance") {
            $0.source = ImageEditorLongCaptureSource(image: $0.image, preview: $0.pixels, origin: .generic)
        }
        try check("fractional source omitted") { $0.source = nil }
        try check("fractional mismatched source CG identity") {
            $0.source = ImageEditorLongCaptureSource(image: $0.image,
                preview: strip(width: 601, height: 407, startY: 9, alpha: true), origin: .longCaptureDocument)
        }
        try check("fractional non-editor mode") { $0.model.captureMode = .normal }
        try check("fractional partial selection") { $0.model.selectionRect.size.height -= 1 }
        try check("fractional changed logical size") { $0.image.size.width += 0.25 }
        try check("fractional added representation") {
            $0.image.addRepresentation(NSBitmapImageRep(cgImage: $0.pixels))
            require(ImageEditorLongCaptureSource(image: $0.image, preview: $0.pixels, origin: .longCaptureDocument) == nil,
                    "multiple representations cannot mint new normalization source")
        }
        try check("fractional replaced preview") {
            $0.model.updatePreviewImage(strip(width: 601, height: 407, startY: 10, alpha: true), scale: 2)
        }
        try check("fractional missing preview") { $0.model.updatePreviewImage(nil, scale: 2) }
        try check("fractional annotation present") {
            $0.model.annotations = [Annotation(type: .rectangle, color: .red,
                startPoint: CGPoint(x: 10, y: 20), endPoint: CGPoint(x: 60, y: 70))]
        }
        try check("fractional pending gesture") {
            $0.model.selectedTool = .rectangle
            $0.model.startDrawing(at: CGPoint(x: 20, y: 20))
        }
        try check("fractional current gesture") {
            $0.model.selectedTool = .rectangle
            $0.model.startDrawing(at: CGPoint(x: 20, y: 20))
            $0.model.updateDrawing(to: CGPoint(x: 50, y: 50))
        }
        try check("fractional orphan translated image") {
            $0.model.translatedSelection = strip(width: 601, height: 407, startY: 50, alpha: true)
        }
        let fixture = ExportFixture(image: try storeImage(width: 601, height: 407, selectionWidth: 300), settings: settings)
        let other = strip(width: 601, height: 407, startY: 30, alpha: true)
        verify(fixture, label: "fractional supplied base priority", fast: false, base: other,
               service: service, reference: reference)
        for action: CaptureAction? in [nil, .pin, .ocr, .translate] {
            verify(fixture, label: "fractional non-export action \(String(describing: action))", fast: false,
                   action: action, service: service, reference: reference)
        }
        fixture.model.selectedTool = .text
        fixture.model.startTextInput(at: CGPoint(x: 10, y: 20))
        fixture.model.editingTextContent = "Fractional 中文"
        verify(fixture, label: "fractional active text commits before route", fast: false,
               service: service, reference: reference)
        require(!fixture.model.isEditingText && fixture.model.annotations.last?.text == "Fractional 中文",
                "fractional route commits text without losing the annotation")
        fixture.model.undoLastAnnotation()
        verify(fixture, label: "fractional undo restores one normalization", fast: false,
               service: service, reference: reference, normalizeOnce: true)
        fixture.model.startTextInput(at: CGPoint(x: 10, y: 20))
        verify(fixture, label: "fractional empty text restores one normalization", fast: false,
               service: service, reference: reference, normalizeOnce: true)
        if #available(macOS 26.0, *) {
            fixture.model.confirmImageTranslation()
            verify(fixture, label: "fractional original with live translation source", fast: false,
                   service: service, reference: reference)
            fixture.model.clearImageTranslation()
            verify(fixture, label: "fractional ended translation restores one normalization", fast: false,
                   service: service, reference: reference, normalizeOnce: true)
        }
        fixture.model.reset()
    }

    @MainActor private static func editingChecks(_ settings: SettingsService, _ service: ExportCountingService,
                                                _ reference: ExportCountingService) throws {
        let text = ExportFixture(image: try storeImage(), settings: settings)
        text.model.selectedTool = .text
        text.model.startTextInput(at: CGPoint(x: 10, y: 20))
        text.model.editingTextContent = "Keep text 中文"
        verify(text, label: "commit active text before qualification", fast: false, service: service, reference: reference)
        require(!text.model.isEditingText && text.model.annotations.last?.text == "Keep text 中文", "active text commits exactly once and remains in export")
        text.model.undoLastAnnotation()
        require(text.model.annotations.isEmpty, "undo returns document to no annotations")
        verify(text, label: "undo to empty restores fast path", fast: true, service: service, reference: reference)
        text.model.startTextInput(at: CGPoint(x: 10, y: 20))
        verify(text, label: "empty text commits without an annotation", fast: true, service: service, reference: reference)
        require(!text.model.isEditingText, "empty text input ends normally")
        text.model.reset()

        let number = ExportFixture(image: try storeImage(), settings: settings)
        let annotation = Annotation(type: .number, color: .red, startPoint: CGPoint(x: 25, y: 25), text: "1")
        number.model.annotations = [annotation]
        number.model.startNumberEdit(annotationID: annotation.id)
        number.model.editingTextContent = "invalid"
        var captures = 0
        number.model.onCapture = { _, _, _, _ in captures += 1 }
        number.model.confirmSave()
        require(captures == 0 && number.model.isEditingText && number.model.annotations[0].text == "1", "invalid number blocks actual confirmation without discarding input")
        verify(number, label: "unfinished number falls back", fast: false, service: service, reference: reference)
        require(number.model.isEditingText && number.model.editingTextContent == "invalid", "renderer does not cancel invalid number input")
        number.model.reset()

        let drawing = ExportFixture(image: try storeImage(), settings: settings)
        drawing.model.selectedTool = .rectangle
        drawing.model.startDrawing(at: CGPoint(x: 15, y: 15))
        require(drawing.model.hasDrawingGesture && drawing.model.currentAnnotation == nil, "pointer-down creates private pending gesture")
        verify(drawing, label: "pending drawing falls back", fast: false, service: service, reference: reference)
        require(drawing.model.hasDrawingGesture, "fallback does not cancel pending gesture")
        drawing.model.updateDrawing(to: CGPoint(x: 45, y: 45))
        verify(drawing, label: "current drawing falls back", fast: false, service: service, reference: reference)
        require(drawing.model.currentAnnotation != nil && drawing.model.annotations.isEmpty, "fallback preserves uncommitted drawing")
        drawing.model.endDrawing()
        verify(drawing, label: "committed shape draws normally", fast: false, service: service, reference: reference)
        drawing.model.deleteSelectedAnnotation()
        verify(drawing, label: "delete last shape restores fast path", fast: true, service: service, reference: reference)
        drawing.model.reset()
    }

    @MainActor private static func translationChecks(_ settings: SettingsService, _ service: ExportCountingService,
                                                     _ reference: ExportCountingService) throws {
        let fixture = ExportFixture(image: try storeImage(alpha: false), settings: settings)
        if #available(macOS 26.0, *) {
            fixture.model.confirmImageTranslation()
            require(fixture.model.translationSource != nil && !fixture.model.canExportSelection, "translation session source blocks incomplete actual export")
            let context = CGContext(data: nil, width: fixture.pixels.width, height: fixture.pixels.height,
                                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.3, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: fixture.pixels.width, height: fixture.pixels.height))
            fixture.model.translatedSelection = context.makeImage()
            let actual = verify(fixture, label: "translated imageForExport background", fast: false, service: service, reference: reference)
            let output = actual.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            require(rows(output) != rows(fixture.pixels), "translated pixels replace source instead of saving original")
            let supplied = fixture.model.imageForExport()!
            verify(fixture, label: "supplied translated base priority", fast: false, base: supplied, service: service, reference: reference)
            fixture.model.showsOriginalTranslation = true
            verify(fixture, label: "original comparison keeps session fallback", fast: false, service: service, reference: reference)
            fixture.model.clearImageTranslation()
            verify(fixture, label: "ended translation restores original fast path", fast: true, service: service, reference: reference)
        } else { print("NOT RUN: translation-source checks require macOS 26; no real OCR or translation requests") }
        fixture.model.translatedSelection = strip(width: 257, height: 227, startY: 80, alpha: false)
        verify(fixture, label: "orphan translated selection fallback", fast: false, service: service, reference: reference)
        fixture.model.reset()
    }

    @MainActor private static func clipboardAndSaveChecks(_ settings: SettingsService, _ service: ExportCountingService,
                                                         _ reference: ExportCountingService, _ board: NSPasteboard,
                                                         _ referenceBoard: NSPasteboard, _ directory: URL) async throws {
        let fixture = ExportFixture(image: try storeImage(), settings: settings)
        let output = ImageEditorExportRenderer.render(image: fixture.image, model: fixture.model, action: .copy,
                                                      backing: fixture.backing, source: fixture.source, service: service)
        let expected = legacy(fixture, base: nil, service: reference)
        reference.copyToClipboard(expected)
        settings.autoSaveEnabled = false
        service.pngCalls = 0
        require(try await service.completeCapture(output) == nil, "disabled autosave remains copy only")
        require(service.pngCalls == 1, "copy encodes PNG once")
        require(board.pasteboardItems?.count == 1, "PNG and TIFF share one private pasteboard item")
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let actual = DecodedExport(board.data(forType: type)!), old = DecodedExport(referenceBoard.data(forType: type)!)
            require(exact(old, actual), "private clipboard \(type.rawValue) preserves exact native pixels, ICC and metadata")
            let dx = (actual.metadata[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
            let dy = (actual.metadata[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 0
            require(abs(dx - 144) < 0.1 && abs(dy - 144) < 0.1 && actual.image.width == 257 && actual.image.height == 227,
                    "private clipboard \(type.rawValue) preserves Retina DPI and physical dimensions")
        }
        settings.autoSaveEnabled = true
        service.pngCalls = 0
        let saved = try await service.completeCapture(output)!
        let savedData = try Data(contentsOf: saved)
        require(saved.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() &&
                savedData == board.data(forType: .png) && service.pngCalls == 1,
                "autosave and copy write identical PNG with one encoding")
        service.pngCalls = 0
        let combined = try await service.copyAndSaveImageDirectly(output)
        require((try Data(contentsOf: combined)) == board.data(forType: .png) && service.pngCalls == 1,
                "explicit save-and-copy writes identical PNG with one encoding")
        board.clearContents(); board.setString("private sentinel", forType: .string)
        let saveOnly = try await service.saveImageDirectly(output)
        require(exact(DecodedExport(try Data(contentsOf: saveOnly)), DecodedExport(reference.pngData(from: expected)!)) &&
                board.string(forType: .string) == "private sentinel", "save-only preserves private clipboard and exact file content")
        fixture.model.reset()
    }

    @MainActor private static func fractionalClipboardAndSaveChecks(_ settings: SettingsService,
                                                                    _ service: ExportCountingService,
                                                                    _ reference: ExportCountingService,
                                                                    _ board: NSPasteboard,
                                                                    _ referenceBoard: NSPasteboard,
                                                                    _ directory: URL) async throws {
        for (label, width, height, logicalWidth) in [("near 2x", 601, 407, CGFloat(300)),
                                                   ("AppKit fractional redraw", 257, 111, CGFloat(97.5))] {
            for rounded in [false, true] {
                settings.useRoundedCorners = rounded
                let fixture = ExportFixture(image: try storeImage(width: width, height: height,
                    selectionWidth: logicalWidth), settings: settings)
                service.normalizationCalls = 0
                service.unannotatedNormalizationCalls = 0
                let output = ImageEditorExportRenderer.render(image: fixture.image, model: fixture.model, action: .copy,
                    backing: fixture.backing, source: fixture.source, service: service)
                require(service.normalizationCalls == 1 && service.unannotatedNormalizationCalls == 1,
                        "\(label) rounded=\(rounded): clipboard receives one-normalization output")
                let expected = legacy(fixture, base: nil, service: reference)
                reference.copyToClipboard(expected)
                settings.autoSaveEnabled = false
                service.pngCalls = 0
                require(try await service.completeCapture(output) == nil && service.pngCalls == 1,
                        "\(label): copy-only performs one PNG encoding without saving")
                require(board.pasteboardItems?.count == 1, "\(label): private PNG/TIFF share one item")
                for type in [NSPasteboard.PasteboardType.png, .tiff] {
                    let actual = DecodedExport(board.data(forType: type)!)
                    let old = DecodedExport(referenceBoard.data(forType: type)!)
                    require(exact(old, actual), "\(label) rounded=\(rounded) \(type.rawValue): exact native pixels, alpha, ICC, DPI and metadata")
                    let dx = (actual.metadata[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0
                    let dy = (actual.metadata[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 0
                    let expectedDX = Double(actual.image.width) / output.size.width * 72
                    let expectedDY = Double(actual.image.height) / output.size.height * 72
                    require(abs(dx - expectedDX) < 0.1 && abs(dy - expectedDY) < 0.1 && output.size == fixture.image.size,
                            "\(label) \(type.rawValue): fractional logical size and pixels/logical DPI preserved")
                }
                settings.autoSaveEnabled = true
                service.pngCalls = 0
                let saved = try await service.completeCapture(output)!
                let savedData = try Data(contentsOf: saved)
                require(saved.deletingLastPathComponent().resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() &&
                        savedData == board.data(forType: .png) && service.pngCalls == 1,
                        "\(label): fractional autosave writes the same private clipboard PNG once")
                service.pngCalls = 0
                let combined = try await service.copyAndSaveImageDirectly(output)
                require((try Data(contentsOf: combined)) == board.data(forType: .png) && service.pngCalls == 1,
                        "\(label): fractional save-and-copy encodes once")
                board.clearContents(); board.setString("fractional private sentinel", forType: .string)
                let saveOnly = try await service.saveImageDirectly(output)
                require(exact(DecodedExport(try Data(contentsOf: saveOnly)), DecodedExport(reference.pngData(from: expected)!)) &&
                        board.string(forType: .string) == "fractional private sentinel",
                        "\(label): fractional save-only preserves clipboard and exact PNG")
                fixture.model.reset()
            }
        }
        settings.useRoundedCorners = true
    }

    @MainActor private static func backingReleaseCheck(_ settings: SettingsService, _ service: CaptureService) async throws {
        let events = PixelReleases()
        weak var pixelOwner: PixelOwner?
        let retainedModel = OverlayViewModel(settings: settings)
        var backing: ImageEditorExportBacking?
        var source: ImageEditorLongCaptureSource?
        autoreleasepool {
            let owner = PixelOwner(events)
            pixelOwner = owner
            let count = 64 * 48 * 4
            let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
            bytes.initializeMemory(as: UInt8.self, repeating: 255, count: count)
            let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(owner).toOpaque(), data: bytes, size: count) { info, bytes, _ in
                UnsafeMutableRawPointer(mutating: bytes).deallocate()
                if let info { _ = Unmanaged<PixelOwner>.fromOpaque(info).takeRetainedValue() }
            }!
            let pixels = CGImage(width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64 * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let image = NSImage(cgImage: pixels, size: NSSize(width: 32, height: 24))
            retainedModel.captureMode = .imageEditor
            retainedModel.state = .editing
            retainedModel.selectionRect = CGRect(origin: .zero, size: image.size)
            retainedModel.updatePreviewImage(pixels, scale: 2)
            backing = ImageEditorExportBacking(image: image, preview: pixels, origin: .longCaptureDocument)
            source = ImageEditorLongCaptureSource(image: image, preview: pixels, origin: .longCaptureDocument)
            require(backing != nil && source != nil, "tracked canonical provider qualifies for both ownership certificates")
            let output = ImageEditorExportRenderer.render(image: image, model: retainedModel, action: .save,
                                                         backing: backing, source: source, service: service)
            require(output.cgImage(forProposedRect: nil, context: nil, hints: nil) === pixels, "fast output shares original immutable backing")
            retainedModel.reset()
        }
        require(events.count == 0 && pixelOwner != nil, "certificate intentionally retains backing until document close")
        autoreleasepool { backing = nil }
        require(events.count == 0 && pixelOwner != nil, "long-source ownership remains after raw certificate is cleared")
        autoreleasepool { source = nil }
        for _ in 0..<100 where events.count == 0 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        require(events.count == 1 && pixelOwner == nil && retainedModel.previewImage == nil,
                "dropping both certificates after reset releases pixel provider once while model remains alive")
    }

    @MainActor private static func fractionalSourceReleaseCheck(_ settings: SettingsService,
                                                               _ service: CaptureService) async throws {
        let events = PixelReleases()
        weak var pixelOwner: PixelOwner?
        let retainedModel = OverlayViewModel(settings: settings)
        var source: ImageEditorLongCaptureSource?
        var exported: NSImage?
        var exportedPNG: Data?
        autoreleasepool {
            let owner = PixelOwner(events)
            pixelOwner = owner
            let count = 64 * 48 * 4
            let bytes = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
            bytes.initializeMemory(as: UInt8.self, repeating: 255, count: count)
            let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(owner).toOpaque(), data: bytes, size: count) { info, bytes, _ in
                UnsafeMutableRawPointer(mutating: bytes).deallocate()
                if let info { _ = Unmanaged<PixelOwner>.fromOpaque(info).takeRetainedValue() }
            }!
            let pixels = CGImage(width: 64, height: 48, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64 * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            // Session changes the initial pixel-as-point NSImage logical size;
            // constructing it at the final fractional size would change preview selection.
            let image = NSImage(cgImage: pixels, size: NSSize(width: 64, height: 48))
            image.size = NSSize(width: 31.8, height: 48 * 31.8 / 64)
            retainedModel.captureMode = .imageEditor
            retainedModel.state = .editing
            retainedModel.selectionRect = CGRect(origin: .zero, size: image.size)
            retainedModel.updatePreviewImage(pixels, scale: 64 / 31.8)
            let backing = ImageEditorExportBacking(image: image, preview: pixels, origin: .longCaptureDocument)
            source = ImageEditorLongCaptureSource(image: image, preview: pixels, origin: .longCaptureDocument)
            require(backing == nil && source != nil, "tracked fractional provider qualifies only for one normalization")
            exported = ImageEditorExportRenderer.render(image: image, model: retainedModel, action: .save,
                backing: backing, source: source, service: service)
            exportedPNG = service.pngData(from: exported!)!
            require(exported!.size == image.size, "one-normalization owned output keeps document logical size")
            retainedModel.reset()
        }
        require(events.count == 0 && pixelOwner != nil, "fractional source keeps original provider until close")
        autoreleasepool { source = nil }
        for _ in 0..<100 where events.count == 0 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        require(events.count == 1 && pixelOwner == nil && retainedModel.previewImage == nil,
                "cleared fractional source releases original provider once even while normalized export remains alive")
        require(exact(DecodedExport(exportedPNG!), DecodedExport(service.pngData(from: exported!)!)),
                "normalized export remains decodable and exact after original document provider releases")
        exported = nil
    }

    private static func rows(_ image: CGImage) -> Data {
        let bytes = image.dataProvider!.data! as Data
        let count = (image.width * image.bitsPerPixel + 7) / 8
        precondition(image.bytesPerRow >= count && bytes.count >= image.bytesPerRow * image.height)
        var result = Data()
        for y in 0..<image.height { result.append(bytes[(y * image.bytesPerRow)..<(y * image.bytesPerRow + count)]) }
        return result
    }

    private static func exact(_ old: DecodedExport, _ new: DecodedExport) -> Bool {
        old.image.width == new.image.width && old.image.height == new.image.height &&
        old.image.bitsPerComponent == new.image.bitsPerComponent && old.image.bitsPerPixel == new.image.bitsPerPixel &&
        old.image.bitmapInfo == new.image.bitmapInfo && old.image.alphaInfo == new.image.alphaInfo &&
        old.image.colorSpace?.copyICCData() as Data? == new.image.colorSpace?.copyICCData() as Data? &&
        old.metadata.isEqual(new.metadata) && old.pngSemanticChunks == new.pngSemanticChunks && rows(old.image) == rows(new.image)
    }
}
