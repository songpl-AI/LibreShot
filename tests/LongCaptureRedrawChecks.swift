import AppKit

/// Synthetic image checks only. Does not launch the app, capture the screen,
/// access the clipboard, or read user images.
@main
struct LongCaptureRedrawChecks {
    @MainActor static func main() {
        var failures = 0
        var assertions = 0
        func check(_ value: Bool, _ message: String) {
            assertions += 1
            print("\(value ? "PASS" : "FAIL"): \(message)")
            if !value { failures += 1 }
        }
        func send(_ document: LongCaptureFrameAccumulator, _ image: CGImage, at timestamp: Double) -> LongCaptureProgress? {
            document.process(frame: .init(image: image, timestamp: timestamp))
        }
        func checkOutput(_ document: LongCaptureFrameAccumulator, expected: CGImage, _ message: String) {
            do {
                let output = try document.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)!
                check(samePixels(output, expected), message)
            } catch {
                check(false, "\(message): \(error.localizedDescription)")
            }
        }
        func checkIncomplete(_ document: LongCaptureFrameAccumulator, _ message: String) {
            do {
                _ = try document.renderFinalImage()
                check(false, message)
            } catch LongCaptureError.incompleteCapture {
                check(true, message)
            } catch {
                check(false, "\(message): unexpected \(error.localizedDescription)")
            }
        }

        let document = LongCaptureFrameAccumulator()
        _ = send(document, fixture(offset: 0), at: 0)
        let moved = send(document, fixture(offset: 72), at: 1)
        check(moved?.acceptedFrameCount == 2 && moved?.appendedPixelHeight == 552 && moved?.warning == nil,
              "known 72px scroll creates two connected frames")
        let onePixel = repaint(fixture(offset: 72), points: [(120, 200)])
        for i in 0..<2 {
            let progress = send(document, onePixel, at: Double(i + 2))
            check(progress?.warning == nil && progress?.acceptedFrameCount == 2 && progress?.appendedPixelHeight == 552,
                  "same-position one-pixel redraw \(i + 1) preserves the frontier without a warning")
        }
        checkOutput(document, expected: fixture(offset: 0, height: 552),
                    "one-pixel final redraw exports the previously connected 552px document exactly")

        // Real failure diagnostics: a thin repaint spans 86px horizontally,
        // so the old single 64px bounding box rejected it before checking anchors.
        let thinDocument = LongCaptureFrameAccumulator()
        let thinBase = fixture(offset: 72)
        _ = send(thinDocument, fixture(offset: 0), at: 0)
        _ = send(thinDocument, thinBase, at: 1)
        let thinPoints = (0..<12).map { (110 + $0 * 7, 200 + $0 % 2) } + [(195, 201)]
        let thinRedraw = repaint(thinBase, points: thinPoints)
        let thinProgress = send(thinDocument, thinRedraw, at: 2)
        check(thinProgress?.warning == nil && thinProgress?.acceptedFrameCount == 2 && thinProgress?.appendedPixelHeight == 552,
              "13-pixel thin repaint spanning 86px keeps a uniquely anchored frontier connected")
        checkOutput(thinDocument, expected: fixture(offset: 0, height: 552),
                    "thin repaint exports the complete original document without missing rows")

        let resumed = send(thinDocument, fixture(offset: 144), at: 3)
        check(resumed?.warning == nil && resumed?.acceptedFrameCount == 3 && resumed?.appendedPixelHeight == 624,
              "scroll after a wide local repaint continues from the original committed frontier")
        checkOutput(thinDocument, expected: fixture(offset: 0, height: 624),
                    "continued capture retains every row exactly once after the thin repaint")

        // Diagnostics expose only matcher decisions and bounded scores, so a
        // failed real capture can be classified without retaining frame pixels.
        let diagnosticStitcher = LongCaptureStitcher()
        _ = diagnosticStitcher.append(frame: .init(image: fixture(offset: 0), timestamp: 0))
        let initialDiagnostics = diagnosticStitcher.lastAppendDiagnostics
        check(initialDiagnostics.frameWidth == 480 && initialDiagnostics.frameHeight == 480 &&
              initialDiagnostics.segmentYOffset == 0 && initialDiagnostics.segmentHeight == 480 &&
              initialDiagnostics.totalHeightBefore == 0 && initialDiagnostics.totalHeightAfter == 480,
              "initial diagnostics describe the original frame and committed first segment")
        _ = diagnosticStitcher.append(frame: .init(image: fixture(offset: 72), timestamp: 1))
        let connectedDiagnostics = diagnosticStitcher.lastAppendDiagnostics
        check(connectedDiagnostics.outcome == "forward-append",
              "diagnostics identify a forward append")
        check(connectedDiagnostics.forward?.outcome == "matched" &&
              connectedDiagnostics.forward?.bestShift == 72 &&
              connectedDiagnostics.forward?.overlapHeight == 408 &&
              (connectedDiagnostics.forward?.confidence ?? 0) > 0.99,
              "diagnostics preserve forward shift, overlap and confidence")
        check(connectedDiagnostics.frameWidth == 480 && connectedDiagnostics.frameHeight == 480 &&
              connectedDiagnostics.forward?.previousWidth == 480 && connectedDiagnostics.forward?.currentHeight == 480 &&
              connectedDiagnostics.forward?.footerHeight == 0 && connectedDiagnostics.cachedFooterHeight == nil &&
              connectedDiagnostics.effectiveFooterHeight == 0 &&
              connectedDiagnostics.cropRect == CGRect(x: 0, y: 408, width: 480, height: 72) &&
              connectedDiagnostics.segmentYOffset == 480 && connectedDiagnostics.segmentWidth == 480 &&
              connectedDiagnostics.segmentHeight == 72 && connectedDiagnostics.segmentCount == 2 &&
              connectedDiagnostics.totalHeightBefore == 480 && connectedDiagnostics.totalHeightAfter == 552,
              "72px diagnostics retain exact crop geometry, original dimensions and segment placement")

        let footerStitcher = LongCaptureStitcher()
        _ = footerStitcher.append(frame: .init(image: footerFixture(offset: 0), timestamp: 0))
        _ = footerStitcher.append(frame: .init(image: footerFixture(offset: 5), timestamp: 1))
        let footerDiagnostics = footerStitcher.lastAppendDiagnostics
        check(footerDiagnostics.forward?.footerHeight == 20 && footerDiagnostics.cachedFooterHeight == nil &&
              footerDiagnostics.effectiveFooterHeight == 20 &&
              footerDiagnostics.cropRect == CGRect(x: 0, y: 455, width: 480, height: 5) &&
              footerDiagnostics.footerCropRect == CGRect(x: 0, y: 460, width: 480, height: 20) &&
              footerDiagnostics.initialTrimCropRect == CGRect(x: 0, y: 0, width: 480, height: 460) &&
              footerDiagnostics.segmentYOffset == 460 && footerDiagnostics.segmentHeight == 5 &&
              footerDiagnostics.totalHeightAfter == 485,
              "fixed-footer diagnostics explain trimming, appended slice and footer placement")
        check(samePixels(footerStitcher.renderFinalImage()!.cgImage(forProposedRect: nil, context: nil, hints: nil)!,
                         footerFixture(offset: 0, height: 485)),
              "diagnosed footer geometry still renders every document row exactly once")
        _ = footerStitcher.append(frame: .init(image: footerFixture(offset: 10), timestamp: 2))
        check(footerStitcher.lastAppendDiagnostics.cachedFooterHeight == 20 &&
              footerStitcher.lastAppendDiagnostics.segmentYOffset == 465 &&
              footerStitcher.lastAppendDiagnostics.totalHeightAfter == 490,
              "subsequent diagnostics distinguish cached footer from the match result")

        let failedDiagnosticStitcher = LongCaptureStitcher()
        _ = failedDiagnosticStitcher.append(frame: .init(image: fixture(offset: 0), timestamp: 0))
        _ = failedDiagnosticStitcher.append(frame: .init(image: fixture(offset: 900), timestamp: 1))
        let failedDiagnostics = failedDiagnosticStitcher.lastAppendDiagnostics
        check(failedDiagnostics.outcome == "forward-unmatched" &&
              failedDiagnostics.forward?.outcome != "matched" &&
              (failedDiagnostics.forward?.changingColumns ?? 0) > 0,
              "diagnostics classify an unmatched forward frame without image data")

        let continued = send(document, fixture(offset: 144), at: 4)
        check(continued?.warning == nil && continued?.acceptedFrameCount == 3 && continued?.appendedPixelHeight == 624,
              "scrolling after redraw resumes from the unchanged forward frontier")
        checkOutput(document, expected: fixture(offset: 0, height: 624),
                    "continuation after redraw exports all 624px exactly once")

        let caretDocument = LongCaptureFrameAccumulator()
        _ = send(caretDocument, fixture(offset: 0), at: 0)
        _ = send(caretDocument, fixture(offset: 72), at: 1)
        let caret = repaint(fixture(offset: 72), points: rectangle(x: 110, y: 200, width: 2, height: 20))
        let caretProgress = send(caretDocument, caret, at: 2)
        check(caretProgress?.warning == nil && caretProgress?.acceptedFrameCount == 2 && caretProgress?.appendedPixelHeight == 552,
              "a localized 2x20 caret redraw does not invalidate the connected document")
        checkOutput(caretDocument, expected: fixture(offset: 0, height: 552),
                    "caret redraw preserves the connected document pixels")
        let retinaCaret = repaint(fixture(offset: 72), points: rectangle(x: 110, y: 200, width: 2, height: 40))
        let retinaProgress = send(caretDocument, retinaCaret, at: 3)
        check(retinaProgress?.warning == nil && retinaProgress?.acceptedFrameCount == 2 && retinaProgress?.appendedPixelHeight == 552,
              "a localized 2x40 Retina caret redraw preserves height and frame count")
        checkOutput(caretDocument, expected: fixture(offset: 0, height: 552),
                    "the 80-pixel Retina caret redraw preserves connected document pixels")

        let textCaretDocument = LongCaptureFrameAccumulator()
        let text = fixture(offset: 0, pattern: "rows")
        _ = send(textCaretDocument, text, at: 0)
        let textCaret = repaint(text, points: rectangle(x: 110, y: 200, width: 2, height: 20))
        let textCaretProgress = send(textCaretDocument, textCaret, at: 1)
        check(textCaretProgress?.warning == nil && textCaretProgress?.acceptedFrameCount == 1 && textCaretProgress?.appendedPixelHeight == 480,
              "a caret redraw over text rows has unchanged structure in its own columns")
        checkOutput(textCaretDocument, expected: text,
                    "text-row caret redraw preserves the original connected pixels")

        // ScreenCaptureKit frames use 32-bit BGRA. Row padding is not content.
        let bgra = LongCaptureFrameAccumulator()
        _ = send(bgra, bgraFrame(fixture(offset: 0), paddingBytes: 16, padding: 0x11), at: 0)
        let bgraMoving = bgraFrame(fixture(offset: 72), paddingBytes: 32, padding: 0xEE)
        let bgraMoved = send(bgra, bgraMoving, at: 1)
        check(bgraMoved?.warning == nil && bgraMoved?.acceptedFrameCount == 2 && bgraMoved?.appendedPixelHeight == 552,
              "32-bit BGRA scrolling accepts different row strides")
        let bgraChanged = repaint(bgraFrame(fixture(offset: 72), paddingBytes: 48, padding: 0x47),
                                  points: rectangle(x: 110, y: 200, width: 2, height: 40))
        let bgraProgress = send(bgra, bgraChanged, at: 2)
        check(bgraProgress?.warning == nil && bgraProgress?.acceptedFrameCount == 2 && bgraProgress?.appendedPixelHeight == 552,
              "32-bit BGRA localized redraw ignores differing stride padding")
        checkOutput(bgra, expected: bgraFrame(fixture(offset: 0, height: 552), paddingBytes: 0, padding: 0),
                    "BGRA redraw preserves the complete 552px document pixels")
        let bgraDedup = LongCaptureFrameDeduplicator()
        bgraDedup.markAccepted(.init(image: bgraMoving, timestamp: 0))
        if case .ignore = bgraDedup.process(frame: .init(image: bgraFrame(fixture(offset: 72), paddingBytes: 64, padding: 0x31), timestamp: 1)) {
            check(true, "32-bit BGRA exact dedup compares visible pixels independently of stride padding")
        } else {
            check(false, "32-bit BGRA exact dedup compares visible pixels independently of stride padding")
        }

        // Keep the redraw inside the overlap; new bottom rows remain the true document.
        // This checks that a real small scroll wins over approximate stationary evidence.
        for pattern in ["unique", "rows"] {
            for shift in [1, 2] {
                for withRedraw in [false, true] {
                    let small = LongCaptureFrameAccumulator()
                    _ = send(small, fixture(offset: 0, pattern: pattern), at: 0)
                    var next = fixture(offset: shift, pattern: pattern)
                    if withRedraw { next = repaint(next, points: rectangle(x: 110, y: 200, width: 2, height: 4)) }
                    let progress = send(small, next, at: 1)
                    let label = "\(pattern) \(shift)px actual scroll\(withRedraw ? " with localized redraw" : "")"
                    check(progress?.warning == nil && progress?.acceptedFrameCount == 2 && progress?.appendedPixelHeight == 480 + shift,
                          "\(label) appends exactly \(shift)px")
                    checkOutput(small, expected: fixture(offset: 0, pattern: pattern, height: 480 + shift),
                                "\(label) renders every document row exactly once")
                }
            }
        }

        let gap = LongCaptureFrameAccumulator()
        _ = send(gap, fixture(offset: 0), at: 0)
        for i in 1...2 {
            let progress = send(gap, fixture(offset: 900), at: Double(i))
            check(progress?.warning != nil && progress?.acceptedFrameCount == 1 && progress?.appendedPixelHeight == 480,
                  "genuine forward gap \(i) remains unmatched even when repeated")
        }
        checkIncomplete(gap, "a repeated genuine gap still cannot silently export the first frame")
        let restored = send(gap, repaint(fixture(offset: 0), points: [(120, 200)]), at: 3)
        check(restored?.warning == nil && restored?.acceptedFrameCount == 1 && restored?.appendedPixelHeight == 480,
              "returning to the actual frontier with a local redraw clears the retry warning")

        let periodic = LongCaptureFrameAccumulator()
        _ = send(periodic, fixture(offset: 0, pattern: "periodic"), at: 0)
        let ambiguous = send(periodic, fixture(offset: 7, pattern: "periodic"), at: 1)
        check(ambiguous?.warning != nil && ambiguous?.acceptedFrameCount == 1,
              "truly periodic moving rows remain ambiguous")
        checkIncomplete(periodic, "ambiguous periodic motion cannot export silently")

        func rejectRedraw(_ first: CGImage, _ next: CGImage, _ label: String) {
            let rejected = LongCaptureFrameAccumulator()
            _ = send(rejected, first, at: 0)
            let progress = send(rejected, next, at: 1)
            check(progress?.warning != nil && progress?.acceptedFrameCount == 1 && progress?.appendedPixelHeight == first.height,
                  "\(label) is not assumed stationary")
            checkIncomplete(rejected, "\(label) remains incomplete")
        }

        // Observed ScreenCaptureKit input: a 752x8 green stripe changes only
        // R=40 to R=41 at the same position. A final such frame must not discard
        // the already connected document; its alpha and geometry are unchanged.
        let colorDocument = LongCaptureFrameAccumulator()
        _ = send(colorDocument, colorStripeFrame(offset: 0), at: 0)
        let colorMoved = send(colorDocument, colorStripeFrame(offset: 72), at: 1)
        check(colorMoved?.warning == nil && colorMoved?.appendedPixelHeight == 872,
              "public-like color stripe accepts the known 72px scroll")
        let stripePoints = rectangle(x: 8, y: 363, width: 752, height: 8)
        for (index, deltas) in [[0, 0, 1, 0], [1, -1, 1, 0], [0, 0, -1, 0]].enumerated() {
            let redraw = changeChannels(colorStripeFrame(offset: 72), points: stripePoints, deltas: deltas)
            let progress = send(colorDocument, redraw, at: Double(index + 2))
            check(progress?.warning == nil && progress?.acceptedFrameCount == 2 && progress?.appendedPixelHeight == 872,
                  "uniform one-level RGB color redraw \(index + 1) preserves the connected frontier")
            checkOutput(colorDocument, expected: colorStripeFrame(offset: 0, height: 872),
                        "one-level color redraw \(index + 1) exports the original document pixels")
        }
        let colorContinued = send(colorDocument, colorStripeFrame(offset: 144), at: 5)
        check(colorContinued?.warning == nil && colorContinued?.acceptedFrameCount == 3 && colorContinued?.appendedPixelHeight == 944,
              "scrolling after a color redraw resumes at the original forward frontier")
        checkOutput(colorDocument, expected: colorStripeFrame(offset: 0, height: 944),
                    "continued color-stripe document contains every row exactly once")
        let stripe = colorStripeFrame(offset: 72)
        rejectRedraw(stripe, changeChannels(stripe, points: stripePoints, deltas: [0, 0, 2, 0]),
                     "a wide two-level RGB change beyond observed compositor quantization")
        rejectRedraw(stripe, changeChannels(stripe, points: stripePoints, deltas: [0, 0, 0, -1]),
                     "one-level alpha changes across a wide stripe")
        rejectRedraw(stripe, changeChannels(stripe, points: [(110, 200)], deltas: [0, 0, 0, -1]),
                     "a one-level alpha change within the old localized pixel budget")
        for (name, alphaInfo, order, channels, red, alpha) in [
            ("ARGB big endian", CGImageAlphaInfo.premultipliedFirst, CGBitmapInfo.byteOrder32Big, [3, 2, 1, 0], 1, 0),
            ("RGBA big endian", CGImageAlphaInfo.premultipliedLast, CGBitmapInfo.byteOrder32Big, [2, 1, 0, 3], 0, 3),
            ("ABGR little endian", CGImageAlphaInfo.premultipliedLast, CGBitmapInfo.byteOrder32Little, [3, 0, 1, 2], 3, 0)
        ] {
            let layout = colorLayout(stripe, alphaInfo: alphaInfo, order: order, channels: channels)
            let layoutDocument = LongCaptureFrameAccumulator()
            _ = send(layoutDocument, layout, at: 0)
            var rgbDelta = [Int](repeating: 0, count: 4); rgbDelta[red] = 1
            let progress = send(layoutDocument, changeChannels(layout, points: stripePoints, deltas: rgbDelta), at: 1)
            check(progress?.warning == nil && progress?.acceptedFrameCount == 1 && progress?.appendedPixelHeight == 800,
                  "\(name) recognizes a uniform one-level RGB redraw")
            checkOutput(layoutDocument, expected: layout, "\(name) preserves the original rendered colors")
            var alphaDelta = [Int](repeating: 0, count: 4); alphaDelta[alpha] = -1
            rejectRedraw(layout, changeChannels(layout, points: [(110, 200)], deltas: alphaDelta),
                         "\(name) one-level alpha change within the localized budget")
        }
        rejectRedraw(lowContrastPointFrame(pointY: 200), lowContrastPointFrame(pointY: 201),
                     "a one-level point really moving 1px in a column with static text anchors")
        let lowContrastRows = fixture(offset: 0, pattern: "rows")
        rejectRedraw(lowContrastRows,
                     changeChannels(lowContrastRows, points: [50, 150, 250, 350, 450].flatMap {
                         rectangle(x: 170, y: $0, width: 2, height: 5)
                     }, deltas: [-1]),
                     "one-level number-like changes spread across separated document bands")
        rejectRedraw(periodicMarkerFrame(offset: 0), periodicMarkerFrame(offset: 24),
                     "periodic text with one-level distinguishing markers really scrolling 24px")
        let blank = fixture(offset: 0, pattern: "blank")
        rejectRedraw(blank, repaint(blank, points: [(120, 479)]),
                     "one-pixel content entering a featureless viewport edge without structural anchors")
        rejectRedraw(sidebarFrame(pointY: 200), sidebarFrame(pointY: 201),
                     "a sparse point really moving 1px beside a rich static sidebar")
        rejectRedraw(sidebarFrame(pointY: 200, pointX: 180), sidebarFrame(pointY: 201, pointX: 180),
                     "a sparse point really moving 1px only 20px from a rich static sidebar")
        rejectRedraw(sidebarFrame(pointY: 200, pointX: 160), sidebarFrame(pointY: 201, pointX: 160),
                     "a sparse point really moving 1px immediately beside a rich static sidebar")
        let rich = fixture(offset: 0)
        rejectRedraw(rich, repaint(rich, points: Array(rectangle(x: 100, y: 200, width: 17, height: 16).prefix(257))),
                     "257 changed pixels exceeding the localized redraw budget")
        let periodicWidePatch = fixture(offset: 0, pattern: "periodic")
        rejectRedraw(periodicWidePatch, repaint(periodicWidePatch, points: [(100, 200), (165, 200)]),
                     "a wider local repaint on periodic content has no unique zero-position proof")
        rejectRedraw(rich, repaint(rich, points: [(100, 200), (228, 200)]),
                     "a repaint spanning 129px still exceeds the bounded local region")
        rejectRedraw(sidebarFrame(pointY: 200), repaint(sidebarFrame(pointY: 200), points: [(320, 200), (405, 201)]),
                     "a wide repaint in a blank pane cannot borrow anchors from a fixed sidebar")
        rejectRedraw(rich, brighten(rich), "a one-level brightness change across the whole viewport")
        let rows = fixture(offset: 0, pattern: "rows")
        let changedNumbers = [50, 150, 250, 350, 450].flatMap { rectangle(x: 170, y: $0, width: 2, height: 5) }
        rejectRedraw(rows, repaint(rows, points: changedNumbers),
                     "small repeated number-like changes spread across the document")

        print("RESULT: \(assertions - failures)/\(assertions) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }

    static func rectangle(x: Int, y: Int, width: Int, height: Int) -> [(Int, Int)] {
        (y..<(y + height)).flatMap { row in (x..<(x + width)).map { ($0, row) } }
    }

    static func fixture(offset: Int, pattern: String = "unique", width: Int = 480, height: Int = 480) -> CGImage {
        var pixels = [UInt8](repeating: 245, count: width * height)
        for y in 0..<height { for x in 0..<width {
            let yy = y + offset
            if pattern == "blank" { continue }
            if pattern == "unique" {
                var value = UInt32(yy * width + x + 1)
                value ^= value >> 16; value &*= 0x7feb352d; value ^= value >> 15
                value &*= 0x846ca68b; value ^= value >> 16
                pixels[y * width + x] = UInt8(value & 255)
            } else {
                let row = pattern == "periodic" ? 0 : yy / 24, line = yy % 24
                if line >= 7 && line < 16 && x > 40 && x < 200 + (row % 7) * 11 {
                    pixels[y * width + x] = UInt8(45 + (row * 13) % 100)
                }
            }
        }}
        return image(pixels, width: width, height: height)
    }

    static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func footerFixture(offset: Int, height: Int = 480) -> CGImage {
        let source = fixture(offset: offset, pattern: "rows", height: height)
        var pixels = Array(source.dataProvider!.data! as Data)
        for y in (height - 20)..<height {
            for x in 0..<source.width { pixels[y * source.bytesPerRow + x] = 90 }
        }
        return image(pixels, width: source.width, height: height)
    }

    static func repaint(_ source: CGImage, points: [(Int, Int)]) -> CGImage {
        var pixels = Array(source.dataProvider!.data! as Data)
        let pixelBytes = source.bitsPerPixel / 8
        for (x, y) in points {
            for channel in 0..<min(pixelBytes, 3) {
                pixels[y * source.bytesPerRow + x * pixelBytes + channel] ^= 255
            }
        }
        return CGImage(width: source.width, height: source.height, bitsPerComponent: source.bitsPerComponent,
                       bitsPerPixel: source.bitsPerPixel, bytesPerRow: source.bytesPerRow,
                       space: source.colorSpace!, bitmapInfo: source.bitmapInfo,
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func bgraFrame(_ gray: CGImage, paddingBytes: Int, padding: UInt8) -> CGImage {
        let grayPixels = Array(gray.dataProvider!.data! as Data)
        let stride = gray.width * 4 + paddingBytes
        var pixels = [UInt8](repeating: padding, count: stride * gray.height)
        for y in 0..<gray.height { for x in 0..<gray.width {
            let p = y * stride + x * 4
            let value = grayPixels[y * gray.bytesPerRow + x]
            pixels[p] = value; pixels[p + 1] = value; pixels[p + 2] = value; pixels[p + 3] = 255
        }}
        return CGImage(width: gray.width, height: gray.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func changeChannels(_ source: CGImage, points: [(Int, Int)], deltas: [Int]) -> CGImage {
        var pixels = Array(source.dataProvider!.data! as Data)
        let pixelBytes = source.bitsPerPixel / 8
        precondition(deltas.count == pixelBytes)
        for (x, y) in points { for channel in 0..<pixelBytes {
            let index = y * source.bytesPerRow + x * pixelBytes + channel
            pixels[index] = UInt8(max(0, min(255, Int(pixels[index]) + deltas[channel])))
        }}
        return CGImage(width: source.width, height: source.height, bitsPerComponent: source.bitsPerComponent,
                       bitsPerPixel: source.bitsPerPixel, bytesPerRow: source.bytesPerRow,
                       space: source.colorSpace!, bitmapInfo: source.bitmapInfo,
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func colorStripeFrame(offset: Int, height: Int = 800) -> CGImage {
        let base = bgraFrame(fixture(offset: offset, width: 760, height: height), paddingBytes: 16, padding: 0x73)
        var pixels = Array(base.dataProvider!.data! as Data)
        for y in 0..<height where (435..<443).contains(y + offset) {
            for x in 8..<760 {
                let index = y * base.bytesPerRow + x * 4
                pixels[index] = 84; pixels[index + 1] = 191; pixels[index + 2] = 40; pixels[index + 3] = 255
            }
        }
        return CGImage(width: base.width, height: base.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: base.bytesPerRow, space: base.colorSpace!, bitmapInfo: base.bitmapInfo,
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func colorLayout(_ bgra: CGImage, alphaInfo: CGImageAlphaInfo, order: CGBitmapInfo, channels: [Int]) -> CGImage {
        let original = Array(bgra.dataProvider!.data! as Data)
        var pixels = original
        for y in 0..<bgra.height { for x in 0..<bgra.width {
            let index = y * bgra.bytesPerRow + x * 4
            for channel in 0..<4 { pixels[index + channel] = original[index + channels[channel]] }
        }}
        return CGImage(width: bgra.width, height: bgra.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bgra.bytesPerRow, space: bgra.colorSpace!,
                       bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue | order.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func lowContrastPointFrame(pointY: Int) -> CGImage {
        let base = fixture(offset: 0, pattern: "rows")
        var pixels = Array(base.dataProvider!.data! as Data)
        // Static text exists above and below in the same column. The point still
        // really moves: its entering and departing pixels have opposite signs.
        for y in 190..<210 { pixels[y * base.bytesPerRow + 120] = 245 }
        pixels[pointY * base.bytesPerRow + 120] = 244
        return image(pixels, width: base.width, height: base.height)
    }

    static func periodicMarkerFrame(offset: Int) -> CGImage {
        let base = fixture(offset: offset, pattern: "periodic")
        var pixels = Array(base.dataProvider!.data! as Data)
        for worldY in [50, 146, 242, 338, 434] {
            let y = worldY - offset
            if (0..<base.height).contains(y) { pixels[y * base.bytesPerRow + 110] = 244 }
        }
        return image(pixels, width: base.width, height: base.height)
    }

    static func sidebarFrame(pointY: Int, pointX: Int = 360) -> CGImage {
        let width = 480, height = 480
        let rich = Array(fixture(offset: 0).dataProvider!.data! as Data)
        var pixels = [UInt8](repeating: 245, count: width * height)
        for y in 0..<height { for x in 0..<160 { pixels[y * width + x] = rich[y * width + x] } }
        pixels[pointY * width + pointX] = 40
        return image(pixels, width: width, height: height)
    }

    static func brighten(_ source: CGImage) -> CGImage {
        let pixels = Array(source.dataProvider!.data! as Data).map { UInt8(min(Int($0) + 1, 255)) }
        return image(pixels, width: source.width, height: source.height)
    }

    static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        func bytes(_ source: CGImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: source.width * source.height * 4)
            let context = CGContext(data: &result, width: source.width, height: source.height, bitsPerComponent: 8,
                                    bytesPerRow: source.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            context.setBlendMode(.copy)
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            return result
        }
        return bytes(a) == bytes(b)
    }
}
