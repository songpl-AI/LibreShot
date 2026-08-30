import AppKit
import ScreenCaptureKit
import CoreImage
import CoreGraphics
import Vision
import Combine

enum CaptureServiceError: Error {
    case noDisplay
    case permissionDenied
    case captureFailed
    case imageConversionFailed
}


class CaptureService {
    static let shared = CaptureService()
    
    let context = CIContext()
    private let exportColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let outputQueue = DispatchQueue(label: "com.libreshot.capture")
    private let continuationLock = NSLock()
    
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var isStopping = false
    private var currentScale: CGFloat = 1.0
    
    init() {}
    
    func saveImageWithFallback(_ image: NSImage) async throws -> URL {
        return try await MainActor.run {
            let previousActivationPolicy = NSApp.activationPolicy()
            let shouldRestoreAccessoryPolicy = previousActivationPolicy == .accessory
            if shouldRestoreAccessoryPolicy {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            defer {
                if shouldRestoreAccessoryPolicy {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.isExtensionHidden = false
            savePanel.title = "保存截图"
            savePanel.message = "选择保存截图的位置"
            savePanel.nameFieldStringValue = "Screenshot \(Date().formatted(date: .numeric, time: .standard)).png"
            savePanel.level = .modalPanel
            let response = savePanel.runModal()
            
            guard response == .OK, let url = savePanel.url else {
                throw CancellationError()
            }
            
            guard let pngData = pngData(from: image) else {
                throw CaptureServiceError.imageConversionFailed
            }
            
            try pngData.write(to: url)
            return url
        }
    }

    /// 直接保存到预设目录（不弹保存面板）。目录优先级：设置里的「保存位置」→ ~/Pictures。
    func saveImageDirectly(_ image: NSImage) async throws -> URL {
        let directory = SettingsService.shared.saveDirectory
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        guard let pngData = pngData(from: image) else {
            throw CaptureServiceError.imageConversionFailed
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let baseName = "Screenshot \(formatter.string(from: Date()))"

        var url = directory.appendingPathComponent("\(baseName).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName) (\(counter)).png")
            counter += 1
        }

        let accessed = SettingsService.shared.saveDirectory != nil && directory.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        try pngData.write(to: url)
        return url
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        guard let pngData = pngData(from: image) else {
            pasteboard.writeObjects([image])
            return
        }
        
        pasteboard.setData(pngData, forType: .png)
        
        if let normalizedImage = NSImage(data: pngData),
           let tiffData = normalizedImage.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
        
        if let normalizedImage = NSImage(data: pngData) {
            pasteboard.writeObjects([normalizedImage])
        }
    }
    
    func crop(image: NSImage, to rect: CGRect, displayID: CGDirectDisplayID? = nil) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        // Find the screen's frame to calculate relative coordinates
        var screenFrame = NSScreen.main?.frame ?? .zero
        if let id = displayID, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
        }) {
            screenFrame = screen.frame
        }
        
        // Calculate scale factor based on actual image pixels vs screen points
        // cgImage is in pixels, screenFrame is in points
        let scaleX = CGFloat(cgImage.width) / screenFrame.width
        let scaleY = CGFloat(cgImage.height) / screenFrame.height
        
        // Calculate the crop rect in image coordinates (Pixels)
        // rect is in global screen coordinates (bottom-left origin)
        let x = (rect.origin.x - screenFrame.origin.x) * scaleX
        
        // For y, we need to flip it because CGImage origin is top-left, but screen is bottom-left
        // (screenFrame.height - relativeY - rectHeight)
        let relativeY = rect.origin.y - screenFrame.origin.y
        let y = (screenFrame.height - relativeY - rect.height) * scaleY
        
        let width = rect.width * scaleX
        let height = rect.height * scaleY
        
        let cropRect = CGRect(x: x, y: y, width: width, height: height)
        
        // Ensure crop rect is within image bounds to prevent failure due to rounding errors
        let imageRect = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let finalRect = cropRect.intersection(imageRect)
        
        if finalRect.isNull || finalRect.isEmpty {
            print("CaptureService: Crop rect is empty. Input: \(rect), Calculated: \(cropRect)")
            return nil
        }
        
        guard let croppedCGImage = cgImage.cropping(to: finalRect) else {
            print("CaptureService: CGImage cropping failed")
            return nil
        }
        
        // Return image with the logical size of the cropped area (Points)
        let finalSize = CGSize(width: finalRect.width / scaleX, height: finalRect.height / scaleY)
        return NSImage(cgImage: croppedCGImage, size: finalSize)
    }
    
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
        
        // Calculate scale factor and physical dimensions
        var scale: CGFloat = 1.0
        var physicalWidth: Int = display.width
        var physicalHeight: Int = display.height
        
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            scale = screen.backingScaleFactor
            // Force use of NSScreen's physical pixel count calculation for reliability
            // This fixes issues where SCDisplay might report logical or scaled sizes
            physicalWidth = Int(screen.frame.width * scale)
            physicalHeight = Int(screen.frame.height * scale)
        }
        self.currentScale = scale
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        
        // Ensure we capture at physical resolution
        configuration.width = physicalWidth
        configuration.height = physicalHeight
        configuration.scalesToFit = false // Ensure no automatic scaling occurs
        
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false

        return try await withCheckedThrowingContinuation { continuation in
            continuationLock.lock()
            self.continuation = continuation
            continuationLock.unlock()
            
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
                continuationLock.lock()
                self.continuation = nil
                continuationLock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Safety check for invalid buffer
        if CVPixelBufferGetWidth(imageBuffer) == 0 || CVPixelBufferGetHeight(imageBuffer) == 0 {
            return
        }
        
        continuationLock.lock()
        guard let continuation = self.continuation else {
            continuationLock.unlock()
            return
        }
        // Claim the continuation
        self.continuation = nil
        continuationLock.unlock()
        
        // Convert to NSImage
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        let context = self.context
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Convert on the output queue or a background task, not main actor if possible,
            // but continuation.resume is thread-safe.
            // We are inside Task, so we are async.
            
            let ciImage = CIImage(cvImageBuffer: imageBuffer)
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                continuation.resume(throwing: CaptureServiceError.imageConversionFailed)
                // self.continuation is already nil
                stopStream()
                return
            }

            // Use the captured scale to set the correct logical size (Points)
            let scale = self.currentScale
            let size = NSSize(width: ciImage.extent.width / scale, height: ciImage.extent.height / scale)
            let nsImage = NSImage(cgImage: cgImage, size: size)
            continuation.resume(returning: nsImage)
            // self.continuation is already nil
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
                    try? stream.removeStreamOutput(output, type: .screen)
                }
            }
            self?.stream = nil
            self?.streamOutput = nil
            self?.isStopping = false
        }
    }

    func bitmapRep(from image: NSImage, opaque: Bool = true) -> NSBitmapImageRep? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let bitmapContext = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: exportColorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }
        
        bitmapContext.interpolationQuality = .high
        
        if opaque {
            bitmapContext.setFillColor(NSColor.white.cgColor)
            bitmapContext.fill(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        } else {
            bitmapContext.clear(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        
        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        guard let normalizedImage = bitmapContext.makeImage() else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: normalizedImage)
        bitmapRep.size = image.size
        return bitmapRep
    }
    
    func pngData(from image: NSImage) -> Data? {
        bitmapRep(from: image)?.representation(using: .png, properties: [:])
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

struct LongCaptureRegion {
    let selectionRect: CGRect
    let screenRect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
}

struct LongCaptureProgress {
    let acceptedFrameCount: Int
    let appendedPixelHeight: Int
}

enum LongCaptureStatus: Equatable {
    case idle
    case capturing
    case paused
    case finishing
    case completed
    case cancelled
    case failed(String)
}

enum LongCaptureError: LocalizedError {
    case noStableFrame
    case rendererFailed
    
    var errorDescription: String? {
        switch self {
        case .noStableFrame:
            return "未采集到有效的滚动帧，请重试"
        case .rendererFailed:
            return "长截图拼接失败"
        }
    }
}

struct LongCaptureFrame {
    let image: CGImage
    let timestamp: CFTimeInterval
}

struct LongCaptureAppendResult {
    let accepted: Bool
    let appendedPixelHeight: Int
}

final class LongCaptureSession: ObservableObject {
    @Published private(set) var status: LongCaptureStatus = .idle
    @Published private(set) var progress = LongCaptureProgress(acceptedFrameCount: 0, appendedPixelHeight: 0)
    
    private let region: LongCaptureRegion
    private let captureService = LongCaptureStreamService()
    private let stabilityAnalyzer = LongCaptureFrameStabilityAnalyzer()
    private let stitcher = LongCaptureStitcher()
    private var isStarted = false
    
    init(region: LongCaptureRegion) {
        self.region = region
    }
    
    func start() async throws {
        guard !isStarted else { return }
        isStarted = true
        await MainActor.run {
            self.status = .capturing
        }
        try await captureService.start(region: region) { [weak self] frame in
            self?.handle(frame: frame)
        }
    }
    
    func pause() async {
        captureService.pause()
        await MainActor.run {
            self.status = .paused
        }
    }
    
    func resume() async {
        captureService.resume()
        await MainActor.run {
            self.status = .capturing
        }
    }
    
    func finish() async throws -> NSImage {
        await MainActor.run {
            self.status = .finishing
        }
        await captureService.stop()
        guard let image = stitcher.renderFinalImage() else {
            await MainActor.run {
                self.status = .failed(LongCaptureError.rendererFailed.localizedDescription)
            }
            throw LongCaptureError.rendererFailed
        }
        await MainActor.run {
            self.status = .completed
        }
        return image
    }
    
    func cancel() async {
        await captureService.stop()
        await MainActor.run {
            self.status = .cancelled
        }
    }
    
    private func handle(frame: LongCaptureFrame) {
        guard captureService.isRunning else { return }
        switch stabilityAnalyzer.process(frame: frame) {
        case .ignore:
            return
        case .accept(let acceptedFrame):
            let result = stitcher.append(frame: acceptedFrame)
            guard result.accepted else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progress = LongCaptureProgress(
                    acceptedFrameCount: self.stitcher.acceptedFrameCount,
                    appendedPixelHeight: self.stitcher.totalPixelHeight
                )
            }
        }
    }
}

private enum LongCaptureFrameDecision {
    case ignore
    case accept(LongCaptureFrame)
}

private final class LongCaptureFrameStabilityAnalyzer {
    private let duplicateThreshold: Double = 1.8
    private let minimumAcceptedInterval: CFTimeInterval = 0.09
    private var lastAcceptedSignature: LongCaptureThumbnailSignature?
    private var lastAcceptedTimestamp: CFTimeInterval = 0
    
    func process(frame: LongCaptureFrame) -> LongCaptureFrameDecision {
        guard let signature = LongCaptureThumbnailSignature(image: frame.image) else {
            return .ignore
        }
        
        guard let lastAcceptedSignature else {
            self.lastAcceptedSignature = signature
            self.lastAcceptedTimestamp = frame.timestamp
            return .accept(frame)
        }
        
        if frame.timestamp - lastAcceptedTimestamp < minimumAcceptedInterval {
            return .ignore
        }
        
        let difference = signature.averageDifference(from: lastAcceptedSignature)
        if difference < duplicateThreshold {
            return .ignore
        } else {
            self.lastAcceptedSignature = signature
            self.lastAcceptedTimestamp = frame.timestamp
            return .accept(frame)
        }
    }
}

private struct LongCaptureThumbnailSignature {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    
    init?(image: CGImage) {
        let targetWidth = 24
        let targetHeight = max(Int(round(CGFloat(targetWidth) * CGFloat(image.height) / CGFloat(max(image.width, 1)))), 24)
        guard let scaledImage = LongCaptureImageSampling.scale(image: image, to: CGSize(width: targetWidth, height: targetHeight)),
              let pixels = LongCaptureImageSampling.grayscalePixels(from: scaledImage) else {
            return nil
        }
        self.pixels = pixels
        self.width = scaledImage.width
        self.height = scaledImage.height
    }
    
    func averageDifference(from other: LongCaptureThumbnailSignature) -> Double {
        let count = min(pixels.count, other.pixels.count)
        guard count > 0 else { return .greatestFiniteMagnitude }
        var total = 0.0
        for index in 0..<count {
            total += abs(Double(pixels[index]) - Double(other.pixels[index]))
        }
        return total / Double(count)
    }
}

private final class LongCaptureStitcher {
    private let overlapMatcher = LongCaptureOverlapMatcher()
    private var segments: [LongCaptureSegment] = []
    private var logicalCanvasSize: CGSize = .zero
    private(set) var totalPixelHeight = 0
    private(set) var acceptedFrameCount = 0
    
    func append(frame: LongCaptureFrame) -> LongCaptureAppendResult {
        if segments.isEmpty {
            logicalCanvasSize = CGSize(width: frame.image.width, height: frame.image.height)
            totalPixelHeight = frame.image.height
            acceptedFrameCount = 1
            segments = [LongCaptureSegment(image: frame.image, yOffset: 0)]
            return LongCaptureAppendResult(accepted: true, appendedPixelHeight: frame.image.height)
        }
        
        guard let previousImage = segments.last?.sourceImage ?? segments.last?.image,
              let match = overlapMatcher.match(previous: previousImage, current: frame.image) else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }
        
        let appendStartY = match.overlapHeight
        let appendHeight = frame.image.height - appendStartY
        guard appendHeight >= 24 else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }
        
        let cropRect = CGRect(x: 0, y: appendStartY, width: frame.image.width, height: appendHeight)
        guard let appendedImage = frame.image.cropping(to: cropRect.integral) else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }
        
        segments.append(
            LongCaptureSegment(
                image: appendedImage,
                yOffset: totalPixelHeight,
                sourceImage: frame.image
            )
        )
        totalPixelHeight += appendHeight
        acceptedFrameCount += 1
        return LongCaptureAppendResult(accepted: true, appendedPixelHeight: appendHeight)
    }
    
    func renderFinalImage() -> NSImage? {
        guard let firstSegment = segments.first else { return nil }
        let width = firstSegment.image.width
        guard width > 0, totalPixelHeight > 0 else { return nil }
        guard let colorSpace = firstSegment.image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        for segment in segments {
            let drawRect = CGRect(
                x: 0,
                y: totalPixelHeight - segment.yOffset - segment.image.height,
                width: segment.image.width,
                height: segment.image.height
            )
            context.draw(segment.image, in: drawRect)
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        let logicalHeight = CGFloat(totalPixelHeight) * logicalCanvasSize.height / CGFloat(max(firstSegment.image.height, 1))
        let logicalSize = NSSize(width: logicalCanvasSize.width, height: logicalHeight)
        return NSImage(cgImage: cgImage, size: logicalSize)
    }
}

private struct LongCaptureSegment {
    let image: CGImage
    let yOffset: Int
    let sourceImage: CGImage?
    
    init(image: CGImage, yOffset: Int, sourceImage: CGImage? = nil) {
        self.image = image
        self.yOffset = yOffset
        self.sourceImage = sourceImage
    }
}

private struct LongCaptureOverlapMatch {
    let overlapHeight: Int
    let confidence: Double
}

private struct LongCaptureOverlapCandidate {
    let overlap: Int
    let confidence: Double
}

private final class LongCaptureOverlapMatcher {
    private let sampleWidth = 240
    private let minimumOverlap = 24
    private let maximumOverlap = 720
    private let confidenceThreshold = 0.72
    private let coarseStride = 4
    private let refineRadius = 6
    private let ambiguityTolerance = 0.012
    
    func match(previous: CGImage, current: CGImage) -> LongCaptureOverlapMatch? {
        let previousHeight = max(Int(round(CGFloat(sampleWidth) * CGFloat(previous.height) / CGFloat(max(previous.width, 1)))), sampleWidth)
        let currentHeight = max(Int(round(CGFloat(sampleWidth) * CGFloat(current.height) / CGFloat(max(current.width, 1)))), sampleWidth)
        guard let previousScaled = LongCaptureImageSampling.scale(image: previous, to: CGSize(width: sampleWidth, height: previousHeight)),
              let currentScaled = LongCaptureImageSampling.scale(image: current, to: CGSize(width: sampleWidth, height: currentHeight)),
              let previousPixels = LongCaptureImageSampling.grayscalePixels(from: previousScaled),
              let currentPixels = LongCaptureImageSampling.grayscalePixels(from: currentScaled) else {
            return nil
        }
        let previousRows = rowSignatures(from: previousPixels, width: sampleWidth, height: previousScaled.height)
        let currentRows = rowSignatures(from: currentPixels, width: sampleWidth, height: currentScaled.height)
        
        let maxOverlap = min(maximumOverlap, previousScaled.height - 8, currentScaled.height - 8)
        let minOverlap = min(minimumOverlap, maxOverlap)
        guard minOverlap >= minimumOverlap else { return nil }
        
        var coarseBest: LongCaptureOverlapCandidate?
        var coarseSecondBest: LongCaptureOverlapCandidate?
        for overlap in stride(from: minOverlap, through: maxOverlap, by: coarseStride) {
            let candidate = LongCaptureOverlapCandidate(
                overlap: overlap,
                confidence: score(
                    previousPixels: previousPixels,
                    previousHeight: previousScaled.height,
                    previousRows: previousRows,
                    currentPixels: currentPixels,
                    currentHeight: currentScaled.height,
                    currentRows: currentRows,
                    overlap: overlap
                )
            )
            
            if coarseBest == nil {
                coarseBest = candidate
            } else if let currentBest = coarseBest, candidate.confidence > currentBest.confidence {
                coarseSecondBest = currentBest
                coarseBest = candidate
            } else if let currentSecondBest = coarseSecondBest {
                if candidate.confidence > currentSecondBest.confidence {
                    coarseSecondBest = candidate
                }
            } else {
                coarseSecondBest = candidate
            }
        }
        
        guard let coarseBest else { return nil }
        
        var bestMatch: LongCaptureOverlapCandidate?
        let refineStart = max(minOverlap, coarseBest.overlap - refineRadius)
        let refineEnd = min(maxOverlap, coarseBest.overlap + refineRadius)
        for overlap in refineStart...refineEnd {
            let candidate = LongCaptureOverlapCandidate(
                overlap: overlap,
                confidence: score(
                    previousPixels: previousPixels,
                    previousHeight: previousScaled.height,
                    previousRows: previousRows,
                    currentPixels: currentPixels,
                    currentHeight: currentScaled.height,
                    currentRows: currentRows,
                    overlap: overlap
                )
            )
            if let bestMatch, candidate.confidence <= bestMatch.confidence {
                continue
            }
            bestMatch = candidate
        }
        
        guard let bestMatch, bestMatch.confidence >= confidenceThreshold else {
            return nil
        }
        
        if let coarseSecondBest,
           abs(bestMatch.overlap - coarseSecondBest.overlap) > coarseStride,
           bestMatch.confidence - coarseSecondBest.confidence < ambiguityTolerance {
            return nil
        }
        
        return LongCaptureOverlapMatch(
            overlapHeight: Int(round(CGFloat(bestMatch.overlap) * CGFloat(current.height) / CGFloat(currentScaled.height))),
            confidence: bestMatch.confidence
        )
    }
    
    private func score(
        previousPixels: [UInt8],
        previousHeight: Int,
        previousRows: [LongCaptureRowSignature],
        currentPixels: [UInt8],
        currentHeight: Int,
        currentRows: [LongCaptureRowSignature],
        overlap: Int
    ) -> Double {
        let rawScore = similarity(
            previousPixels: previousPixels,
            previousHeight: previousHeight,
            currentPixels: currentPixels,
            currentHeight: currentHeight,
            width: sampleWidth,
            overlap: overlap
        )
        let rowScore = rowSimilarity(
            previousRows: previousRows,
            currentRows: currentRows,
            overlap: overlap
        )
        let overlapBias = min(Double(overlap) / Double(max(maximumOverlap, 1)), 1) * 0.02
        return rawScore * 0.72 + rowScore * 0.28 + overlapBias
    }
    
    private func similarity(previousPixels: [UInt8], previousHeight: Int, currentPixels: [UInt8], currentHeight: Int, width: Int, overlap: Int) -> Double {
        let previousStartRow = previousHeight - overlap
        var total = 0.0
        var sampleCount = 0
        for row in stride(from: 0, to: overlap, by: 2) {
            let previousRowIndex = (previousStartRow + row) * width
            let currentRowIndex = row * width
            for column in stride(from: Int(Double(width) * 0.15), to: Int(Double(width) * 0.85), by: 2) {
                let previousValue = previousPixels[previousRowIndex + column]
                let currentValue = currentPixels[currentRowIndex + column]
                total += abs(Double(previousValue) - Double(currentValue))
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return 0 }
        let averageDifference = total / Double(sampleCount)
        return max(0, 1.0 - averageDifference / 255.0)
    }
    
    private func rowSignatures(from pixels: [UInt8], width: Int, height: Int) -> [LongCaptureRowSignature] {
        guard width > 0, height > 0 else { return [] }
        return (0..<height).map { row in
            let rowOffset = row * width
            var brightnessTotal = 0.0
            var edgeTotal = 0.0
            var previousValue = Double(pixels[rowOffset])
            for column in 0..<width {
                let value = Double(pixels[rowOffset + column])
                brightnessTotal += value
                if column > 0 {
                    edgeTotal += abs(value - previousValue)
                }
                previousValue = value
            }
            return LongCaptureRowSignature(
                brightness: brightnessTotal / Double(width),
                edge: edgeTotal / Double(max(width - 1, 1))
            )
        }
    }
    
    private func rowSimilarity(previousRows: [LongCaptureRowSignature], currentRows: [LongCaptureRowSignature], overlap: Int) -> Double {
        guard previousRows.count >= overlap, currentRows.count >= overlap, overlap > 0 else {
            return 0
        }
        let previousSlice = previousRows[(previousRows.count - overlap)..<previousRows.count]
        let currentSlice = currentRows[..<overlap]
        var totalDifference = 0.0
        var sampleCount = 0
        for (previousRow, currentRow) in zip(previousSlice, currentSlice) {
            totalDifference += abs(previousRow.brightness - currentRow.brightness)
            totalDifference += abs(previousRow.edge - currentRow.edge) * 0.8
            sampleCount += 2
        }
        guard sampleCount > 0 else { return 0 }
        let averageDifference = totalDifference / Double(sampleCount)
        return max(0, 1.0 - averageDifference / 255.0)
    }
}

private struct LongCaptureRowSignature {
    let brightness: Double
    let edge: Double
}

private final class LongCaptureStreamService {
    private let context = CIContext()
    private let outputQueue = DispatchQueue(label: "com.libreshot.long-capture")
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var region: LongCaptureRegion?
    private var onFrame: ((LongCaptureFrame) -> Void)?
    private var minimumFrameInterval: CFTimeInterval = 0.10
    private var lastEmissionTimestamp: CFTimeInterval = 0
    private(set) var isRunning = false
    private var isPaused = false
    
    func start(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureServiceError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureServiceError.noDisplay
        }
        
        self.region = region
        self.onFrame = onFrame
        self.lastEmissionTimestamp = 0
        self.isPaused = false
        
        let excludedApplications: [SCRunningApplication]
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            excludedApplications = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
        } else {
            excludedApplications = []
        }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.minimumFrameInterval = CMTime(seconds: minimumFrameInterval, preferredTimescale: 600)
        
        let output = CaptureStreamOutput { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        
        self.streamOutput = output
        self.stream = stream
        self.isRunning = true
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        lastEmissionTimestamp = 0
        isPaused = false
    }
    
    func stop() async {
        guard let stream else {
            isRunning = false
            return
        }
        isRunning = false
        try? await stream.stopCapture()
        if let streamOutput {
            try? stream.removeStreamOutput(streamOutput, type: .screen)
        }
        self.stream = nil
        self.streamOutput = nil
        self.onFrame = nil
        self.region = nil
    }
    
    private func handle(sampleBuffer: CMSampleBuffer) {
        guard isRunning, !isPaused, let region, let onFrame else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if lastEmissionTimestamp > 0, timestamp - lastEmissionTimestamp < minimumFrameInterval {
            return
        }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let fullImage = context.createCGImage(ciImage, from: ciImage.extent),
              let croppedImage = LongCaptureImageSampling.crop(image: fullImage, screenRect: region.screenRect, screenFrame: region.screenFrame) else {
            return
        }
        
        lastEmissionTimestamp = timestamp
        onFrame(LongCaptureFrame(image: croppedImage, timestamp: timestamp))
    }
}

private enum LongCaptureImageSampling {
    static func crop(image: CGImage, screenRect: CGRect, screenFrame: CGRect) -> CGImage? {
        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height
        let x = (screenRect.origin.x - screenFrame.origin.x) * scaleX
        let relativeY = screenRect.origin.y - screenFrame.origin.y
        let y = (screenFrame.height - relativeY - screenRect.height) * scaleY
        let cropRect = CGRect(
            x: x,
            y: y,
            width: screenRect.width * scaleX,
            height: screenRect.height * scaleY
        )
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let finalRect = cropRect.integral.intersection(imageRect)
        guard !finalRect.isNull, !finalRect.isEmpty else { return nil }
        return image.cropping(to: finalRect)
    }
    
    static func scale(image: CGImage, to size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded()), 1)
        let height = max(Int(size.height.rounded()), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    
    static func grayscalePixels(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

// MARK: - Sound Service
class SoundService {
    static let shared = SoundService()
    
    private var captureSound: NSSound?
    
    private init() {
        // 尝试加载系统截图音效 (macOS 系统自带的相机快门声)
        // 路径可能因系统版本略有不同，但通常在这个位置
        let soundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: soundPath) {
            self.captureSound = NSSound(contentsOfFile: soundPath, byReference: true)
        }
    }
    
    /// 播放截图完成音效
    /// 该方法非阻塞，会立即返回
    func playCaptureSound() {
        guard SettingsService.shared.playSound else { return }
        
        // 在主线程播放以确保安全，或者直接播放
        // NSSound.play() 是异步的（对于非循环声音）
        if let sound = self.captureSound {
            if sound.isPlaying {
                sound.stop()
            }
            sound.play()
        } else {
            // 如果找不到系统截图音效，回退到系统默认的清脆提示音
            NSSound(named: "Tink")?.play()
        }
    }
}
