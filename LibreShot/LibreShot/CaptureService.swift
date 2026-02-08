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
}


class CaptureService {
    static let shared = CaptureService()
    
    let context = CIContext()
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let outputQueue = DispatchQueue(label: "com.libreshot.capture")
    private let continuationLock = NSLock()
    
    private var continuation: CheckedContinuation<NSImage, Error>?
    private var isStopping = false
    
    init() {}
    
    func saveImageWithFallback(_ image: NSImage) async throws -> URL {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "保存截图"
        savePanel.message = "选择保存截图的位置"
        savePanel.nameFieldStringValue = "Screenshot \(Date().formatted(date: .numeric, time: .standard)).png"
        
        let response = await savePanel.begin()
        guard response == .OK, let url = savePanel.url else {
            throw CancellationError()
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw CaptureServiceError.imageConversionFailed
        }
        
        try pngData.write(to: url)
        return url
    }
    
    func copyToClipboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
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
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
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

            let size = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
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
