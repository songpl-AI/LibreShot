import AppKit
import ImageIO
import Darwin

func makeImage(width: Int, height: Int, logical: NSSize, space: CGColorSpace, alpha: Bool, noise: Bool = false,
               rowPadding: Int = 0, littleEndian: Bool = false, decodeMap: Bool = false) -> NSImage {
    let stride = width * 4 + rowPadding
    let count = stride * height
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 16)
    pointer.initializeMemory(as: UInt8.self,repeating: 0xAC,count: count)
    let p = pointer.assumingMemoryBound(to: UInt8.self)
    var state: UInt64 = 0xCF924B63
    for y in 0..<height {
        for x in 0..<width {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let off = y * stride + x * 4
            let a = alpha ? UInt8((x * 11 + y * 17) % 256) : 255
            let values = noise ? [UInt8(truncatingIfNeeded: state >> 24), UInt8(truncatingIfNeeded: state >> 40), UInt8(truncatingIfNeeded: state >> 48)]
                               : [UInt8((x * 13 + y * 3) % 256), UInt8((y * 7 + x) % 256), UInt8((x * 5 + y * 19) % 256)]
            let rgba = [UInt8(Int(values[0]) * Int(a) / 255),UInt8(Int(values[1]) * Int(a) / 255),UInt8(Int(values[2]) * Int(a) / 255),a]
            for i in 0..<4 { p[off+i] = rgba[littleEndian ? 3-i : i] }
        }
    }
    let provider = CGDataProvider(dataInfo: pointer, data: pointer, size: count,
        releaseData: { data, _, _ in data!.deallocate() })!
    var map: [CGFloat] = [1,0,0,1,0,1]
    let cg = map.withUnsafeMutableBufferPointer { values in
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: stride, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | (littleEndian ? CGBitmapInfo.byteOrder32Little : .byteOrder32Big).rawValue),
                provider: provider, decode: decodeMap ? values.baseAddress : nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    return NSImage(cgImage: cg, size: logical)
}

// Same canonical sRGB RGBA draw used by CaptureMemoryOptimizationChecks.
func pixels(_ image: CGImage) -> Data {
    let context = CGContext(data: nil, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: context.data!, count: context.bytesPerRow * image.height)
}

func decoded(_ data: Data) -> (CGImage, [String: String]) {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    var metadata: [String: String] = [:]
    for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
                kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
                kCGImagePropertyDepth, kCGImagePropertyHasAlpha,
                kCGImagePropertyColorModel, kCGImagePropertyProfileName] {
        metadata[key as String] = props[key].map { String(describing: $0) } ?? "missing"
    }
    return (image, metadata)
}


@main
struct CaptureExportPixelChecks {
    @MainActor static func main() throws {
        let domain = "LibreShot.ExportPixels.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let board = NSPasteboard(name: .init(domain))
        defer { board.releaseGlobally() }
        let settings = SettingsService(defaults: defaults)
        let current = CaptureService(settings: settings, pasteboard: board)
        let reference = LegacyNormalizedExport(settings: settings, pasteboard: board)
        var checks = 0, failures = 0
        func check(_ source: NSImage, _ candidate: CaptureService, _ baseline: CaptureService, _ label: String) {
            checks += 1
            let before = pixels(source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            guard let expectedData = baseline.pngData(from: source), let actualData = candidate.pngData(from: source) else {
                print("FAIL: \(label) must export PNG")
                failures += 1
                return
            }
            let expected = decoded(expectedData), actual = decoded(actualData)
            let pass = pixels(expected.0) == pixels(actual.0) && expected.1 == actual.1 &&
                before == pixels(source.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            print("\(pass ? "PASS" : "FAIL"): \(label) preserves normalized pixels, metadata and input")
            if !pass { failures += 1 }
        }
        for (label, space) in [("sRGB", CGColorSpace(name: CGColorSpace.sRGB)!),
                               ("Display P3", CGColorSpace(name: CGColorSpace.displayP3)!)] {
            for (width, height, logical) in [(160,80,NSSize(width:80,height:40)),
                                           (5,3,NSSize(width:2.5,height:1.5)),
                                           (257,111,NSSize(width:97.5,height:53.25))] {
                for alpha in [false, true] { for rounded in [false, true] {
                    autoreleasepool {
                        settings.useRoundedCorners = rounded
                        let source = makeImage(width:width,height:height,logical:logical,space:space,alpha:alpha)
                        check(source,current,reference,"\(label) \(width)x\(height) alpha=\(alpha) rounded=\(rounded)")
                    }
                }}
            }
        }
        settings.useRoundedCorners = false
        for padding in [0, 16] { for little in [false, true] { for decode in [false, true] {
            autoreleasepool {
                let source = makeImage(width:117,height:47,logical:NSSize(width:58.5,height:23.5),
                                       space:CGColorSpace(name:CGColorSpace.sRGB)!,alpha:true,
                                       rowPadding:padding,littleEndian:little,decodeMap:decode)
                check(source,current,reference,"row padding=\(padding) little endian=\(little) decode=\(decode)")
            }
        }}}
        settings.useRoundedCorners = true
        let alreadyStyled = AlreadyStyledPNGExport(settings: settings, pasteboard: board)
        let styledReference = LegacyAlreadyStyledExport(settings: settings, pasteboard: board)
        check(makeImage(width:160,height:80,logical:NSSize(width:80,height:40),
                        space:CGColorSpace(name:CGColorSpace.sRGB)!,alpha:true),
              alreadyStyled,styledReference,"already-styled export preserves styledImage override")
        print("RESULT: \(checks-failures)/\(checks) passed; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}

/// Exercise the old normalization path with the same PNG encoder and styling.
private class LegacyNormalizedExport: CaptureService {
    override func bitmapRep(from image: NSImage, opaque: Bool = false, reuseExportPixels: Bool = false) -> NSBitmapImageRep? {
        super.bitmapRep(from: image, opaque: opaque)
    }
}
private final class AlreadyStyledPNGExport: CaptureService {
    override func styledImage(_ image: NSImage) -> NSImage { image }
}
private final class LegacyAlreadyStyledExport: LegacyNormalizedExport {
    override func styledImage(_ image: NSImage) -> NSImage { image }
}
