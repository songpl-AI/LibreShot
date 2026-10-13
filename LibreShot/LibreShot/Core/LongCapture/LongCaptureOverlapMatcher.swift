import AppKit

/// Search vertical translations in original pixel rows. Only the horizontal axis is sampled:
/// reducing height aliases small scrolls and can select a different repeated text row.
final class LongCaptureOverlapMatcher {
    private let sampleWidth = 240
    private(set) var lastDiagnostics = LongCaptureMatchDiagnostics()
    private(set) var lastStationaryDiagnostics = LongCaptureStationaryDiagnostics()
    private(set) var lastBodyBandSupport: [Int: Int] = [:]

    private func reject(_ reason: String) -> LongCaptureOverlapMatch? {
        lastDiagnostics.outcome = reason
        return nil
    }

    /// Evaluated only after motion matching fails. Original-resolution differences
    /// must be local or a one-level flat-color quantization change; a thumbnail
    /// can hide the changing numbers in rows. Color quantization keeps alpha,
    /// the original/target color pair, and alpha unchanged. A tall narrow flat
    /// patch additionally requires a unique original-resolution zero position.
    /// Require unchanged structure in the changed columns so blank/sparse frames do
    /// not turn an unknown movement or an overlap gap into a successful capture.
    func isStationaryRedraw(previous a: CGImage, current b: CGImage) -> Bool {
        lastStationaryDiagnostics = LongCaptureStationaryDiagnostics()
        lastStationaryDiagnostics.outcome = "format-or-dimension-mismatch"
        guard a.width == b.width, a.height == b.height, a.width >= 8, a.height >= 32,
              a.bitsPerComponent == 8, b.bitsPerComponent == 8,
              a.bitsPerPixel == b.bitsPerPixel, a.bitsPerPixel % 8 == 0,
              a.bitmapInfo == b.bitmapInfo, a.decode == nil, b.decode == nil,
              let ac = a.colorSpace, let bc = b.colorSpace, CFEqual(ac, bc),
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
        let pixelBytes = a.bitsPerPixel / 8
        lastStationaryDiagnostics.outcome = "unsupported-pixel-layout"
        guard (1...4).contains(pixelBytes) else { return false }
        let rowBytes = a.width * pixelBytes
        lastStationaryDiagnostics.outcome = "invalid-pixel-storage"
        guard a.bytesPerRow >= rowBytes, b.bytesPerRow >= rowBytes,
              CFDataGetLength(ad) >= (a.height - 1) * a.bytesPerRow + rowBytes,
              CFDataGetLength(bd) >= (b.height - 1) * b.bytesPerRow + rowBytes else { return false }

        // Flat-color compositor quantization can affect a wide horizontal stripe.
        // A real low-contrast translation has entering/departing color pairs;
        // accepting arbitrary one-level changes would silently lose that motion.
        let alphaByte: Int?
        var quantizedColor = false
        if pixelBytes == 4, ac.model == .rgb {
            let littleEndian = a.bitmapInfo.contains(.byteOrder32Little)
            switch a.alphaInfo {
            case .first, .premultipliedFirst, .noneSkipFirst:
                alphaByte = littleEndian ? 3 : 0
                quantizedColor = true
            case .last, .premultipliedLast, .noneSkipLast:
                alphaByte = littleEndian ? 0 : 3
                quantizedColor = true
            default: alphaByte = nil
            }
        } else {
            alphaByte = nil
            quantizedColor = (pixelBytes == 3 && ac.model == .rgb) ||
                             (pixelBytes == 1 && ac.model == .monochrome)
        }
        var originalColor: [UInt8] = [], targetColor: [UInt8] = []
        var changedPixels = 0, maximumDelta = 0
        var left = a.width, right = -1, top = a.height, bottom = -1
        var changedColumns = [Bool](repeating: false, count: a.width)
        func recordChanges(_ outcome: String) {
            lastStationaryDiagnostics.outcome = outcome
            lastStationaryDiagnostics.changedPixels = changedPixels
            lastStationaryDiagnostics.left = left
            lastStationaryDiagnostics.top = top
            lastStationaryDiagnostics.width = max(0, right - left + 1)
            lastStationaryDiagnostics.height = max(0, bottom - top + 1)
            lastStationaryDiagnostics.maximumDelta = maximumDelta
            lastStationaryDiagnostics.uniformColorPair = quantizedColor
        }
        for y in 0..<a.height {
            let ar = ap + y * a.bytesPerRow, br = bp + y * b.bytesPerRow
            for x in 0..<a.width where memcmp(ar + x * pixelBytes, br + x * pixelBytes, pixelBytes) != 0 {
                let p = ar + x * pixelBytes, q = br + x * pixelBytes
                if originalColor.isEmpty {
                    originalColor = Array(UnsafeBufferPointer(start: p, count: pixelBytes))
                    targetColor = Array(UnsafeBufferPointer(start: q, count: pixelBytes))
                }
                for channel in 0..<pixelBytes {
                    let delta = abs(Int(p[channel]) - Int(q[channel]))
                    maximumDelta = max(maximumDelta, delta)
                    if delta > 1 || p[channel] != originalColor[channel] || q[channel] != targetColor[channel] ||
                       (channel == alphaByte && delta != 0) { quantizedColor = false }
                }
                changedPixels += 1
                changedColumns[x] = true
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
                // The legacy local paths remain bounded. A taller flat-color
                // patch gets no permission here: it must separately prove a
                // filled narrow rectangle and a unique zero-position body below.
                guard quantizedColor || (bottom - top < 64 && changedPixels <= 256 && right - left < 64) else {
                    recordChanges("nonuniform-or-local-budget-exceeded")
                    return false
                }
            }
        }

        recordChanges("unsupported-change-pair")
        guard changedPixels > 0,
              quantizedColor || (maximumDelta > 1 && changedPixels <= 256 && right - left < 64) else { return false }
        let tallFlatPatch = bottom - top >= 64
        if tallFlatPatch {
            let patchWidth = right - left + 1, patchHeight = bottom - top + 1
            // This is evidence for a compositor repaint, not a larger generic
            // edit budget. Every changed pixel has one identical source/target
            // color pair with unchanged alpha. Sparse entering/departing pixels
            // from a real low-contrast translation cannot satisfy this shape.
            lastStationaryDiagnostics.uniqueZeroRequired = true
            lastStationaryDiagnostics.outcome = "nonrectangular-or-wide-tall-change"
            guard quantizedColor, patchWidth <= max(2, a.width / 16),
                  patchHeight <= a.height / 3,
                  changedPixels == patchWidth * patchHeight else { return false }
        }

        // Anchors agree at zero displacement, but differ from the next row.
        // Several separated bands must contain them; local changes alone in a
        // mostly blank viewport are not evidence that scrolling has stopped.
        // Only columns that actually changed may supply anchors: even an adjacent
        // fixed sidebar cannot establish the position of a moving sparse pane.
        // Inspect each row so narrow text/caret columns retain their text edges.
        var anchors = [Int](repeating: 0, count: 4)
        let columns = (left...right).filter { changedColumns[$0] }
        for y in 0..<(a.height - 1) {
            let band = min(3, y * 4 / a.height)
            guard anchors[band] < 8 else { continue }
            for x in columns {
                let p = ap + y * a.bytesPerRow + x * pixelBytes
                let q = ap + (y + 1) * a.bytesPerRow + x * pixelBytes
                let cp = bp + y * b.bytesPerRow + x * pixelBytes
                let cq = bp + (y + 1) * b.bytesPerRow + x * pixelBytes
                guard memcmp(p, cp, pixelBytes) == 0, memcmp(q, cq, pixelBytes) == 0 else { continue }
                if (0..<pixelBytes).contains(where: { abs(Int(p[$0]) - Int(q[$0])) >= 8 }) {
                    anchors[band] += 1
                    if anchors[band] >= 8 { break }
                }
            }
        }
        lastStationaryDiagnostics.anchorBands = anchors
        lastStationaryDiagnostics.outcome = "insufficient-unchanged-body-anchors"
        guard anchors.filter({ $0 >= 8 }).count >= 3 else { return false }
        if tallFlatPatch {
            // The supporting columns must belong to the changed body itself;
            // even a rich adjacent fixed sidebar is not a position witness.
            // Distinct original pixel-row signatures must select zero uniquely,
            // including against repeated periods hidden in a thumbnail.
            let unique = Self.hasUniqueZeroPosition(ap, bp, height: a.height,
                                                   aStride: a.bytesPerRow, bStride: b.bytesPerRow,
                                                   pixelBytes: pixelBytes, columns: columns)
            lastStationaryDiagnostics.outcome = unique ? "stationary-tall-flat-patch" : "nonunique-or-insufficient-zero-structure"
            return unique
        }
        lastStationaryDiagnostics.outcome = quantizedColor ? "stationary-flat-color" : "stationary-local-redraw"
        return true
    }

    private static func hasUniqueZeroPosition(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>,
                                               height: Int, aStride: Int, bStride: Int,
                                               pixelBytes: Int, columns: [Int]) -> Bool {
        struct Anchor { let x: Int; let y: Int; let band: Int }
        var anchors: [Anchor] = []
        var counts = [Int](repeating: 0, count: 4)
        // One signature per row, separated vertically, prevents a single text
        // edge repeated across many x positions from supplying all witnesses.
        let separation = max(2, height / 64)
        var previousRows = [Int](repeating: -separation, count: 4)
        for y in 0..<(height - 1) {
            let band = min(3, y * 4 / height)
            guard counts[band] < 8, y - previousRows[band] >= separation else { continue }
            for x in columns {
                let p = a + y * aStride + x * pixelBytes
                let q = a + (y + 1) * aStride + x * pixelBytes
                let cp = b + y * bStride + x * pixelBytes
                let cq = b + (y + 1) * bStride + x * pixelBytes
                if memcmp(p, cp, pixelBytes) == 0, memcmp(q, cq, pixelBytes) == 0,
                   (0..<pixelBytes).contains(where: { abs(Int(p[$0]) - Int(q[$0])) >= 8 }) {
                    anchors.append(Anchor(x: x, y: y, band: band))
                    counts[band] += 1; previousRows[band] = y
                    break
                }
            }
        }
        guard counts.filter({ $0 >= 4 }).count >= 3 else { return false }
        for shift in 1...(height - 32) {
            for sign in [-1, 1] {
                var available = [Int](repeating: 0, count: 4)
                var equal = [Int](repeating: 0, count: 4)
                for anchor in anchors {
                    let targetY = anchor.y + sign * shift
                    guard targetY >= 0, targetY + 1 < height else { continue }
                    available[anchor.band] += 1
                    let p = a + anchor.y * aStride + anchor.x * pixelBytes
                    let q = a + (anchor.y + 1) * aStride + anchor.x * pixelBytes
                    let cp = b + targetY * bStride + anchor.x * pixelBytes
                    let cq = b + (targetY + 1) * bStride + anchor.x * pixelBytes
                    if memcmp(p, cp, pixelBytes) == 0, memcmp(q, cq, pixelBytes) == 0 {
                        equal[anchor.band] += 1
                    }
                }
                let bands = (0..<4).filter { available[$0] >= 4 }
                if bands.count >= 2,
                   bands.allSatisfy({ equal[$0] * 10 >= available[$0] * 9 }) { return false }
            }
        }
        return true
    }

    func match(previous: CGImage, current: CGImage) -> LongCaptureOverlapMatch? {
        lastBodyBandSupport = [:]
        lastDiagnostics = LongCaptureMatchDiagnostics(width: previous.width, height: previous.height)
        lastDiagnostics.previousWidth = previous.width
        lastDiagnostics.previousHeight = previous.height
        lastDiagnostics.currentWidth = current.width
        lastDiagnostics.currentHeight = current.height
        guard previous.width == current.width, previous.height == current.height else {
            return reject("dimension-mismatch")
        }
        let width = min(sampleWidth, current.width), height = current.height
        lastDiagnostics.width = width
        lastDiagnostics.height = height
        guard height >= 32,
              let a = LongCaptureImageSampling.scale(image: previous, to: CGSize(width: width, height: height)),
              let b = LongCaptureImageSampling.scale(image: current, to: CGSize(width: width, height: height)),
              let ap = LongCaptureImageSampling.grayscalePixels(from: a),
              let bp = LongCaptureImageSampling.grayscalePixels(from: b) else {
            return reject("sampling-failed")
        }

        // Ignore static sidebars when locating the scrolling content.
        let columns = (0..<width).filter { x in
            var difference = 0.0
            for y in 0..<height {
                difference += abs(Double(ap[y * width + x]) - Double(bp[y * width + x]))
            }
            return difference / Double(height) > 1.0
        }
        lastDiagnostics.changingColumns = columns.count
        guard columns.count >= 8 else { return reject("insufficient-changing-columns") }
        let rows = (0..<height).filter { y in
            columns.reduce(0.0) { $0 + abs(Double(ap[y * width + $1]) - Double(bp[y * width + $1])) }
                / Double(columns.count) > 1.0
        }
        lastDiagnostics.changingRows = rows.count
        // A caret or small toolbar repaint can precede the scrolling body. It
        // must not expand the translation window into that fixed prefix: doing
        // so aligns unrelated header rows against the body and rejects an exact
        // motion. Range endpoints need distributed changes within the same
        // moving columns used by the global error. If that evidence is absent,
        // keep the legacy full range so sparse input earns no weaker check.
        let bodyRows = rows.filter { y in
            let changedIndices = columns.indices.filter { i in
                abs(Int(ap[y * width + columns[i]]) - Int(bp[y * width + columns[i]])) > 1
            }
            guard changedIndices.count >= max(8, columns.count / 8),
                  let first = changedIndices.first, let last = changedIndices.last,
                  last - first >= columns.count / 3 else { return false }
            return Set(changedIndices.map { min(3, $0 * 4 / columns.count) }).count >= 2
        }
        let reliableRange = bodyRows.first.flatMap { first in
            bodyRows.last.flatMap { last in last - first >= 24 ? (first, last) : nil }
        }
        guard let top = reliableRange?.0 ?? rows.first,
              let last = reliableRange?.1 ?? rows.last, last - top >= 24 else {
            return reject("insufficient-changing-rows")
        }
        lastDiagnostics.rowTop = top
        lastDiagnostics.rowBottom = last
        let bottom = last + 1
        let minOverlap = max(24, (bottom - top) / 4)
        let contrastA = Self.contrast(ap, width: width, columns: columns)
        let contrastB = Self.contrast(bp, width: width, columns: columns)
        let maximumShift = bottom - top - minOverlap
        let coarse = (1...maximumShift).map { shift in
            (shift: shift, error: Self.error(contrastA, contrastB, width: width, top: top, bottom: bottom,
                                            columns: columns, shift: shift, exhaustive: false))
        }
        // Independent body bands contribute candidate positions; they do not
        // authorize a seam. Every contributed position still undergoes the same
        // full-body exhaustive error and competing-period validation below.
        lastBodyBandSupport = Self.bodyBandCandidates(contrastA, contrastB, width: width,
                                                     top: top, bottom: bottom, columns: columns,
                                                     maximumShift: maximumShift)
        let proposedShifts = Set(lastBodyBandSupport.filter { $0.value >= 2 }.map { $0.key })
        let candidates = coarse.filter { $0.error < 0.20 || proposedShifts.contains($0.shift) }
            .sorted { $0.error < $1.error }
        lastDiagnostics.candidateCount = candidates.count
        guard let coarseBest = candidates.first else { return reject("no-coarse-candidate") }
        lastDiagnostics.coarseShift = coarseBest.shift
        lastDiagnostics.coarseError = coarseBest.error
        // Preserve all old close contenders and any independently supported
        // band proposal. Refuse too many explanations instead of discarding an
        // inconvenient repeated period to force one winning displacement.
        let contenders = candidates.filter { $0.error < coarseBest.error + 0.05 || proposedShifts.contains($0.shift) }
        lastDiagnostics.contenderCount = contenders.count
        guard contenders.count <= 64 else { return reject("too-many-contenders") }
        let verified = contenders.map { candidate in
            (shift: candidate.shift, error: Self.error(contrastA, contrastB, width: width, top: top, bottom: bottom,
                                                       columns: columns, shift: candidate.shift, exhaustive: true))
        }.sorted { $0.error < $1.error }
        guard let best = verified.first else { return reject("no-verified-candidate") }
        lastDiagnostics.bestShift = best.shift
        lastDiagnostics.bestError = best.error
        guard best.error < 0.08 else { return reject("verified-error-too-high") }
        if let second = verified.first(where: { abs($0.shift - best.shift) > 2 }),
           second.error - best.error < 0.025 {
            lastDiagnostics.secondShift = second.shift
            lastDiagnostics.secondError = second.error
            return reject("ambiguous-verified-candidates")
        }

        let footer = Self.fixedFooterHeight(ap, bp, width: width, height: height, unchangedFrom: bottom)
        lastDiagnostics.footerHeight = footer
        guard best.shift + footer < height else { return reject("overlap-outside-frame") }
        lastDiagnostics.overlapHeight = height - best.shift
        lastDiagnostics.confidence = 1 - best.error
        lastDiagnostics.outcome = "matched"
        return LongCaptureOverlapMatch(overlapHeight: height - best.shift,
                                       confidence: 1 - best.error, footerHeight: footer)
    }

    /// Propose original-row displacements independently from four body bands.
    /// Horizontal sampling stays bounded; vertical row positions never scale.
    /// Bands use only columns identified as changing, so a fixed sidebar cannot
    /// vote for motion or zero motion on behalf of a sparse scrolling pane.
    private static func bodyBandCandidates(_ a: [Double], _ b: [Double], width: Int,
                                            top: Int, bottom: Int, columns: [Int],
                                            maximumShift: Int) -> [Int: Int] {
        var support: [Int: Int] = [:]
        for band in 0..<4 {
            let bandTop = top + (bottom - top) * band / 4
            let bandBottom = top + (bottom - top) * (band + 1) / 4
            let candidates = (1...maximumShift).compactMap { shift -> (shift: Int, error: Double)? in
                let end = min(bandBottom, bottom - shift)
                guard end - bandTop >= 24 else { return nil }
                var difference = 0.0, energy = 0.0
                let rowStep = max(1, (end - bandTop) / 32)
                let colStep = max(1, columns.count / 32)
                for y in stride(from: bandTop, to: end, by: rowStep) {
                    for i in stride(from: 0, to: columns.count, by: colStep) {
                        let x = columns[i]
                        let av = a[(y + shift) * width + x], bv = b[y * width + x]
                        difference += abs(av - bv)
                        energy += max(abs(av), abs(bv))
                    }
                }
                guard energy > 1000 else { return nil }
                let error = difference / energy
                return error < 0.20 ? (shift, error) : nil
            }.sorted { $0.error < $1.error }
            // Bound work and retain competitors. A band with many equivalent
            // periods supplies no additional direction evidence.
            guard candidates.count <= 64 else { continue }
            for candidate in candidates.prefix(4) { support[candidate.shift, default: 0] += 1 }
        }
        return support
    }

    private static func fixedFooterHeight(_ a: [UInt8], _ b: [UInt8], width: Int,
                                          height: Int, unchangedFrom bottom: Int) -> Int {
        guard bottom < height else { return 0 }
        // A fixed bar needs both a stable suffix and an actual horizontal boundary.
        // Blank spacing after the last text row is not a footer, regardless of its height.
        for y in bottom..<height {
            var boundaryColumns = 0
            var unchanged = 0.0
            for x in 0..<width {
                if abs(Int(a[y * width + x]) - Int(a[(y - 1) * width + x])) > 3 { boundaryColumns += 1 }
                unchanged += abs(Double(a[y * width + x]) - Double(b[y * width + x]))
            }
            if boundaryColumns > width / 2, unchanged / Double(width) < 0.5 {
                return height - y
            }
        }
        return 0
    }

    private static func contrast(_ pixels: [UInt8], width: Int, columns: [Int]) -> [Double] {
        var result = [Double](repeating: 0, count: pixels.count)
        for y in 0..<(pixels.count / width) {
            let row = y * width
            // The normalization baseline must use the same moving body as the
            // error calculation. A textured fixed sidebar has unrelated rows
            // after translation and would otherwise bias even an exact seam.
            let samples = stride(from: 0, to: columns.count, by: max(1, columns.count / 24))
                .map { pixels[row + columns[$0]] }.sorted()
            let background = Double(samples[samples.count / 2])
            for x in 0..<width { result[row + x] = Double(pixels[row + x]) - background }
        }
        return result
    }

    private static func error(_ a: [Double], _ b: [Double], width: Int, top: Int, bottom: Int,
                              columns: [Int], shift: Int, exhaustive: Bool) -> Double {
        var difference = 0.0, energy = 0.0
        let rowStep = exhaustive ? 1 : max(1, (bottom - top - shift) / 64)
        let colStep = max(1, columns.count / (exhaustive ? 120 : 32))
        for y in stride(from: top, to: bottom - shift, by: rowStep) {
            let ay = (y + shift) * width, by = y * width
            for i in stride(from: 0, to: columns.count, by: colStep) {
                let x = columns[i]
                let av = a[ay + x], bv = b[by + x]
                difference += abs(av - bv)
                energy += max(abs(av), abs(bv))
            }
        }
        return energy > 1000 ? difference / energy : .infinity
    }
}

