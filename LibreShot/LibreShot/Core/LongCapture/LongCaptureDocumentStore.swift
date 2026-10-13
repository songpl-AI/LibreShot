import AppKit

/// Limits bound the store and final bitmap separately; they are not a promise
/// about total process RSS, which also includes capture, editor and export work.
struct LongCaptureLimits {
    var residentDocumentBytes = 32 * 1024 * 1024
    var maximumOutputBytes = 128 * 1024 * 1024
    var maximumFrameBytes = 64 * 1024 * 1024
    var maximumSegments = 20_000
}

enum LongCaptureDocumentStoreError: Error, Equatable {
    case invalidLimits
    case invalidImage
    case invalidPlacement
    case outputLimit
    case frameLimit
    case segmentLimit
    case storageFailure
    case rendererFailure
}

struct LongCaptureSegment {
    let image: CGImage
    let yOffset: Int
}

/// Canonical, lossless, contiguous document strips on the engine's serial queue.
/// Spills contain only independent RGBA bytes, never a retained capture buffer.
final class LongCaptureDocumentStore {
    private struct Strip {
        let yOffset: Int
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let byteCount: Int
        var image: CGImage?
        var file: URL?
    }

    private var strips: [Strip] = []
    private var directory: URL?
    let limits: LongCaptureLimits
    private(set) var residentBytes = 0
    private(set) var spilledBytes = 0
    private(set) var totalHeight = 0
    var count: Int { strips.count }
    var firstHeight: Int? { strips.first?.height }
    var width: Int? { strips.first?.width }

    init(limits: LongCaptureLimits = LongCaptureLimits()) { self.limits = limits }

    deinit {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private var validLimits: Bool {
        limits.residentDocumentBytes >= 0 && limits.maximumOutputBytes > 0 &&
            limits.maximumFrameBytes > 0 && limits.maximumSegments > 0
    }

    private static func byteLayout(width: Int, height: Int) -> (row: Int, count: Int)? {
        guard width > 0, height > 0 else { return nil }
        let (row, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow else { return nil }
        let (count, countOverflow) = row.multipliedReportingOverflow(by: height)
        guard !countOverflow else { return nil }
        return (row, count)
    }

    func permits(width: Int, height: Int) -> Bool {
        guard validLimits, let bytes = Self.byteLayout(width: width, height: height) else { return false }
        return bytes.count <= limits.maximumOutputBytes
    }

    /// Materialize a crop so it cannot retain the full source frame's provider.
    /// Callers with a custom frame budget can pass that same budget here.
    static func detached(_ image: CGImage, maximumBytes: Int = 64 * 1024 * 1024) -> CGImage? {
        guard maximumBytes > 0,
              let bytes = byteLayout(width: image.width, height: image.height),
              bytes.count <= maximumBytes,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: bytes.row,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func canonicalData(_ image: CGImage) -> (data: CFData, row: Int, count: Int)? {
        guard let bytes = byteLayout(width: image.width, height: image.height),
              image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.bytesPerRow == bytes.row, image.decode == nil,
              image.bitmapInfo == CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              let colorSpace = image.colorSpace, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              CFEqual(colorSpace, srgb), let data = image.dataProvider?.data,
              CFDataGetLength(data) == bytes.count else { return nil }
        return (data, bytes.row, bytes.count)
    }

    func image(at index: Int) -> CGImage? {
        guard strips.indices.contains(index) else { return nil }
        return try? load(strips[index])
    }

    func placement(at index: Int) -> (yOffset: Int, height: Int)? {
        guard strips.indices.contains(index) else { return nil }
        return (strips[index].yOffset, strips[index].height)
    }

    func append(_ image: CGImage, at yOffset: Int) throws {
        guard validLimits else { throw LongCaptureDocumentStoreError.invalidLimits }
        guard strips.count < limits.maximumSegments else { throw LongCaptureDocumentStoreError.segmentLimit }
        guard yOffset == totalHeight, strips.first.map({ $0.width == image.width }) ?? true else {
            throw LongCaptureDocumentStoreError.invalidPlacement
        }
        let strip = try makeStrip(image, at: yOffset)
        try commit(strips + [strip])
    }

    /// Stage the entire replacement, including every spill, before changing any
    /// accepted placement. Used for first-frame trimming plus its first append.
    func replace(with segments: [LongCaptureSegment]) throws {
        guard validLimits else { throw LongCaptureDocumentStoreError.invalidLimits }
        guard segments.count <= limits.maximumSegments else { throw LongCaptureDocumentStoreError.segmentLimit }
        var proposed: [Strip] = []
        proposed.reserveCapacity(segments.count)
        var expectedOffset = 0
        let proposedWidth = segments.first?.image.width
        for segment in segments {
            guard segment.yOffset == expectedOffset, segment.image.width == proposedWidth else {
                throw LongCaptureDocumentStoreError.invalidPlacement
            }
            let strip = try makeStrip(segment.image, at: segment.yOffset)
            let (end, overflow) = expectedOffset.addingReportingOverflow(strip.height)
            guard !overflow else { throw LongCaptureDocumentStoreError.outputLimit }
            expectedOffset = end
            proposed.append(strip)
        }
        try commit(proposed)
    }

    private func makeStrip(_ image: CGImage, at yOffset: Int) throws -> Strip {
        guard yOffset >= 0 else { throw LongCaptureDocumentStoreError.invalidPlacement }
        let (end, overflow) = yOffset.addingReportingOverflow(image.height)
        guard !overflow, permits(width: image.width, height: end) else {
            throw LongCaptureDocumentStoreError.outputLimit
        }
        guard let value = Self.canonicalData(image) else { throw LongCaptureDocumentStoreError.invalidImage }
        guard value.count <= limits.maximumFrameBytes else { throw LongCaptureDocumentStoreError.frameLimit }
        return Strip(yOffset: yOffset, width: image.width, height: image.height,
                     bytesPerRow: value.row, byteCount: value.count, image: image, file: nil)
    }

    private func validateCoverage(_ proposed: [Strip], height: Int) throws {
        guard height >= 0 else { throw LongCaptureDocumentStoreError.invalidPlacement }
        var end = 0
        let expectedWidth = proposed.first?.width
        for strip in proposed {
            guard strip.yOffset == end, strip.width == expectedWidth, strip.height > 0,
                  let bytes = Self.byteLayout(width: strip.width, height: strip.height),
                  bytes.row == strip.bytesPerRow, bytes.count == strip.byteCount else {
                throw LongCaptureDocumentStoreError.invalidPlacement
            }
            let (nextEnd, overflow) = end.addingReportingOverflow(strip.height)
            guard !overflow else { throw LongCaptureDocumentStoreError.outputLimit }
            end = nextEnd
        }
        guard end == height else { throw LongCaptureDocumentStoreError.invalidPlacement }
    }

    private func commit(_ proposed: [Strip]) throws {
        let proposedHeight: Int
        if let last = proposed.last {
            let (end, overflow) = last.yOffset.addingReportingOverflow(last.height)
            guard !overflow else { throw LongCaptureDocumentStoreError.outputLimit }
            proposedHeight = end
        } else {
            proposedHeight = 0
        }
        try validateCoverage(proposed, height: proposedHeight)
        var next = proposed
        var resident = 0
        var spilled = 0
        for strip in next {
            let (sum, overflow) = (strip.image == nil ? spilled : resident).addingReportingOverflow(strip.byteCount)
            guard !overflow else { throw LongCaptureDocumentStoreError.outputLimit }
            if strip.image == nil { spilled = sum } else { resident = sum }
        }
        let existingDirectory = directory
        var created: [URL] = []
        do {
            for index in next.indices where resident > limits.residentDocumentBytes && next[index].image != nil {
                let strip = next[index]
                guard let image = strip.image, let value = Self.canonicalData(image),
                      value.count == strip.byteCount else { throw LongCaptureDocumentStoreError.invalidImage }
                let target = try spoolDirectory().appendingPathComponent(UUID().uuidString + ".rgba")
                // Register before writing, so any partial target is removed on failure.
                created.append(target)
                try (value.data as Data).write(to: target, options: .atomic)
                next[index].file = target
                next[index].image = nil
                resident -= strip.byteCount
                spilled += strip.byteCount // Both totals are bounded by the validated document.
            }
        } catch {
            created.forEach { try? FileManager.default.removeItem(at: $0) }
            if existingDirectory == nil, let newDirectory = directory {
                try? FileManager.default.removeItem(at: newDirectory)
                directory = nil
            }
            if let typed = error as? LongCaptureDocumentStoreError { throw typed }
            throw LongCaptureDocumentStoreError.storageFailure
        }
        let retainedFiles = Set(next.compactMap(\.file))
        let obsoleteFiles = strips.compactMap(\.file).filter { !retainedFiles.contains($0) }
        strips = next
        residentBytes = resident
        spilledBytes = spilled
        totalHeight = proposedHeight
        obsoleteFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        if strips.isEmpty, let directory {
            try? FileManager.default.removeItem(at: directory)
            self.directory = nil
        }
    }

    private func spoolDirectory() throws -> URL {
        if let directory { return directory }
        let value = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibreShot-LongCapture-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        directory = value
        return value
    }

    private func load(_ strip: Strip) throws -> CGImage {
        if let image = strip.image {
            guard let value = Self.canonicalData(image), value.count == strip.byteCount else {
                throw LongCaptureDocumentStoreError.invalidImage
            }
            return image
        }
        guard let file = strip.file else { throw LongCaptureDocumentStoreError.storageFailure }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let fileBytes = attributes[.size] as? NSNumber,
                  fileBytes.int64Value == Int64(strip.byteCount) else {
                throw LongCaptureDocumentStoreError.storageFailure
            }
            let data = try Data(contentsOf: file, options: .alwaysMapped)
            guard data.count == strip.byteCount,
                  let provider = CGDataProvider(data: data as CFData),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let image = CGImage(width: strip.width, height: strip.height, bitsPerComponent: 8,
                                      bitsPerPixel: 32, bytesPerRow: strip.bytesPerRow, space: colorSpace,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw LongCaptureDocumentStoreError.storageFailure
            }
            return image
        } catch {
            throw LongCaptureDocumentStoreError.storageFailure
        }
    }

    /// The body must cover exactly height - footer.height. Each spilled strip is
    /// mapped, drawn synchronously and released before opening the next strip.
    func render(height: Int, footer: CGImage? = nil) throws -> CGImage {
        guard validLimits else { throw LongCaptureDocumentStoreError.invalidLimits }
        guard let width, permits(width: width, height: height) else {
            throw LongCaptureDocumentStoreError.outputLimit
        }
        let footerHeight = footer?.height ?? 0
        let (bodyHeight, overflow) = height.subtractingReportingOverflow(footerHeight)
        guard !overflow, bodyHeight > 0 else { throw LongCaptureDocumentStoreError.invalidPlacement }
        try validateCoverage(strips, height: bodyHeight)
        if let footer {
            guard footer.width == width, let data = Self.canonicalData(footer) else {
                throw LongCaptureDocumentStoreError.invalidImage
            }
            guard data.count <= limits.maximumFrameBytes else { throw LongCaptureDocumentStoreError.frameLimit }
        }
        guard let bytes = Self.byteLayout(width: width, height: height),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytes.row,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw LongCaptureDocumentStoreError.rendererFailure
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        for strip in strips {
            try autoreleasepool {
                let image = try load(strip)
                context.draw(image, in: CGRect(x: 0, y: height - strip.yOffset - strip.height,
                                              width: width, height: strip.height))
            }
        }
        if let footer { context.draw(footer, in: CGRect(x: 0, y: 0, width: width, height: footerHeight)) }
        guard let output = context.makeImage() else { throw LongCaptureDocumentStoreError.rendererFailure }
        return output
    }

    /// Compare a covered document interval without constructing the full image.
    /// Nil means invalid range/format/I/O; -1 means all requested rows are equal.
    func firstDifferentRow(from image: CGImage, documentStart: Int, imageStart: Int,
                           rowCount: Int) -> Int? {
        let (imageEnd, imageOverflow) = imageStart.addingReportingOverflow(rowCount)
        let (documentEnd, documentOverflow) = documentStart.addingReportingOverflow(rowCount)
        guard rowCount > 0, imageStart >= 0, documentStart >= 0,
              !imageOverflow, !documentOverflow, imageEnd <= image.height, documentEnd <= totalHeight,
              image.width == width, let incoming = Self.canonicalData(image),
              let pointer = CFDataGetBytePtr(incoming.data) else { return nil }
        defer { withExtendedLifetime(incoming.data) {} }
        var covered = documentStart
        var low = 0, high = strips.count
        while low < high {
            let mid = low + (high - low) / 2
            if strips[mid].yOffset + strips[mid].height <= documentStart { low = mid + 1 }
            else { high = mid }
        }
        for index in low..<strips.count {
            if covered == documentEnd { break }
            let strip = strips[index]
            let lower = max(documentStart, strip.yOffset)
            let upper = min(documentEnd, strip.yOffset + strip.height)
            guard lower == covered, upper > lower, strip.width == image.width else { return nil }
            do {
                let difference: Int? = try autoreleasepool {
                    let stored = try load(strip)
                    guard let storedData = stored.dataProvider?.data,
                          let storedPointer = CFDataGetBytePtr(storedData) else {
                        throw LongCaptureDocumentStoreError.storageFailure
                    }
                    defer { withExtendedLifetime(storedData) {} }
                    for y in lower..<upper {
                        let a = pointer + (imageStart + (y - documentStart)) * incoming.row
                        let b = storedPointer + (y - strip.yOffset) * strip.bytesPerRow
                        if memcmp(a, b, incoming.row) != 0 { return y }
                    }
                    return nil
                }
                if let difference { return difference }
            } catch { return nil }
            covered = upper
        }
        return covered == documentEnd ? -1 : nil
    }
}
