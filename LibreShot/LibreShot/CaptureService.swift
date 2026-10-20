import AppKit
import ScreenCaptureKit
import CoreImage
import CoreGraphics
import Vision
import Combine
import ImageIO
import UniformTypeIdentifiers
import OSLog

enum CaptureServiceError: LocalizedError {
    case noDisplay
    case permissionRequestPending
    case permissionDenied
    case captureFailed
    case imageConversionFailed
    case saveDirectoryAccessFailed
    case screenContentUnavailable(underlying: Error)

    var isPermissionFailure: Bool {
        switch self {
        case .permissionRequestPending, .permissionDenied:
            return true
        case .screenContentUnavailable(let underlying):
            let error = underlying as NSError
            return error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
        default:
            return false
        }
    }

    var shouldPresentAlert: Bool {
        if case .permissionRequestPending = self { return false }
        return true
    }

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "未找到可截图的显示器，请确认显示器已连接后重试。"
        case .permissionRequestPending, .permissionDenied:
            return "LibreShot 尚未获得屏幕录制权限。请前往“系统设置 → 隐私与安全性 → 录屏与系统录音”（旧版 macOS 为“屏幕录制”），允许 LibreShot 后退出并重新打开应用。若已开启却仍报错，请先退出 LibreShot，删除列表中的旧 LibreShot 项，再用“+”添加当前安装的 LibreShot.app，授权后重新打开。"
        case .captureFailed:
            return "截图失败，请重新选择截图区域后重试。"
        case .imageConversionFailed:
            return "无法生成截图图片，请重新截图后重试。"
        case .saveDirectoryAccessFailed:
            return "无法记住所选保存目录的访问权限，请在设置中重新选择保存位置。"
        case .screenContentUnavailable(let underlying):
            let error = underlying as NSError
            let reason = error.domain == SCStreamErrorDomain && error.code == SCStreamError.Code.userDeclined.rawValue
                ? CaptureServiceError.permissionDenied.localizedDescription
                : "无法读取可截图的屏幕内容，请稍后重试。"
            return "\(reason)\n\n系统错误：\(error.localizedDescription)\n\(error.domain)（\(error.code)）"
        }
    }
}

/// Shared by ordinary and scrolling capture, keeping permission and system failures distinct.
@MainActor
final class ScreenCaptureRequestGate {
    static let shared = ScreenCaptureRequestGate()
    private var requested = false
    private var presentedPermissionAlert = false

    func claimRequest() -> Bool {
        guard !requested else { return false }
        requested = true
        return true
    }

    func claimPermissionAlert() -> Bool {
        guard !presentedPermissionAlert else { return false }
        presentedPermissionAlert = true
        return true
    }

    func markContentLoaded() {
        requested = false
        presentedPermissionAlert = false
    }
}

@MainActor
enum ScreenCaptureAccess {
    static func content(
        preflight: () -> Bool = CGPreflightScreenCaptureAccess,
        request: () -> Bool = CGRequestScreenCaptureAccess,
        load: () async throws -> SCShareableContent,
        requestGate: ScreenCaptureRequestGate? = nil
    ) async throws -> SCShareableContent {
        let requestGate = requestGate ?? .shared
        if !preflight() {
            guard requestGate.claimRequest() else {
                throw CaptureServiceError.permissionDenied
            }
            let granted = request()
            guard granted || preflight() else {
                throw CaptureServiceError.permissionRequestPending
            }
        }
        do {
            let content = try await load()
            requestGate.markContentLoaded()
            return content
        } catch {
            throw CaptureServiceError.screenContentUnavailable(underlying: error)
        }
    }
}


class CaptureService {
    static let shared = CaptureService()

    static func displayID(at point: CGPoint, displays: [(id: CGDirectDisplayID, frame: CGRect)],
                          fallback: CGDirectDisplayID?) -> CGDirectDisplayID? {
        displays.first { $0.frame.contains(point) }?.id ?? fallback
    }

    static func displayIDAtPointer() -> CGDirectDisplayID? {
        let displays = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, frame: CGRect)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            return (id, screen.frame)
        }
        return displayID(at: NSEvent.mouseLocation, displays: displays, fallback: CGMainDisplayID())
    }
    
    private let exportColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let outputQueue = DispatchQueue(label: "com.libreshot.capture")
    private let lifecycleGate = StreamLifecycleGate()
    private let diagnosticTrace = LongCaptureTrace()
    
    private let settings: SettingsService
    private let pasteboard: NSPasteboard
    private let directoryChooser: @MainActor (URL) -> URL?
    private let fileWriter: @Sendable (Data, URL) throws -> Void

    init(settings: SettingsService = .shared, pasteboard: NSPasteboard = .general,
         directoryChooser: @escaping @MainActor (URL) -> URL? = { CaptureService.chooseSaveDirectory(suggested: $0) },
         fileWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in try data.write(to: url) }) {
        self.settings = settings
        self.pasteboard = pasteboard
        self.directoryChooser = directoryChooser
        self.fileWriter = fileWriter
    }

    @MainActor private static func chooseSaveDirectory(suggested: URL) -> URL? {
        let changedPolicy = AppActivationPolicy.beginForegroundPanel()
        defer { AppActivationPolicy.endForegroundPanel(changedPolicy) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择截图保存目录"
        panel.message = "当前目录没有写入权限。请选择保存目录，之后截图将自动保存到这里。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = suggested
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Copy first so a failed automatic save never discards the completed screenshot.
    @MainActor
    func completeCapture(_ image: NSImage) async throws -> URL? {
        guard settings.autoSaveEnabled else {
            copyToClipboard(image)
            return nil
        }
        return try await copyAndSaveImageDirectly(image)
    }

    @MainActor
    func copyAndSaveImageDirectly(_ image: NSImage) async throws -> URL {
        let encoded = pngData(from: image)
        writeToClipboard(image, pngData: encoded)
        guard let encoded else { throw CaptureServiceError.imageConversionFailed }
        return try await savePNGDataDirectly(encoded)
    }
    
    func saveImageWithFallback(_ image: NSImage) async throws -> URL {
        return try await MainActor.run {
            let changedPolicy = AppActivationPolicy.beginForegroundPanel()
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            defer { AppActivationPolicy.endForegroundPanel(changedPolicy) }
            
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.png]
            savePanel.canCreateDirectories = true
            savePanel.directoryURL = settings.saveDirectory
                ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
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
        guard let pngData = pngData(from: image) else {
            throw CaptureServiceError.imageConversionFailed
        }
        return try await savePNGDataDirectly(pngData)
    }

    @MainActor private func savePNGDataDirectly(_ pngData: Data) async throws -> URL {
        let configuredDirectory = settings.saveDirectory
        let directory = configuredDirectory
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileWriter = fileWriter
        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.writePNGData(pngData, to: directory, scoped: configuredDirectory != nil, using: fileWriter)
            }.value
        } catch {
            guard Self.isSavePermissionError(error) else { throw error }
            // A default path is not a sandbox grant. Let the user choose a directory
            // once, retain its security-scoped bookmark, then retry the same PNG.
            guard let chosen = directoryChooser(directory) else { throw CancellationError() }
            guard settings.saveSaveDirectory(chosen) else { throw CaptureServiceError.saveDirectoryAccessFailed }
            return try await Task.detached(priority: .userInitiated) {
                try Self.writePNGData(pngData, to: chosen, scoped: true, using: fileWriter)
            }.value
        }
    }

    nonisolated private static func isSavePermissionError(_ error: Error) -> Bool {
        var current = error as NSError
        for _ in 0..<3 {
            if current.domain == NSCocoaErrorDomain && current.code == CocoaError.fileWriteNoPermission.rawValue { return true }
            if current.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(current.code) { return true }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }

    nonisolated private static func writePNGData(_ pngData: Data, to directory: URL, scoped: Bool,
                                                 using fileWriter: @Sendable (Data, URL) throws -> Void) throws -> URL {
        let trace = LongCaptureTrace()
        let writeStart = trace.startTime()
        var outcome = "failed"
        trace.event("event=save-write-start pngBytes=\(pngData.count)")
        defer { trace.event("event=save-write-ended outcome=\(outcome) pngBytes=\(pngData.count) elapsedMs=\(trace.elapsed(since: writeStart))") }
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

        let accessed = scoped && directory.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        try fileWriter(pngData, url)
        outcome = "success"
        return url
    }

    func copyToClipboard(_ image: NSImage) {
        let copyStart = diagnosticTrace.startTime()
        diagnosticTrace.event("event=copy-start logicalSize=\(image.size.width)x\(image.size.height)")
        defer { diagnosticTrace.event("event=copy-ended elapsedMs=\(diagnosticTrace.elapsed(since: copyStart))") }
        writeToClipboard(image, pngData: pngData(from: image))
    }

    private func writeToClipboard(_ image: NSImage, pngData: Data?) {
        let clipboardStart = diagnosticTrace.startTime()
        diagnosticTrace.event("event=clipboard-start pngBytes=\(pngData?.count ?? 0) logicalSize=\(image.size.width)x\(image.size.height)")
        defer { diagnosticTrace.event("event=clipboard-ended elapsedMs=\(diagnosticTrace.elapsed(since: clipboardStart))") }
        pasteboard.clearContents()
        
        guard let pngData else {
            diagnosticTrace.event("event=clipboard-fallback-image")
            pasteboard.writeObjects([image])
            return
        }
        
        diagnosticTrace.event("event=clipboard-png-start bytes=\(pngData.count)")
        pasteboard.setData(pngData, forType: .png)
        diagnosticTrace.event("event=clipboard-png-ended bytes=\(pngData.count)")
        
        // Decode the normalized PNG so both formats have the same pixels and DPI.
        diagnosticTrace.event("event=clipboard-tiff-start pngBytes=\(pngData.count)")
        if let normalizedBitmap = NSBitmapImageRep(data: pngData),
           let tiffData = encodedData(from: normalizedBitmap, type: .tiff) {
            diagnosticTrace.event("event=clipboard-tiff-write-start bytes=\(tiffData.count) pixels=\(normalizedBitmap.pixelsWide)x\(normalizedBitmap.pixelsHigh)")
            pasteboard.setData(tiffData, forType: .tiff)
            diagnosticTrace.event("event=clipboard-tiff-write-ended bytes=\(tiffData.count)")
        } else {
            diagnosticTrace.event("event=clipboard-tiff-unavailable")
        }
        diagnosticTrace.event("event=clipboard-tiff-ended")
        // Both representations already belong to the same pasteboard item.
        // Writing NSImage again adds a second item and another decoded image.
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

        // A CGImage crop can retain the entire display backing store while the selection is open.
        guard let context = CGContext(data: nil, width: croppedCGImage.width, height: croppedCGImage.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: croppedCGImage.colorSpace ?? exportColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return nil
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: croppedCGImage.width, height: croppedCGImage.height))
        guard let detachedImage = context.makeImage() else { return nil }
        
        // Return image with the logical size of the cropped area (Points)
        let finalSize = CGSize(width: finalRect.width / scaleX, height: finalRect.height / scaleY)
        return NSImage(cgImage: detachedImage, size: finalSize)
    }
    
    // Updated to accept optional displayID. If sourceRect is supplied, capture
    // only that display-local rectangle instead of creating a full-screen frame.
    func captureDisplayImage(displayID: CGDirectDisplayID? = nil, sourceRect: CGRect? = nil) async throws -> NSImage {
        // Register cancellation before either async permission/content loading
        // or gate acquisition. Each request owns its own result and stream.
        let request = CaptureRequestState<CGImage>()
        return try await withTaskCancellationHandler {
            try await lifecycleGate.withLock {
                try Task.checkCancellation()
                return try await captureDisplayImageUnlocked(displayID: displayID,
                                                             sourceRect: sourceRect, request: request)
            }
        } onCancel: {
            request.fail(CancellationError())
        }
    }

    private func captureDisplayImageUnlocked(displayID: CGDirectDisplayID?, sourceRect: CGRect?,
                                             request: CaptureRequestState<CGImage>) async throws -> NSImage {
        try Task.checkCancellation()
        let content = try await ScreenCaptureAccess.content {
            try await SCShareableContent.current
        }
        try Task.checkCancellation()
        try request.checkFailure()
        
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
        var displayBounds = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) {
            scale = screen.backingScaleFactor
            // Force use of NSScreen's physical pixel count calculation for reliability
            // This fixes issues where SCDisplay might report logical or scaled sizes
            physicalWidth = Int(screen.frame.width * scale)
            physicalHeight = Int(screen.frame.height * scale)
            displayBounds = CGRect(origin: .zero, size: screen.frame.size)
        }

        let effectiveSourceRect: CGRect?
        if let sourceRect {
            let normalized = sourceRect.standardized
            let clipped = normalized.intersection(displayBounds)
            guard !clipped.isNull, !clipped.isEmpty else {
                throw CaptureServiceError.captureFailed
            }
            effectiveSourceRect = clipped
            physicalWidth = max(1, Int((clipped.width * scale).rounded()))
            physicalHeight = max(1, Int((clipped.height * scale).rounded()))
        } else {
            effectiveSourceRect = nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = Self.displayConfiguration(width: physicalWidth, height: physicalHeight, sourceRect: effectiveSourceRect)

        let output = CaptureStreamOutput { sampleBuffer in
            Self.handleSampleBuffer(sampleBuffer, request: request)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let image = try await SingleFrameCaptureLifecycle.capture(request: request, start: {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.outputQueue)
            try await stream.startCapture()
        }, stop: {
            // This always runs after the start operation has returned, including
            // when a first frame or cancellation arrived during startup.
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(output, type: .screen)
        })
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return NSImage(cgImage: image, size: size)
    }

    /// Builds the common ScreenCaptureKit configuration.
    ///
    /// The SDK default queue depth is eight frames.  Keep that default unless
    /// `LIBRESHOT_STREAM_QUEUE_DEPTH` is explicitly set to 1, 2, or 8 so we
    /// can run a bounded A/B memory experiment without changing the shipped
    /// capture behavior.  Invalid values are ignored deliberately.
    static func displayConfiguration(width: Int, height: Int, sourceRect: CGRect? = nil) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        // Preserve physical resolution without automatic scaling.
        configuration.width = width
        configuration.height = height
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Exclude the system cursor from both frozen previews and final screenshots.
        // The live overlay cursor remains visible for selection and annotation.
        configuration.showsCursor = false
        configuration.capturesAudio = false
        if let queueDepth = streamQueueDepthOverride {
            configuration.queueDepth = queueDepth
        }
        return configuration
    }

    /// Optional test-only override for ScreenCaptureKit's frame queue.
    ///
    /// The environment is read when a configuration is created, which keeps
    /// the default app behavior unchanged and lets a running test process be
    /// relaunched with a different depth between samples.
    private static var streamQueueDepthOverride: Int? {
        guard let rawValue = ProcessInfo.processInfo.environment["LIBRESHOT_STREAM_QUEUE_DEPTH"],
              let value = Int(rawValue),
              [1, 2, 8].contains(value) else {
            return nil
        }
        return value
    }

    nonisolated static func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, request: CaptureRequestState<CGImage>) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetWidth(imageBuffer) > 0, CVPixelBufferGetHeight(imageBuffer) > 0,
              request.claimFrame() else { return }

        // Claim before copying: queued frames after the first one allocate no
        // additional full-screen buffers, even while startCapture is finishing.
        guard let image = CaptureFrameImage.copy(from: imageBuffer) else {
            request.fail(CaptureServiceError.imageConversionFailed)
            return
        }
        request.succeed(image)
    }

    /// Preserves the normalization performed by annotation compositing while
    /// avoiding its second full-image draw for a certified unannotated document.
    func normalizedUnannotatedImage(_ image: NSImage) -> NSImage {
        guard let bitmap = bitmapRep(from: image, opaque: false), let pixels = bitmap.cgImage else { return image }
        return NSImage(cgImage: pixels, size: image.size)
    }

    func bitmapRep(from image: NSImage, opaque: Bool = false, reuseExportPixels: Bool = false) -> NSBitmapImageRep? {
        let bitmapStart = diagnosticTrace.startTime()
        var outcome = "source-unavailable"
        diagnosticTrace.event("event=bitmap-normalize-start logicalSize=\(image.size.width)x\(image.size.height)")
        defer { diagnosticTrace.event("event=bitmap-normalize-ended outcome=\(outcome) elapsedMs=\(diagnosticTrace.elapsed(since: bitmapStart))") }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        diagnosticTrace.event("event=bitmap-normalize-source pixels=\(cgImage.width)x\(cgImage.height)")
        // PNG styling may already produce this exact export format. Preserve its
        // pixels instead of allocating and drawing another full-size bitmap.
        // Other callers and images requiring color/decode/alpha conversion keep
        // the existing normalization path.
        if reuseExportPixels, !opaque,
           cgImage.colorSpace?.name == CGColorSpace.sRGB,
           cgImage.bitsPerComponent == 8, cgImage.bitsPerPixel == 32,
           cgImage.alphaInfo == .premultipliedLast, cgImage.decode == nil,
           !cgImage.bitmapInfo.contains(.floatComponents) {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            bitmap.size = image.size
            outcome = "reused-export-pixels"
            return bitmap
        }
        outcome = "context-failed"
        
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
        
        outcome = "image-failed"
        guard let normalizedImage = bitmapContext.makeImage() else {
            return nil
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: normalizedImage)
        bitmapRep.size = image.size
        outcome = "success"
        return bitmapRep
    }
    
    /// Compatibility entry point for exporters that already hold a styled image.
    /// The optional-argument overload below remains the settings-aware path.
    func styledImage(_ image: NSImage) -> NSImage {
        styledImage(image, useRoundedCorners: nil)
    }

    /// Apply the final outline after annotation compositing, in physical pixels.
    func styledImage(_ image: NSImage, useRoundedCorners: Bool? = nil) -> NSImage {
        guard (useRoundedCorners ?? settings.useRoundedCorners),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.size.width > 0, image.size.height > 0,
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: exportColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let radiusX = min(16, image.size.width / 2) * CGFloat(source.width) / image.size.width
        let radiusY = min(16, image.size.height / 2) * CGFloat(source.height) / image.size.height
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radiusX, cornerHeight: radiusY, transform: nil))
        context.clip()
        context.draw(source, in: rect)
        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: image.size)
    }

    func pngData(from image: NSImage) -> Data? {
        let pngStart = diagnosticTrace.startTime()
        var outcome = "normalize-failed"
        var encodedBytes = 0
        diagnosticTrace.event("event=png-start logicalSize=\(image.size.width)x\(image.size.height)")
        defer { diagnosticTrace.event("event=png-ended outcome=\(outcome) bytes=\(encodedBytes) elapsedMs=\(diagnosticTrace.elapsed(since: pngStart))") }
        guard let bitmap = bitmapRep(from: styledImage(image), reuseExportPixels: true) else { return nil }
        let data = encodedData(from: bitmap, type: .png)
        encodedBytes = data?.count ?? 0
        outcome = data == nil ? "encode-failed" : "success"
        return data
    }

    /// File-backed output avoids growing large in-memory encoder buffers on each
    /// copy. The private temporary file is unlinked once its mapped data is ready;
    /// consumers own the data normally, including after it reaches the pasteboard.
    private func encodedData(from bitmap: NSBitmapImageRep, type: UTType) -> Data? {
        let encodeStart = diagnosticTrace.startTime()
        var outcome = "source-unavailable"
        var encodedBytes = 0
        diagnosticTrace.event("event=encode-start format=\(type.identifier) pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        defer { diagnosticTrace.event("event=encode-ended format=\(type.identifier) outcome=\(outcome) pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) bytes=\(encodedBytes) elapsedMs=\(diagnosticTrace.elapsed(since: encodeStart))") }
        guard let image = bitmap.cgImage, bitmap.size.width > 0, bitmap.size.height > 0 else { return nil }
        outcome = "file-create-failed"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("libreshot-encode-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        outcome = "destination-failed"
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: Double(bitmap.pixelsWide) / bitmap.size.width * 72,
            kCGImagePropertyDPIHeight: Double(bitmap.pixelsHigh) / bitmap.size.height * 72
        ]
        if type == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // Lossless LZW.
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        outcome = "finalize-failed"
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        encodedBytes = data?.count ?? 0
        outcome = data == nil ? "file-read-failed" : "success"
        return data
    }
}

/// A request can be cancelled or receive its first frame before its waiter is
/// installed. Cache that terminal result and atomically claim only one frame.
/// Claiming a frame does not consume the waiter: cancellation can still settle
/// the request while pixel copying is in progress.
nonisolated final class CaptureRequestState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    private var frameClaimed = false

    nonisolated init() {}

    nonisolated func claimFrame() -> Bool {
        lock.withLock {
            guard result == nil, !frameClaimed else { return false }
            frameClaimed = true
            return true
        }
    }

    nonisolated func checkFailure() throws {
        let error: Error? = lock.withLock {
            if case .failure(let error) = result { return error }
            return nil
        }
        if let error { throw error }
    }

    nonisolated func waitForResult() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let cached: Result<Value, Error>? = lock.withLock {
                if let result { return result }
                precondition(self.continuation == nil, "A capture request has only one pending waiter")
                self.continuation = continuation
                return nil as Result<Value, Error>?
            }
            if let cached { continuation.resume(with: cached) }
        }
    }

    nonisolated func fail(_ error: Error) {
        complete(.failure(error))
    }

    nonisolated func succeed(_ value: Value) {
        complete(.success(value))
    }

    nonisolated private func complete(_ result: Result<Value, Error>) {
        let waiter = lock.withLock {
            guard self.result == nil else { return nil as CheckedContinuation<Value, Error>? }
            self.result = result
            defer { continuation = nil }
            return continuation
        }
        waiter?.resume(with: result)
    }
}

/// The callback only completes request state. This owner waits for startup to
/// return before waiting for its cached result and performing one teardown.
nonisolated enum SingleFrameCaptureLifecycle {
    nonisolated static func capture<Value>(request: CaptureRequestState<Value>,
                                           start: () async throws -> Void,
                                           stop: () async -> Void) async throws -> Value {
        var startAttempted = false
        do {
            try Task.checkCancellation()
            try request.checkFailure()
            startAttempted = true
            try await start()
            try Task.checkCancellation()
            let value = try await request.waitForResult()
            await stop()
            return value
        } catch {
            if startAttempted { await stop() }
            throw error
        }
    }
}

/// ScreenCaptureKit is configured for BGRA. Copying its native pixels preserves
/// their color profile and alpha without starting CoreImage/Metal for a screenshot.
nonisolated enum CaptureFrameImage {
    nonisolated static func copy(from buffer: CVPixelBuffer, pixelRect: CGRect? = nil) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(buffer),
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let sourceStride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, width <= Int.max / 4,
              sourceStride >= width * 4, height <= Int.max / sourceStride,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let pixelRect {
            guard pixelRect.minX.isFinite, pixelRect.minY.isFinite,
                  pixelRect.width.isFinite, pixelRect.height.isFinite else { return nil }
        }
        let rect = (pixelRect ?? bounds).integral.intersection(bounds)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let outputWidth = Int(rect.width), outputHeight = Int(rect.height)
        let outputStride = outputWidth * 4
        guard outputHeight <= Int.max / outputStride else { return nil }
        var pixels = Data(count: outputStride * outputHeight)
        pixels.withUnsafeMutableBytes { destination in
            guard let address = destination.baseAddress else { return }
            for row in 0..<outputHeight {
                memcpy(address.advanced(by: row * outputStride),
                       base.advanced(by: (Int(rect.minY) + row) * sourceStride + Int(rect.minX) * 4),
                       outputStride)
            }
        }
        let attachments = CVBufferCopyAttachments(buffer, .shouldPropagate)
        let colorSpace: CGColorSpace
        if let tagged = CVBufferCopyAttachment(buffer, kCVImageBufferCGColorSpaceKey, nil),
           CFGetTypeID(tagged) == CGColorSpace.typeID {
            colorSpace = tagged as! CGColorSpace
        } else {
            colorSpace = attachments.flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(width: outputWidth, height: outputHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: outputStride, space: colorSpace,
                       bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

final class CaptureStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        autoreleasepool {
            handler(sampleBuffer)
        }
    }
}

/// Serializes async ScreenCaptureKit lifecycle operations. `startCapture()` and
/// `stopCapture()` may both suspend, so a boolean flag alone cannot prevent a
/// stop requested during startup from racing the stream creation.
actor StreamLifecycleGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func withLock<Value>(_ operation: () async throws -> Value) async throws -> Value {
        await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}

// Frame state is confined to outputQueue; start/stop own stream lifecycle and drain that queue before teardown.
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
