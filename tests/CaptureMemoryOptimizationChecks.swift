import AppKit
import Darwin

@main
struct CaptureMemoryOptimizationChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            print("\(value ? "PASS" : "FAIL"): \(message)")
            if !value { failures += 1 }
        }

        let name = "LibreShot.CaptureMemory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let board = NSPasteboard(name: .init(name))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let settings = SettingsService(defaults: defaults)
        settings.autoSaveEnabled = true
        settings.saveSaveDirectory(directory)
        let service = CountingCaptureService(settings: settings, pasteboard: board) { data, url in
            guard !Thread.isMainThread else { throw MainThreadFileWriteError() }
            try data.write(to: url)
        }
        check(await startFailureCompletesCaptureOnce(), "stream start failure completes capture once")
        check(await firstFrameWinsOverLateFailure(), "first captured frame wins over a late start error")

        let mainScreen = NSScreen.main!
        let screen = mainScreen.frame
        let pixelWidth = Int(screen.width * mainScreen.backingScaleFactor)
        let pixelHeight = Int(screen.height * mainScreen.backingScaleFactor)
        let selection = CGRect(x: screen.minX + screen.width * 0.25,
                               y: screen.minY + screen.height * 0.25,
                               width: screen.width * 0.25, height: screen.height * 0.25)
        var croppedForCopy: NSImage?
        for (label, colorSpace) in [("sRGB", CGColorSpace(name: CGColorSpace.sRGB)!),
                                    ("Display P3", CGColorSpace(name: CGColorSpace.displayP3)!)] {
            let (cropped, source, expectedWidth, expectedHeight, expectedPixels) = autoreleasepool {
                () -> (NSImage, WeakPixelStorage, Int, Int, Data) in
                let storage = PixelStorage(width: pixelWidth, height: pixelHeight)
                let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(storage).toOpaque(),
                                              data: storage.bytes, size: storage.count,
                                              releaseData: { info, _, _ in
                    Unmanaged<PixelStorage>.fromOpaque(info!).release()
                })!
                let image = CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: pixelWidth * 4, space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent)!
                let input = NSImage(cgImage: image, size: screen.size)
                let sourceImage = input.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                let scaleX = CGFloat(sourceImage.width) / screen.width
                let scaleY = CGFloat(sourceImage.height) / screen.height
                let expectedRect = CGRect(x: (selection.minX - screen.minX) * scaleX,
                                          y: (screen.maxY - selection.maxY) * scaleY,
                                          width: selection.width * scaleX,
                                          height: selection.height * scaleY).integral
                let reference = sourceImage.cropping(to: expectedRect)!
                return (service.crop(image: input, to: selection)!, WeakPixelStorage(storage),
                        reference.width, reference.height, rgbaPixels(reference))
            }
            print("OBSERVED \(label) full-screen backing retained by crop: \(source.value != nil)")
            check(source.value == nil, "\(label) crop releases full-screen pixel backing")
            let cropImage = cropped.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            check(cropImage.width == expectedWidth && cropImage.height == expectedHeight,
                  "\(label) crop keeps the selected pixel dimensions")
            check(rgbaPixels(cropImage) == expectedPixels, "\(label) crop keeps color and alpha pixels")
            croppedForCopy = cropped
        }

        for (label, colorSpace) in [("sRGB", CGColorSpace(name: CGColorSpace.sRGB)!),
                                    ("Display P3", CGColorSpace(name: CGColorSpace.displayP3)!)] {
            let (crop, source, expectedPixels) = autoreleasepool { () -> (CGImage, WeakPixelStorage, Data) in
                let storage = PixelStorage(width: 1400, height: 800)
                let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(storage).toOpaque(),
                                              data: storage.bytes, size: storage.count,
                                              releaseData: { info, _, _ in
                    Unmanaged<PixelStorage>.fromOpaque(info!).release()
                })!
                let image = CGImage(width: 1400, height: 800, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 1400 * 4, space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent)!
                let reference = image.cropping(to: CGRect(x: 350, y: 200, width: 700, height: 400))!
                let pixels = rgbaPixels(reference)
                let crop = LongCaptureImageSampling.crop(
                    image: image,
                    screenRect: CGRect(x: 175, y: 100, width: 350, height: 200),
                    screenFrame: CGRect(x: 0, y: 0, width: 700, height: 400)
                )!
                return (crop, WeakPixelStorage(storage), pixels)
            }
            check(source.value == nil, "\(label) long-capture crop releases full-screen pixel backing")
            check(crop.width == 700 && crop.height == 400, "\(label) long-capture crop keeps selected dimensions")
            check(rgbaPixels(crop) == expectedPixels, "\(label) long-capture crop keeps selected pixels")
        }

        let file = try await service.completeCapture(croppedForCopy!)
        print("OBSERVED PNG encodings for copy + auto-save: \(service.pngEncodingCount)")
        check(service.pngEncodingCount == 1, "copy and auto-save encode PNG once")
        check(file != nil && FileManager.default.fileExists(atPath: file!.path), "auto-save writes a file")
        check(file.flatMap { try? Data(contentsOf: $0) } == board.data(forType: .png),
              "saved PNG and clipboard PNG are identical")
        check(board.data(forType: .tiff) != nil && board.pasteboardItems?.count == 1,
              "clipboard retains one PNG/TIFF image item")
        let explicitFile = try await service.copyAndSaveImageDirectly(croppedForCopy!)
        check(service.pngEncodingCount == 2, "explicit save-and-copy also encodes PNG once")
        check((try? Data(contentsOf: explicitFile)) == board.data(forType: .png),
              "explicit save-and-copy keeps file and clipboard identical")
        if failures > 0 { exit(1) }
    }
}

private struct MainThreadFileWriteError: Error {}
private struct SyntheticStreamError: Error {}

@MainActor
private func startFailureCompletesCaptureOnce() async -> Bool {
    do {
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
            let pending = CaptureContinuation(continuation)
            pending.fail(SyntheticStreamError())
            precondition(pending.take() == nil)
            pending.fail(SyntheticStreamError())
        }
        return false
    } catch is SyntheticStreamError {
        return true
    } catch {
        return false
    }
}

@MainActor
private func firstFrameWinsOverLateFailure() async -> Bool {
    do {
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSImage, Error>) in
            let pending = CaptureContinuation(continuation)
            pending.take()?.resume(returning: NSImage(size: NSSize(width: 1, height: 1)))
            pending.fail(SyntheticStreamError())
        }
        return image.size.width == 1
    } catch {
        return false
    }
}

private func rgbaPixels(_ image: CGImage) -> Data {
    let context = CGContext(data: nil, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Data(bytes: context.data!, count: context.bytesPerRow * image.height)
}

private final class CountingCaptureService: CaptureService {
    private(set) var pngEncodingCount = 0

    override func pngData(from image: NSImage) -> Data? {
        pngEncodingCount += 1
        return super.pngData(from: image)
    }
}

private final class PixelStorage {
    let bytes: UnsafeMutableRawPointer
    let count: Int

    init(width: Int, height: Int) {
        count = width * height * 4
        bytes = .allocate(byteCount: count, alignment: 16)
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let transparent = x % 17 == 0 && y % 13 == 0
                pixels[offset] = transparent ? 0 : UInt8(x % 251)
                pixels[offset + 1] = transparent ? 0 : UInt8(y % 251)
                pixels[offset + 2] = transparent ? 0 : 80
                pixels[offset + 3] = transparent ? 0 : 255
            }
        }
    }

    deinit { bytes.deallocate() }
}

private final class WeakPixelStorage {
    weak var value: PixelStorage?
    init(_ value: PixelStorage) { self.value = value }
}
