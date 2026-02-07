import AppKit
import ScreenCaptureKit
import CoreImage
import CoreGraphics

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
    private let context = CIContext()
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var continuation: CheckedContinuation<NSImage, Error>?

    // Updated to accept optional displayID. If nil, captures main display.
    func captureDisplayImage(displayID: CGDirectDisplayID? = nil) async throws -> NSImage {
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

    func saveToDesktop(_ image: NSImage) throws -> URL {
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            throw CaptureServiceError.saveFailed(underlying: NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "MyScreenShots_\(formatter.string(from: Date())).png"
        let fileURL = desktopURL.appendingPathComponent(fileName)

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

    func saveImageWithFallback(_ image: NSImage) async throws -> URL {
        do {
            return try saveToDesktop(image)
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
        
        // Return image with point size matching the selection rect
        return NSImage(cgImage: croppedCGImage, size: rect.size)
    }

    private func isPermissionError(_ error: Error) -> Bool {
        guard let captureError = error as? CaptureServiceError else { return false }
        guard case let .saveFailed(underlying) = captureError else { return false }
        let nsError = underlying as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let continuation else { return }
        self.continuation = nil

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            continuation.resume(throwing: CaptureServiceError.captureFailed)
            stopStream()
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            continuation.resume(throwing: CaptureServiceError.imageConversionFailed)
            stopStream()
            return
        }

        let size = NSSize(width: ciImage.extent.width, height: ciImage.extent.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        continuation.resume(returning: nsImage)
        stopStream()
    }

    private func stopStream() {
        let stream = self.stream
        let output = self.streamOutput
        self.stream = nil
        self.streamOutput = nil
        Task {
            if let output {
                try? await stream?.removeStreamOutput(output, type: .screen)
            }
            try? await stream?.stopCapture()
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
