import AppKit
import CoreVideo
import CoreImage
import Darwin

@main struct CaptureFrameMemoryChecks {
    static func main() async throws {
        if let mode = CommandLine.arguments.dropFirst().first {
            try await profile(mode)
            return
        }
        for space in [CGColorSpace(name: CGColorSpace.sRGB)!, CGColorSpace(name: CGColorSpace.displayP3)!] {
            try checkFrame(space: space)
        }
        precondition(LongCaptureImageSampling.pixelRect(width: 100, height: 100, screenRect: .zero, screenFrame: .zero) == nil)
        let screen = CGRect(x: -600, y: 120, width: 500, height: 400)
        let selection = CGRect(x: -550, y: 220, width: 150, height: 100)
        precondition(LongCaptureImageSampling.pixelRect(width: 1000, height: 800,
                                                       screenRect: selection, screenFrame: screen)
                     == CGRect(x: 100, y: 400, width: 300, height: 200))
        var unsupported: CVPixelBuffer?
        precondition(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_OneComponent8, nil, &unsupported) == kCVReturnSuccess)
        precondition(CaptureFrameImage.copy(from: unsupported!) == nil)
        print("PASS: detached BGRA frames preserve sRGB/P3 pixels, alpha, row padding, cropped dimensions and multi-display coordinates")
    }

    static func checkFrame(space: CGColorSpace) throws {
        weak var storage: PixelStorage?
        var original: Data!
        let full: CGImage = autoreleasepool {
            let bytes = PixelStorage(width: 37, height: 29, stride: 160)
            storage = bytes
            original = bytes.packed(rect: CGRect(x: 0, y: 0, width: 37, height: 29))
            var buffer: CVPixelBuffer?
            let retained = Unmanaged.passRetained(bytes).toOpaque()
            precondition(CVPixelBufferCreateWithBytes(nil, 37, 29, kCVPixelFormatType_32BGRA,
                                                      bytes.address, 160,
                                                      { info, _ in Unmanaged<PixelStorage>.fromOpaque(info!).release() },
                                                      retained, nil, &buffer) == kCVReturnSuccess)
            CVBufferSetAttachment(buffer!, kCVImageBufferCGColorSpaceKey, space, .shouldPropagate)
            let image = CaptureFrameImage.copy(from: buffer!)!
            precondition(image.width == 37 && image.height == 29 && image.bytesPerRow == 148)
            precondition(image.colorSpace?.name == space.name, "Native color profile must survive capture")
            precondition(image.alphaInfo == .premultipliedFirst)
            precondition(image.dataProvider!.data! as Data == original)
            let renderer = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
            let input = CIImage(cvPixelBuffer: buffer!)
            let reference = renderer.createCGImage(input, from: input.extent)!
            let oldPixels = rendered(reference), newPixels = rendered(image)
            let difference = zip(oldPixels, newPixels).map { abs(Int($0) - Int($1)) }.max()!
            print("RENDER \(space.name!): old/new maximum channel difference \(difference)")
            fflush(stdout)
            // CoreImage color-management rounds wide-gamut P3 values differently
            // from the native tagged provider; the measured tolerance is bounded.
            precondition(difference <= 4, "Old and new frame conversion must preserve colors, alpha and orientation")
            let rect = CGRect(x: -2, y: 3, width: 11, height: 7)
            let selected = CaptureFrameImage.copy(from: buffer!, pixelRect: rect)!
            precondition(selected.width == 9 && selected.height == 7)
            precondition(selected.dataProvider!.data! as Data == bytes.packed(rect: CGRect(x: 0, y: 3, width: 9, height: 7)))
            precondition(CaptureFrameImage.copy(from: buffer!, pixelRect: CGRect(x: 50, y: 0, width: 3, height: 3)) == nil)
            precondition(CaptureFrameImage.copy(from: buffer!, pixelRect: CGRect(x: CGFloat.nan, y: 0, width: 3, height: 3)) == nil)
            memset(bytes.address, 0, bytes.count)
            precondition(image.dataProvider!.data! as Data == original, "Reusing a stream buffer must not change the frozen screenshot")
            return image
        }
        precondition(storage == nil, "Frozen screenshot must not retain the ScreenCaptureKit pixel buffer")
        precondition(full.dataProvider!.data! as Data == original)
    }

    static func rendered(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: context.bytesPerRow * image.height)
    }

    static func profile(_ mode: String) async throws {
        precondition(["ci", "copy", "ci-long", "copy-long"].contains(mode))
        report(mode, "baseline")
        let context = mode.hasPrefix("ci") ? CIContext() : nil
        let isLong = mode.hasSuffix("long")
        let selectedRect = CGRect(x: 300, y: 300, width: 1200, height: 700)
        for iteration in 1...20 {
            autoreleasepool {
                var buffer: CVPixelBuffer?
                precondition(CVPixelBufferCreate(nil, 3840, 2160, kCVPixelFormatType_32BGRA,
                                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
                                                &buffer) == kCVReturnSuccess)
                CVBufferSetAttachment(buffer!, kCVImageBufferCGColorSpaceKey,
                                      CGColorSpace(name: CGColorSpace.displayP3)!, .shouldPropagate)
                CVPixelBufferLockBaseAddress(buffer!, [])
                memset(CVPixelBufferGetBaseAddress(buffer!)!, 173,
                       CVPixelBufferGetBytesPerRow(buffer!) * CVPixelBufferGetHeight(buffer!))
                CVPixelBufferUnlockBaseAddress(buffer!, [])
                let image: CGImage
                if let context {
                    let input = CIImage(cvPixelBuffer: buffer!)
                    let full = context.createCGImage(input, from: input.extent)!
                    image = isLong ? LongCaptureImageSampling.crop(image: full, screenRect: selectedRect,
                                                                  screenFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160))! : full
                } else {
                    let rect = isLong ? LongCaptureImageSampling.pixelRect(width: 3840, height: 2160,
                                                                         screenRect: selectedRect,
                                                                         screenFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160)) : nil
                    image = CaptureFrameImage.copy(from: buffer!, pixelRect: rect)!
                }
                let consumer = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                consumer.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
                if iteration == 1 || iteration == 20 { report(mode, "frame_\(iteration)") }
            }
        }
        report(mode, "scope_released")
        var previous = 0
        for seconds in [1, 15, 60] {
            try await Task.sleep(for: .seconds(seconds - previous))
            report(mode, "idle_\(seconds)s")
            previous = seconds
        }
        withExtendedLifetime(context) {}
    }

    static func report(_ mode: String, _ stage: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        print("SAMPLE,\(mode),\(stage),\(Double(info.phys_footprint) / 1048576),pid=\(getpid())")
        fflush(stdout)
    }
}

private final class PixelStorage {
    let address: UnsafeMutableRawPointer
    let count: Int
    let stride: Int
    init(width: Int, height: Int, stride: Int) {
        self.stride = stride
        count = stride * height
        address = .allocate(byteCount: count, alignment: 16)
        address.initializeMemory(as: UInt8.self, repeating: 0xee, count: count)
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height { for x in 0..<width {
            let i = y * stride + x * 4
            bytes[i] = UInt8((x * 7 + y * 3) % 100)
            bytes[i + 1] = UInt8((x * 2 + y * 5) % 100)
            bytes[i + 2] = UInt8((x * 3 + y * 11) % 100)
            bytes[i + 3] = UInt8(128 + (x + y) % 128)
        } }
    }
    func packed(rect: CGRect) -> Data {
        var result = Data()
        for y in Int(rect.minY)..<Int(rect.maxY) {
            result.append(address.advanced(by: y * stride + Int(rect.minX) * 4).assumingMemoryBound(to: UInt8.self),
                          count: Int(rect.width) * 4)
        }
        return result
    }
    deinit { address.deallocate() }
}
