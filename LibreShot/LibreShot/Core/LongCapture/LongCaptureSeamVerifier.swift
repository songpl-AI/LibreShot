import AppKit

/// The reduced matcher only proposes a translation. Verify its visible body in
/// original pixels, independently of thumbnail contrast or correlation scores.
/// Static columns/prefixes do not establish motion; a small isolated repaint in
/// the overlap may be omitted because the committed document already has it.
enum LongCaptureSeamVerifier {
    static func sameSuffix(previous a: CGImage, current b: CGImage, height: Int) -> Bool {
        guard height > 0, height < a.height, a.width == b.width, a.height == b.height,
              a.bitsPerComponent == b.bitsPerComponent, a.bitsPerPixel == b.bitsPerPixel,
              a.bitmapInfo == b.bitmapInfo, a.bitsPerPixel % 8 == 0, a.decode == nil, b.decode == nil,
              let ac = a.colorSpace, let bc = b.colorSpace, CFEqual(ac, bc),
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        let (rowBytes, rowOverflow) = a.width.multipliedReportingOverflow(by: a.bitsPerPixel / 8)
        let (aBytes, aOverflow) = a.bytesPerRow.multipliedReportingOverflow(by: a.height)
        let (bBytes, bOverflow) = b.bytesPerRow.multipliedReportingOverflow(by: b.height)
        guard !rowOverflow, !aOverflow, !bOverflow, rowBytes > 0,
              a.bytesPerRow >= rowBytes, b.bytesPerRow >= rowBytes,
              CFDataGetLength(ad) >= aBytes, CFDataGetLength(bd) >= bBytes else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
        for y in (a.height - height)..<a.height {
            if memcmp(ap + y * a.bytesPerRow, bp + y * b.bytesPerRow, rowBytes) != 0 { return false }
        }
        return true
    }

    static func verify(previous a: CGImage, current b: CGImage, shift: Int, footerHeight: Int, allowRedraw: Bool = true, bodyStart: Int? = nil) -> Bool {
        guard a.width == b.width, a.height == b.height, shift > 0, footerHeight >= 0,
              footerHeight < a.height, shift < a.height - footerHeight else { return false }
        if a.bitsPerComponent != b.bitsPerComponent || a.bitsPerPixel != b.bitsPerPixel ||
            a.bitmapInfo != b.bitmapInfo || a.colorSpace == nil || b.colorSpace == nil ||
            !CFEqual(a.colorSpace!, b.colorSpace!) || a.decode != nil || b.decode != nil {
            guard let aa = LongCaptureDocumentStore.detached(a), let bb = LongCaptureDocumentStore.detached(b) else { return false }
            return verify(previous: aa, current: bb, shift: shift, footerHeight: footerHeight, allowRedraw: allowRedraw, bodyStart: bodyStart)
        }
        guard a.bitsPerComponent == 8, a.bitsPerPixel % 8 == 0,
              a.bitsPerPixel >= 8, a.bitsPerPixel <= 32,
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        let pixelBytes = a.bitsPerPixel / 8
        let (rowBytes, rowOverflow) = a.width.multipliedReportingOverflow(by: pixelBytes)
        let (aLength, aOverflow) = a.bytesPerRow.multipliedReportingOverflow(by: a.height)
        let (bLength, bOverflow) = b.bytesPerRow.multipliedReportingOverflow(by: b.height)
        guard !rowOverflow, !aOverflow, !bOverflow, a.bytesPerRow >= rowBytes, b.bytesPerRow >= rowBytes,
              CFDataGetLength(ad) >= aLength, CFDataGetLength(bd) >= bLength else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
        let bodyEnd = a.height - footerHeight
        var columns: [Int] = []
        var firstChangingRow = bodyEnd
        for x in 0..<a.width {
            for y in 0..<bodyEnd {
                if memcmp(ap + y * a.bytesPerRow + x * pixelBytes,
                          bp + y * b.bytesPerRow + x * pixelBytes, pixelBytes) != 0 {
                    columns.append(x)
                    firstChangingRow = min(firstChangingRow, y)
                    break
                }
            }
        }
        let overlapEnd = bodyEnd - shift
        var top = bodyStart ?? firstChangingRow
        guard !columns.isEmpty, top >= 0, overlapEnd - top >= 24 else { return false }
        var changed: [(x: Int, y: Int)] = []
        // A statistical body top may skip sparse moving text above it. Ignore a
        // prefix only when its zero-position differences are a tiny local patch;
        // otherwise verify all original changing rows under the motion itself.
        var prefixMinX = a.width, prefixMaxX = 0, prefixMinY = bodyEnd, prefixMaxY = 0
        var prefixIsLocal = true
        var prefixSource: [UInt8]?, prefixTarget: [UInt8]?
        var uniformSource = true, uniformTarget = true
        outer: for y in 0..<top {
            for x in 0..<a.width {
                if memcmp(ap + y * a.bytesPerRow + x * pixelBytes,
                          bp + y * b.bytesPerRow + x * pixelBytes, pixelBytes) != 0 {
                    let source = UnsafeBufferPointer(start: ap + y * a.bytesPerRow + x * pixelBytes, count: pixelBytes)
                    let target = UnsafeBufferPointer(start: bp + y * b.bytesPerRow + x * pixelBytes, count: pixelBytes)
                    if let first = prefixSource { uniformSource = uniformSource && source.elementsEqual(first) }
                    else { prefixSource = Array(source) }
                    if let first = prefixTarget { uniformTarget = uniformTarget && target.elementsEqual(first) }
                    else { prefixTarget = Array(target) }
                    changed.append((x, y))
                    prefixMinX = min(prefixMinX, x); prefixMaxX = max(prefixMaxX, x)
                    prefixMinY = min(prefixMinY, y); prefixMaxY = max(prefixMaxY, y)
                    if changed.count > 64 || prefixMaxX - prefixMinX >= 32 || prefixMaxY - prefixMinY >= 32 {
                        prefixIsLocal = false
                        break outer
                    }
                }
            }
        }
        if !prefixIsLocal || (!uniformSource && !uniformTarget) {
            top = firstChangingRow
            changed.removeAll(keepingCapacity: true)
        } else if !allowRedraw && !changed.isEmpty {
            // A heuristic footer may coexist with a genuine moving body. Verify
            // its full original overlap rather than letting the heuristic erase
            // narrow text or localized pixel evidence at the beginning.
            top = firstChangingRow
            changed.removeAll(keepingCapacity: true)
        }
        guard overlapEnd - top >= 24 else { return false }
        var verifiedPixels = 0
        for y in top..<overlapEnd {
            for x in columns {
                if memcmp(ap + (y + shift) * a.bytesPerRow + x * pixelBytes,
                          bp + y * b.bytesPerRow + x * pixelBytes, pixelBytes) == 0 {
                    verifiedPixels += 1
                } else {
                    guard allowRedraw, y < overlapEnd - 16 else { return false }
                    changed.append((x, y))
                    // Bounded transient pixels cannot excuse a different seam,
                    // a growing full-width bar, or a large changed body band.
                    if changed.count > 128 { return false }
                }
            }
        }
        guard verifiedPixels >= 128, changed.count * 100 <= verifiedPixels else { return false }
        // A transient caret can appear twice in aligned frames: its old location
        // translated into the overlap, and its new screen location. Check each
        // connected patch rather than treating that distance as a giant repaint.
        var remaining = Set(changed.map { $0.y * a.width + $0.x })
        var components = 0
        while let first = remaining.first {
            components += 1
            guard components <= 2 else { return false }
            remaining.remove(first)
            var queue = [first], index = 0
            var minX = first % a.width, maxX = minX
            var minY = first / a.width, maxY = minY
            while index < queue.count {
                let point = queue[index]; index += 1
                let x = point % a.width, y = point / a.width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                guard maxX - minX < 64, maxY - minY < 64 else { return false }
                var neighbors = [point - a.width, point + a.width]
                if x > 0 { neighbors.append(point - 1) }
                if x < a.width - 1 { neighbors.append(point + 1) }
                for neighbor in neighbors where remaining.remove(neighbor) != nil { queue.append(neighbor) }
            }
        }
        return true
    }
}
