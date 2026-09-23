import AppKit
import CoreText

nonisolated struct TranslatedImageRegion: Identifiable, Sendable {
    var source: OCRTextRegion
    var translation: String
    var isIncluded = true
    var id: Int { source.id }
}

nonisolated struct ImageTranslationRender: Sendable {
    let image: CGImage
    let overflowIDs: Set<Int>
    let complexBackgroundIDs: Set<Int>
}

nonisolated enum ImageTranslationRenderError: LocalizedError {
    case tooLarge, allocationFailed
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "图片过大，请缩小选区后重试原图翻译。"
        case .allocationFailed: return "无法创建翻译图片，请关闭其他图片后重试。"
        }
    }
}

nonisolated enum ImageTranslationRenderer {
    static func replacingSelection(in image: CGImage, with translated: CGImage,
                                   selection: CGRect, scale: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let rect = CGRect(x: selection.minX * scale, y: CGFloat(image.height) - selection.maxY * scale,
                          width: selection.width * scale, height: selection.height * scale)
        context.clip(to: rect)
        context.draw(translated, in: rect)
        return context.makeImage()
    }

    static func render(image: CGImage, regions: [TranslatedImageRegion], scale: CGFloat) throws -> ImageTranslationRender {
        try Task.checkCancellation()
        guard image.width <= 80_000_000 / max(image.height, 1) else { throw ImageTranslationRenderError.tooLarge }
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw ImageTranslationRenderError.allocationFailed }
        let size = CGSize(width: image.width, height: image.height)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var overflow = Set<Int>()
        var complex = Set<Int>()
        // Sample all backgrounds before drawing so neighboring translations do not affect one another.
        let backgrounds = regions.map { sampleBackground($0.source.bounds, pixels: pixels,
                                                         width: image.width, height: image.height,
                                                         bytesPerRow: context.bytesPerRow) }
        let inks = zip(regions, backgrounds).map {
            sampleInk($0.0.source.bounds, background: ($0.1.r, $0.1.g, $0.1.b), pixels: pixels,
                      width: image.width, height: image.height, bytesPerRow: context.bytesPerRow)
        }
        for (index, region) in regions.enumerated() where region.isIncluded {
            try Task.checkCancellation()
            let normalized = region.source.bounds.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !normalized.isNull, !normalized.isEmpty else { overflow.insert(region.id); continue }
            let rect = CGRect(x: normalized.minX * size.width, y: (1 - normalized.maxY) * size.height,
                              width: normalized.width * size.width, height: normalized.height * size.height)
            let text = region.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { overflow.insert(region.id); continue }
            if text == region.source.text.trimmingCharacters(in: .whitespacesAndNewlines) { continue }
            let background = backgrounds[index]
            if background.complex { complex.insert(region.id) }
            let brightness = background.r * 0.2126 + background.g * 0.7152 + background.b * 0.0722
            let ink = inks[index] ?? CGColor(gray: brightness > 0.5 ? 0.08 : 0.96, alpha: 1)
            let maxFont = max(6 * scale, rect.height / CGFloat(max(1, region.source.lineCount)) * 1.4)
            let minFont = max(5, 7 * scale)
            func layout(at fontSize: CGFloat) -> (frame: CTFrame?, line: CTLine?, origin: CGPoint)? {
                let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                let attributed = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink
                ])
                // OCR returns ink bounds, not a font's line box. Position single lines by their
                // glyph bounds so fallback CJK font leading does not halve the visible size.
                if region.source.lineCount == 1, !text.contains("\n") {
                    let line = CTLineCreateWithAttributedString(attributed)
                    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    let width = max(bounds.maxX, CTLineGetTypographicBounds(line, nil, nil, nil)) - min(0, bounds.minX)
                    if !bounds.isEmpty, width <= rect.width, bounds.height <= rect.height {
                        return (nil, line, CGPoint(x: rect.minX - bounds.minX, y: rect.midY - bounds.midY))
                    }
                }
                let framesetter = CTFramesetterCreateWithAttributedString(attributed)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
                guard CTFrameGetVisibleStringRange(frame).length == attributed.length else { return nil }
                let lines = CTFrameGetLines(frame) as! [CTLine]
                var origins = [CGPoint](repeating: .zero, count: lines.count)
                CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
                // CoreText counts an oversized single glyph as visible even when it will be clipped.
                let localRect = CGRect(origin: .zero, size: rect.size).insetBy(dx: -0.01, dy: -0.01)
                for (line, origin) in zip(lines, origins) {
                    let inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                        .offsetBy(dx: origin.x, dy: origin.y)
                    if !inkBounds.isEmpty && !localRect.contains(inkBounds) { return nil }
                    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                    if origin.x + width > rect.width + 0.01 { return nil }
                }
                return (frame, nil, .zero)
            }
            var low = min(minFont, maxFont), high = maxFont
            guard var frame = layout(at: low) else { overflow.insert(region.id); continue }
            for _ in 0..<9 {
                let middle = (low + high) / 2
                if let candidate = layout(at: middle) { frame = candidate; low = middle }
                else { high = middle }
            }
            context.saveGState()
            context.clip(to: rect)
            context.setFillColor(CGColor(srgbRed: background.r, green: background.g, blue: background.b, alpha: 1))
            context.fill(rect)
            context.textMatrix = .identity
            if let line = frame.line {
                context.textPosition = frame.origin
                CTLineDraw(line, context)
            } else if let textFrame = frame.frame {
                CTFrameDraw(textFrame, context)
            }
            context.restoreGState()
        }
        guard let output = context.makeImage() else { throw ImageTranslationRenderError.allocationFailed }
        return ImageTranslationRender(image: output, overflowIDs: overflow, complexBackgroundIDs: complex)
    }

    private static func sampleInk(_ bounds: CGRect, background: (CGFloat, CGFloat, CGFloat),
                                  pixels: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int) -> CGColor? {
        let rect = CGRect(x: bounds.minX * CGFloat(width), y: bounds.minY * CGFloat(height),
                          width: bounds.width * CGFloat(width), height: bounds.height * CGFloat(height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, !rect.isEmpty else { return nil }
        var bins: [Int: (count: Int, r: CGFloat, g: CGFloat, b: CGFloat)] = [:]
        let step = max(1, Int(max(rect.width, rect.height) / 180))
        for y in stride(from: Int(rect.minY), to: min(height, Int(ceil(rect.maxY))), by: step) {
            for x in stride(from: Int(rect.minX), to: min(width, Int(ceil(rect.maxX))), by: step) {
                let offset = y * bytesPerRow + x * 4
                let alpha = CGFloat(pixels[offset + 3])
                guard alpha > 180 else { continue }
                let r = CGFloat(pixels[offset]) / alpha, g = CGFloat(pixels[offset + 1]) / alpha, b = CGFloat(pixels[offset + 2]) / alpha
                guard abs(r - background.0) + abs(g - background.1) + abs(b - background.2) > 0.65 else { continue }
                let key = Int(r * 15) * 256 + Int(g * 15) * 16 + Int(b * 15)
                let old = bins[key] ?? (0, 0, 0, 0)
                bins[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
            }
        }
        guard let ink = bins.max(by: { $0.value.count < $1.value.count })?.value, ink.count >= 3 else { return nil }
        return CGColor(srgbRed: ink.r / CGFloat(ink.count), green: ink.g / CGFloat(ink.count), blue: ink.b / CGFloat(ink.count), alpha: 1)
    }

    private static func sampleBackground(_ bounds: CGRect, pixels: UnsafePointer<UInt8>,
                                         width: Int, height: Int, bytesPerRow: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat, complex: Bool) {
        let rect = CGRect(x: bounds.minX * CGFloat(width), y: bounds.minY * CGFloat(height),
                          width: bounds.width * CGFloat(width), height: bounds.height * CGFloat(height))
        var samples: [(CGFloat, CGFloat, CGFloat)] = []
        for step in 0..<16 {
            let t = CGFloat(step) / 15
            let points = [CGPoint(x: rect.minX + rect.width * t, y: rect.minY - 2),
                          CGPoint(x: rect.minX + rect.width * t, y: rect.maxY + 2),
                          CGPoint(x: rect.minX - 2, y: rect.minY + rect.height * t),
                          CGPoint(x: rect.maxX + 2, y: rect.minY + rect.height * t)]
            for point in points {
                let x = min(width - 1, max(0, Int(point.x)))
                let y = min(height - 1, max(0, Int(point.y)))
                let offset = y * bytesPerRow + x * 4
                let alpha = max(1, CGFloat(pixels[offset + 3]))
                samples.append((CGFloat(pixels[offset]) / alpha, CGFloat(pixels[offset + 1]) / alpha, CGFloat(pixels[offset + 2]) / alpha))
            }
        }
        let middle = samples.count / 2
        let r = samples.map { $0.0 }.sorted()[middle]
        let g = samples.map { $0.1 }.sorted()[middle]
        let b = samples.map { $0.2 }.sorted()[middle]
        let variation = samples.reduce(CGFloat(0)) { $0 + abs($1.0 - r) + abs($1.1 - g) + abs($1.2 - b) } / CGFloat(samples.count * 3)
        return (r, g, b, variation > 0.10)
    }
}
