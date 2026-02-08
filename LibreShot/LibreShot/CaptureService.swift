import AppKit
import ScreenCaptureKit
import CoreImage
import CoreGraphics
import Vision

enum CaptureServiceError: Error {
    case noDisplay
    case permissionDenied
    case captureFailed
    case imageConversionFailed
    case saveCancelled
    case saveFailed(underlying: Error)
}

extension CaptureServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "未找到可用显示器"
        case .permissionDenied:
            return "未获得屏幕录制权限"
        case .captureFailed:
            return "截图失败"
        case .imageConversionFailed:
            return "图片转换失败"
        case .saveCancelled:
            return "用户取消保存"
        case .saveFailed(let underlying):
            return (underlying as NSError).localizedDescription
        }
    }
}

final class CaptureService {
    static let shared = CaptureService()

    private let outputQueue = DispatchQueue(label: "com.myscreenshots.capture.output")
    // Disable caching of intermediates to save memory, as we don't do complex chains that reuse them often
    let context = CIContext(options: [.cacheIntermediates: false])
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var isStopping = false

    // Updated to accept optional displayID. If nil, captures main display.
    func captureDisplayImage(displayID: CGDirectDisplayID? = nil) async throws -> NSImage {
        isStopping = false
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureServiceError.permissionDenied
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw CaptureServiceError.permissionDenied
        }
        
        let display: SCDisplay
        if let targetID = displayID {
            guard let found = content.displays.first(where: { $0.displayID == targetID }) else {
                throw CaptureServiceError.noDisplay
            }
            display = found
        } else {
            // Fallback to first (usually main)
            guard let first = content.displays.first else {
                throw CaptureServiceError.noDisplay
            }
            display = first
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let output = CaptureStreamOutput { [weak self] sampleBuffer in
                self?.handleSampleBuffer(sampleBuffer)
            }
            self.streamOutput = output
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            self.stream = stream
            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.outputQueue)
                try stream.startCapture()
            } catch {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func saveToDefaultLocation(_ image: NSImage) throws -> URL {
        // Try to use configured directory
        if let result = SettingsService.shared.withSaveDirectory(block: { directoryURL -> URL? in
            return try? self.saveToDirectory(image, directoryURL: directoryURL)
        }), let savedURL = result {
            return savedURL
        }
        
        // Fallback to Desktop
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            throw CaptureServiceError.saveFailed(underlying: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError))
        }
        return try saveToDirectory(image, directoryURL: desktopURL)
    }
    
    private func saveToDirectory(_ image: NSImage, directoryURL: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MyScreenShots_\(formatter.string(from: Date())).png"
        let fileURL = directoryURL.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureServiceError.imageConversionFailed
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw CaptureServiceError.saveFailed(underlying: error)
        }
    }
    
    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func recognizeText(in image: NSImage, recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US"]) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.missingImage
        }
        return try await recognizeText(in: cgImage, recognitionLanguages: recognitionLanguages)
    }

    func recognizeText(in image: CGImage, recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US"]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            autoreleasepool {
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = self.buildOCRText(from: observations)
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if !recognitionLanguages.isEmpty {
                    request.recognitionLanguages = recognitionLanguages
                }
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try handler.perform([request])
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func saveImageWithFallback(_ image: NSImage) async throws -> URL {
        do {
            return try saveToDefaultLocation(image)
        } catch {
            if isPermissionError(error) {
                return try await saveWithPanel(image)
            }
            throw error
        }
    }

    @MainActor
    private func saveWithPanel(_ image: NSImage) async throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MyScreenShots_\(formatter.string(from: Date())).png"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.png]
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw CaptureServiceError.saveCancelled
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureServiceError.imageConversionFailed
        }

        do {
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            throw CaptureServiceError.saveFailed(underlying: error)
        }
    }

    func crop(image: NSImage, to rect: CGRect, displayID: CGDirectDisplayID? = nil) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // Find target screen
        var targetScreen: NSScreen?
        if let id = displayID {
            targetScreen = NSScreen.screens.first { 
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id 
            }
        }
        if targetScreen == nil { targetScreen = NSScreen.main }
        guard let screen = targetScreen else { return nil }
        
        let screenFrame = screen.frame
        
        // Calculate scale factor (Retina display handling)
        let xScale = CGFloat(cgImage.width) / screenFrame.width
        let yScale = CGFloat(cgImage.height) / screenFrame.height
        
        // Rect is in points (SwiftUI coordinates, Top-Left origin)
        // CGImage cropping expects pixels, Top-Left origin
        let scaledRect = CGRect(
            x: rect.origin.x * xScale,
            y: rect.origin.y * yScale,
            width: rect.width * xScale,
            height: rect.height * yScale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: scaledRect) else { return nil }
        
        // Apply rounded corners if enabled
        if SettingsService.shared.useRoundedCorners {
            return applyRoundedCorners(to: croppedCGImage, size: rect.size)
        }
        
        // Return image with point size matching the selection rect
        return NSImage(cgImage: croppedCGImage, size: rect.size)
    }
    
    private func applyRoundedCorners(to cgImage: CGImage, size: NSSize) -> NSImage? {
        // Use actual pixel dimensions from the CGImage to preserve resolution
        let width = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = 8
        let bytesPerRow = 4 * width
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        // Rect in pixel coordinates
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // Scale radius based on resolution (assuming size is points)
        // Calculate scale factor by comparing pixel width to point width
        let scale = CGFloat(width) / size.width
        let radius: CGFloat = 8.0 * scale // Scaled corner radius
        
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        
        context.draw(cgImage, in: rect)
        
        guard let resultCGImage = context.makeImage() else { return nil }
        // Return NSImage with original point size but high-res backing
        return NSImage(cgImage: resultCGImage, size: size)
    }

    private func isPermissionError(_ error: Error) -> Bool {
        guard let captureError = error as? CaptureServiceError else { return false }
        guard case let .saveFailed(underlying) = captureError else { return false }
        let nsError = underlying as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
    }

    private func buildOCRText(from observations: [VNRecognizedTextObservation]) -> String {
        let blocks: [(CGRect, String)] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (observation.boundingBox, candidate.string)
        }
        if blocks.isEmpty {
            return ""
        }
        let sorted = blocks.sorted { lhs, rhs in
            let lhsY = lhs.0.maxY
            let rhsY = rhs.0.maxY
            if abs(lhsY - rhsY) > 0.02 {
                return lhsY > rhsY
            }
            return lhs.0.minX < rhs.0.minX
        }
        var lines: [[(CGRect, String)]] = []
        var currentLine: [(CGRect, String)] = []
        var currentY: CGFloat?
        let lineThreshold: CGFloat = 0.025
        for item in sorted {
            let y = item.0.maxY
            if let existingY = currentY, abs(y - existingY) > lineThreshold {
                lines.append(currentLine)
                currentLine = [item]
                currentY = y
            } else {
                currentLine.append(item)
                if currentY == nil {
                    currentY = y
                }
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        let text = lines.map { line in
            line.sorted { $0.0.minX < $1.0.minX }.map { $0.1 }.joined(separator: " ")
        }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        autoreleasepool {
            guard let continuation else { return }
            // Note: continuation needs to be captured carefully if we nil it out outside, 
            // but here we are inside the function.
            // However, we can't nil out self.continuation inside autoreleasepool easily if we want to be thread safe 
            // or we need to be careful.
            // Let's just wrap the heavy lifting.
            
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continuation.resume(throwing: CaptureServiceError.captureFailed)
                self.continuation = nil
                stopStream()
                return
            }

            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                continuation.resume(throwing: CaptureServiceError.imageConversionFailed)
                self.continuation = nil
                stopStream()
                return
            }

            let size = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
            let nsImage = NSImage(cgImage: cgImage, size: size)
            continuation.resume(returning: nsImage)
            self.continuation = nil
            stopStream()
        }
    }

    private func stopStream() {
        if isStopping { return }
        isStopping = true
        let stream = self.stream
        let output = self.streamOutput
        Task { [weak self] in
            if let stream {
                try? await stream.stopCapture()
                if let output {
                    try? await stream.removeStreamOutput(output, type: .screen)
                }
            }
            self?.stream = nil
            self?.streamOutput = nil
            self?.isStopping = false
        }
    }
}

final class CaptureStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        handler(sampleBuffer)
    }
}
