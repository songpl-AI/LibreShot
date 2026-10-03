import Foundation
import CoreGraphics

/// Private, versioned transport. Preserve the CGImage raster instead of re-rendering it.
nonisolated enum OCRWire {
    static let version = 1
    static let maximumRasterBytes = 512 * 1024 * 1024
    static let maximumResponseBytes = 8 * 1024 * 1024

    struct Raster: Codable {
        let version: Int
        let requestID: UUID
        let width, height, bitsPerComponent, bitsPerPixel, bytesPerRow: Int
        let bitmapInfo: UInt32
        let colorProfile: Data
        let decode: [CGFloat]?
        let interpolate: Bool
        let intent: Int32
    }

    struct Response: Codable {
        let version: Int
        let requestID: UUID
        let regions: [OCRTextRegion]
        let error: String?
    }

    static func write(image: CGImage, requestID: UUID, directory: URL) throws {
        guard let pixels = image.dataProvider?.data,
              let profile = image.colorSpace?.copyICCData(),
              image.bytesPerRow > 0, image.height <= maximumRasterBytes / image.bytesPerRow,
              CFDataGetLength(pixels) == image.bytesPerRow * image.height else {
            throw OCRError.recognitionFailed("图片格式无法无损传输，或图片过大")
        }
        let components = image.colorSpace!.numberOfComponents
        let metadata = Raster(version: version, requestID: requestID, width: image.width,
                              height: image.height, bitsPerComponent: image.bitsPerComponent,
                              bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow,
                              bitmapInfo: image.bitmapInfo.rawValue, colorProfile: profile as Data,
                              decode: image.decode.map { Array(UnsafeBufferPointer(start: $0, count: components * 2)) },
                              interpolate: image.shouldInterpolate, intent: image.renderingIntent.rawValue)
        let rasterURL = directory.appendingPathComponent("raster")
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard FileManager.default.createFile(atPath: rasterURL.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              FileManager.default.createFile(atPath: metadataURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try (pixels as Data).write(to: rasterURL)
        try JSONEncoder().encode(metadata).write(to: metadataURL)
    }

    static func read(directory: URL, requestID: UUID) throws -> CGImage {
        let metadataData = try Data(contentsOf: directory.appendingPathComponent("metadata.json"))
        guard metadataData.count <= 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        let metadata = try JSONDecoder().decode(Raster.self, from: metadataData)
        guard metadata.version == version, metadata.requestID == requestID,
              metadata.width > 0, metadata.height > 0, metadata.bytesPerRow > 0,
              metadata.height <= maximumRasterBytes / metadata.bytesPerRow,
              metadata.bitsPerComponent > 0, metadata.bitsPerPixel > 0,
              metadata.width <= metadata.bytesPerRow * 8 / metadata.bitsPerPixel,
              let space = CGColorSpace(iccData: metadata.colorProfile as CFData),
              let intent = CGColorRenderingIntent(rawValue: metadata.intent),
              metadata.decode == nil || metadata.decode!.count == space.numberOfComponents * 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("raster"), options: .mappedIfSafe)
        guard data.count == metadata.bytesPerRow * metadata.height,
              let provider = CGDataProvider(data: data as CFData) else { throw CocoaError(.fileReadCorruptFile) }
        func make(_ decode: UnsafePointer<CGFloat>?) -> CGImage? {
            CGImage(width: metadata.width, height: metadata.height,
                    bitsPerComponent: metadata.bitsPerComponent, bitsPerPixel: metadata.bitsPerPixel,
                    bytesPerRow: metadata.bytesPerRow, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: metadata.bitmapInfo), provider: provider,
                    decode: decode, shouldInterpolate: metadata.interpolate, intent: intent)
        }
        let image = metadata.decode.map { $0.withUnsafeBufferPointer { make($0.baseAddress) } } ?? make(nil)
        guard let image else { throw CocoaError(.fileReadCorruptFile) }
        return image
    }

    static func validate(_ response: Response, requestID: UUID) throws -> [OCRTextRegion] {
        guard response.version == version, response.requestID == requestID,
              response.regions.count <= 100_000,
              Set(response.regions.map(\.id)).count == response.regions.count,
              response.regions.allSatisfy({ region in
                  let r = region.bounds
                  return region.id >= 0 && region.lineCount > 0 && region.text.utf8.count <= 100_000 &&
                      region.confidence.isFinite && (0...1).contains(region.confidence) &&
                      [r.origin.x, r.origin.y, r.width, r.height].allSatisfy(\.isFinite) &&
                      r.minX >= -0.001 && r.minY >= -0.001 && r.width >= 0 && r.height >= 0 &&
                      r.maxX <= 1.001 && r.maxY <= 1.001
              }) else { throw OCRError.recognitionFailed("识别进程返回了无效数据") }
        if let error = response.error { throw OCRError.recognitionFailed(String(error.prefix(500))) }
        return response.regions
    }
}
