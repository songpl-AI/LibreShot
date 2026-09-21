import AppKit
import SwiftUI
import Translation
import Vision

nonisolated private final class CancellationRequest: VNRecognizeTextRequest, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0
    var cancelCount: Int { lock.withLock { cancellations } }
    override func cancel() {
        lock.withLock { cancellations += 1 }
        super.cancel()
    }
}

@MainActor
enum ImageTranslationChecks {
    static func run() async throws {
        let image = fixture()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let request = CancellationRequest()
        let operation = OCRRecognitionOperation(request: request)
        let queue = DispatchQueue(label: "LibreShot.OCR.CancellationCheck")
        let gate = DispatchSemaphore(value: 0)
        queue.async { gate.wait() }
        let cancelledOCR = Task { try await operation.run(image: cg, queue: queue) }
        cancelledOCR.cancel()
        gate.signal()
        do {
            _ = try await cancelledOCR.value
            preconditionFailure("Cancelled OCR must not return recognition results")
        } catch is CancellationError { }
        precondition(request.cancelCount > 0, "Swift task cancellation must reach VNRequest.cancel")
        print("PASS: cancelled OCR forwards cancellation to Vision and returns no results")
        let source = [
            OCRTextRegion(id: 10, text: "Source text", bounds: CGRect(x: 0.06, y: 0.08, width: 0.4, height: 0.16), confidence: 0.99),
            OCRTextRegion(id: 20, text: "Table cell", bounds: CGRect(x: 0.55, y: 0.08, width: 0.4, height: 0.16), confidence: 0.99),
            OCRTextRegion(id: 30, text: "Dark background", bounds: CGRect(x: 0.06, y: 0.65, width: 0.88, height: 0.18), confidence: 0.99)
        ]
        let translated = zip(source, ["Translated text", "表格译文", "深色背景翻译"]).map {
            TranslatedImageRegion(source: $0.0, translation: $0.1)
        }
        let result = try ImageTranslationRenderer.render(image: cg, regions: translated, scale: 2)
        let unchanged = try ImageTranslationRenderer.render(image: cg, regions: source.map { .init(source: $0, translation: $0.text) }, scale: 2)
        let unchangedText = try await OCRService.shared.recognizeText(from: NSImage(cgImage: unchanged.image, size: image.size))
        precondition(unchangedText.contains("Source text") && unchangedText.contains("Dark background"))
        precondition(result.image.width == 1200 && result.image.height == 800)
        precondition(result.overflowIDs.isEmpty && result.complexBackgroundIDs.isEmpty)
        let output = NSBitmapImageRep(cgImage: result.image)
        precondition(output.colorAt(x: 5, y: 5)!.redComponent > 0.9)
        precondition(output.colorAt(x: 5, y: 700)!.redComponent < 0.2)
        let outputImage = NSImage(cgImage: result.image, size: image.size)
        let recognized = try await OCRService.shared.recognizeRegions(from: outputImage)
        precondition(recognized.contains { $0.text.contains("Translated") && $0.bounds.midY < 0.3 })
        precondition(!recognized.contains { $0.text.contains("Source") || $0.text.contains("Table cell") || $0.text.contains("Dark background") })
        precondition(recognized.contains { $0.bounds.midY > 0.6 }, "Bottom translation must remain at the bottom")
        print("PASS: image translation keeps physical size, light/dark backgrounds and top-left OCR coordinates; rendered text is recognized by Vision")

        var overflow = translated
        overflow[0].translation = String(repeating: "This translation is too long. ", count: 150)
        let rejected = try ImageTranslationRenderer.render(image: cg, regions: overflow, scale: 2)
        precondition(rejected.overflowIDs == [10])
        overflow[0].isIncluded = false
        let excluded = try ImageTranslationRenderer.render(image: cg, regions: overflow, scale: 2)
        precondition(excluded.overflowIDs.isEmpty)
        print("PASS: overflowing text is reported instead of truncated; excluded regions retain original pixels")

        let narrow = OCRTextRegion(id: 40, text: "I", bounds: CGRect(x: 0.3, y: 0.3, width: 2.0 / 1200, height: 20.0 / 800), confidence: 1)
        let clipped = try ImageTranslationRenderer.render(image: cg, regions: [.init(source: narrow, translation: "W")], scale: 1)
        precondition(clipped.overflowIDs == [40], "A glyph wider than its region must be rejected, not silently clipped")
        print("PASS: a single glyph that is wider than its region blocks export")

        let tableContext = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        tableContext.setFillColor(CGColor(gray: 1, alpha: 1))
        tableContext.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        tableContext.setFillColor(CGColor(gray: 0, alpha: 1))
        tableContext.fill(CGRect(x: 0, y: 335, width: 600, height: 1))
        let cells = [
            OCRTextRegion(id: 50, text: "First cell", bounds: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.05), confidence: 1),
            OCRTextRegion(id: 51, text: "Second cell", bounds: CGRect(x: 0.1, y: 0.17, width: 0.4, height: 0.05), confidence: 1)
        ]
        let table = try ImageTranslationRenderer.render(image: tableContext.makeImage()!, regions: OCRTextRegion.readingOrder(from: cells).map {
            .init(source: $0, translation: "Translated cell")
        }, scale: 1)
        precondition(NSBitmapImageRep(cgImage: table.image).colorAt(x: 100, y: 64)!.redComponent < 0.1,
                     "Translating adjacent table cells must not erase their separator")
        print("PASS: adjacent table cells retain the separating grid line")

        let lines = [
            OCRTextRegion(id: 0, text: "First line", bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.04), confidence: 0.9),
            OCRTextRegion(id: 1, text: "Second column", bounds: CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.04), confidence: 0.9),
            OCRTextRegion(id: 2, text: "Next line", bounds: CGRect(x: 0.1, y: 0.15, width: 0.29, height: 0.04), confidence: 0.8)
        ]
        let ordered = OCRTextRegion.readingOrder(from: lines)
        precondition(ordered.map(\.id) == [0, 1, 2])
        precondition(ordered[2].confidence == 0.8 && ordered[2].bounds == lines[2].bounds)
        print("PASS: reading order preserves separate lines, columns, IDs, bounds and confidence")

        let path = "/tmp/libreshot-roadmap-qa"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + "/translation-original.png"))
        try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + "/translation-result.png"))
        if #available(macOS 26.0, *) {
            try await lifecycle(image: image, source: source)
            try await renderWindow(image: image, translated: translated, path: path)
            let en = Locale.Language(identifier: "en"), zh = Locale.Language(identifier: "zh-Hans")
            if await LanguageAvailability().status(from: en, to: zh) == .installed {
                let session = TranslationSession(installedSource: en, target: zh)
                let responses = try await session.translations(from: source.map { .init(sourceText: $0.text, clientIdentifier: String($0.id)) })
                precondition(Set(responses.compactMap(\.clientIdentifier)) == Set(source.map { String($0.id) }))
                precondition(responses.allSatisfy { !$0.targetText.isEmpty })
                print("PASS: installed system translation model returns all batch region IDs")
            } else { print("NOT RUN: real batch translation; language model not installed (no download requested)") }
        }
    }

    @available(macOS 26.0, *)
    private static func lifecycle(image: NSImage, source: [OCRTextRegion]) async throws {
        var recognitionStarted = false
        var recognitionCancelled = false
        let recognizingModel = ImageTranslationModel(image: image, recognizeImage: { _ in
            recognitionStarted = true
            do { try await Task.sleep(for: .seconds(60)) }
            catch { recognitionCancelled = true; throw error }
            return []
        })
        let recognition = Task { await recognizingModel.recognize() }
        while !recognitionStarted { await Task.yield() }
        recognizingModel.cancel()
        try await Task.sleep(for: .milliseconds(30))
        precondition(recognitionCancelled, "Cancelling OCR must cancel the running recognition task, not only discard its result")
        await recognition.value
        precondition(recognizingModel.regions.isEmpty && !recognizingModel.isBusy)
        let model = ImageTranslationModel(image: image)
        model.loadRegions(source)
        model.startTranslation()
        let firstID = model.activeRequestID
        var continuation: CheckedContinuation<[Int: String], Error>?
        let old = Task { await model.run(requestID: firstID) { _ in try await withCheckedThrowingContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        model.cancel()
        model.startTranslation()
        await model.run(requestID: firstID) { _ in preconditionFailure("A late obsolete session must not translate the new request") }
        precondition(model.isTranslating && model.configuration != nil)
        await model.run(requestID: model.activeRequestID) { blocks in Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, "New text") }) }
        continuation?.resume(returning: Dictionary(uniqueKeysWithValues: source.map { ($0.id, "Stale text") }))
        await old.value
        precondition(model.regions.allSatisfy { $0.translation == "New text" })
        await model.render()
        precondition(model.canExport && model.translatedImage?.size == image.size)
        model.updateTranslation(String(repeating: "too long ", count: 500), id: 10)
        precondition(!model.canExport, "Export waits for the latest edit to render")
        await model.render()
        precondition(!model.canExport && model.overflowIDs.contains(10))
        model.setIncluded(false, id: 10)
        await model.render()
        precondition(model.canExport)
        model.updateTranslation("Pending change", id: 20)
        model.cancel()
        precondition(!model.canExport, "Cancelling layout must not export a stale image")
        model.targetLanguageID = "ja"
        precondition(model.translatedImage == nil && !model.canExport && model.regions.allSatisfy { $0.translation.isEmpty })
        model.startTranslation()
        await model.run(requestID: model.activeRequestID) { _ in [:] }
        precondition(model.errorMessage != nil && !model.canExport && !model.isTranslating)
        model.startTranslation()
        precondition(model.configuration != nil && model.isTranslating)
        model.cancel()
        precondition(model.configuration == nil && !model.isBusy)
        print("PASS: image translation cancellation/retry, stale result rejection, language changes, missing responses and export gating")
    }

    @available(macOS 26.0, *)
    private static func renderWindow(image: NSImage, translated: [TranslatedImageRegion], path: String) async throws {
        let controller = ImageTranslationWindowController(image: image)
        controller.model.loadRegions(translated.map(\.source))
        for region in translated { controller.model.updateTranslation(region.translation, id: region.id) }
        await controller.model.render()
        let window = controller.window!
        window.orderFrontRegardless()
        for (width, height) in [(1000, 680), (740, 480)] {
            window.setContentSize(CGSize(width: width, height: height))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            let view = window.contentView!
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path + "/translation-window-\(width).png"))
        }
        controller.close()
        precondition(window.contentView == nil && !controller.model.isBusy)
        print("PASS: native translation window renders at 1000x680 and 740x480 and tears down its content on close")
    }

    private static func fixture() -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1200, height: 800).fill()
        NSColor(white: 0.12, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: 1200, height: 350).fill()
        let font = NSFont.systemFont(ofSize: 42)
        for (text, point, color) in [("Source text", CGPoint(x: 90, y: 650), NSColor.black),
                                     ("Table cell", CGPoint(x: 690, y: 650), NSColor.black),
                                     ("Dark background", CGPoint(x: 90, y: 170), NSColor.white)] {
            (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
        }
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: rep.cgImage!, size: CGSize(width: 600, height: 400))
    }
}
