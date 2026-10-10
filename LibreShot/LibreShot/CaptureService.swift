import AppKit
import ScreenCaptureKit
import CoreImage
import CoreGraphics
import Vision
import Combine
import ImageIO
import UniformTypeIdentifiers

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
    
    let context = CIContext()
    private let exportColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let outputQueue = DispatchQueue(label: "com.libreshot.capture")
    private var isStopping = false
    private var currentScale: CGFloat = 1.0
    
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
        let policy = NSApp.activationPolicy()
        if policy == .accessory { NSApp.setActivationPolicy(.regular) }
        defer { if policy == .accessory { NSApp.setActivationPolicy(policy) } }
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
        return url
    }

    func copyToClipboard(_ image: NSImage) {
        writeToClipboard(image, pngData: pngData(from: image))
    }

    private func writeToClipboard(_ image: NSImage, pngData: Data?) {
        pasteboard.clearContents()
        
        guard let pngData else {
            pasteboard.writeObjects([image])
            return
        }
        
        pasteboard.setData(pngData, forType: .png)
        
        // Decode the normalized PNG so both formats have the same pixels and DPI.
        if let normalizedBitmap = NSBitmapImageRep(data: pngData),
           let tiffData = encodedData(from: normalizedBitmap, type: .tiff) {
            pasteboard.setData(tiffData, forType: .tiff)
        }
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
    
    // Updated to accept optional displayID. If nil, captures main display.
    func captureDisplayImage(displayID: CGDirectDisplayID? = nil) async throws -> NSImage {
        isStopping = false
        let content = try await ScreenCaptureAccess.content {
            try await SCShareableContent.current
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
        let configuration = Self.displayConfiguration(width: physicalWidth, height: physicalHeight)

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let pending = CaptureContinuation(continuation)
                let output = CaptureStreamOutput { [weak self, pending] sampleBuffer in
                    self?.handleSampleBuffer(sampleBuffer, pending: pending)
                }
                self.streamOutput = output
                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                self.stream = stream
                do {
                    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: self.outputQueue)
                    stream.startCapture { error in
                        if let error { pending.fail(error) }
                    }
                } catch {
                    pending.fail(error)
                }
            }
        } catch {
            stopStream()
            throw error
        }
    }

    static func displayConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        // Preserve physical resolution without automatic scaling.
        configuration.width = width
        configuration.height = height
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        // Exclude the system cursor from both frozen previews and final screenshots.
        // The live overlay cursor remains visible for selection and annotation.
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return configuration
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer, pending: CaptureContinuation) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Safety check for invalid buffer
        if CVPixelBufferGetWidth(imageBuffer) == 0 || CVPixelBufferGetHeight(imageBuffer) == 0 {
            return
        }
        
        guard let continuation = pending.take() else { return }
        
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
                stopStream()
                return
            }

            // Use the captured scale to set the correct logical size (Points)
            let scale = self.currentScale
            let size = NSSize(width: ciImage.extent.width / scale, height: ciImage.extent.height / scale)
            let nsImage = NSImage(cgImage: cgImage, size: size)
            continuation.resume(returning: nsImage)
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

    func bitmapRep(from image: NSImage, opaque: Bool = false) -> NSBitmapImageRep? {
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
    
    /// Apply the final outline after annotation compositing, in physical pixels.
    func styledImage(_ image: NSImage) -> NSImage {
        guard settings.useRoundedCorners,
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
        guard let bitmap = bitmapRep(from: styledImage(image)) else { return nil }
        return encodedData(from: bitmap, type: .png)
    }

    /// File-backed output avoids growing large in-memory encoder buffers on each
    /// copy. The private temporary file is unlinked once its mapped data is ready;
    /// consumers own the data normally, including after it reaches the pasteboard.
    private func encodedData(from bitmap: NSBitmapImageRep, type: UTType) -> Data? {
        guard let image = bitmap.cgImage, bitmap.size.width > 0, bitmap.size.height > 0 else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("libreshot-encode-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
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
        guard CGImageDestinationFinalize(destination) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}

final class CaptureContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSImage, Error>?

    init(_ continuation: CheckedContinuation<NSImage, Error>) {
        self.continuation = continuation
    }

    func take() -> CheckedContinuation<NSImage, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }

    func fail(_ error: Error) {
        take()?.resume(throwing: error)
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

struct LongCaptureRegion {
    let selectionRect: CGRect
    let screenRect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
}

struct LongCaptureProgress {
    let acceptedFrameCount: Int
    let appendedPixelHeight: Int
    var warning: String? = nil
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
    case incompleteCapture
    
    var errorDescription: String? {
        switch self {
        case .noStableFrame:
            return "未采集到有效的滚动帧，请重试"
        case .rendererFailed:
            return "长截图拼接失败"
        case .incompleteCapture:
            return "有滚动画面未能接上，本次未生成完整长截图。请重新框选可滚动内容，缓慢向下滚动，保留至少三分之一的重叠区域。"
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
    private let frames = LongCaptureFrameAccumulator()
    private var isStarted = false
    #if DEBUG
    private var lastReportedFrameCount = 0
    #endif
    
    init(region: LongCaptureRegion) {
        self.region = region
    }
    
    func start() async throws {
        guard !isStarted else { return }
        #if DEBUG
        MemoryTrace.mark("long_stream_starting")
        #endif
        isStarted = true
        await MainActor.run {
            self.status = .capturing
        }
        try await captureService.start(region: region) { [weak self] frame in
            self?.handle(frame: frame)
        }
        #if DEBUG
        MemoryTrace.mark("long_stream_started")
        #endif
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
        #if DEBUG
        MemoryTrace.mark("long_finish_started")
        #endif
        await MainActor.run {
            self.status = .finishing
        }
        await captureService.stop()
        #if DEBUG
        MemoryTrace.mark("long_stream_stopped")
        #endif
        let image: NSImage
        do {
            image = try frames.renderFinalImage()
        } catch {
            await MainActor.run { self.status = .failed(error.localizedDescription) }
            throw error
        }
        #if DEBUG
        MemoryTrace.mark("long_image_rendered")
        #endif
        if image.size.width > 0 {
            image.size = NSSize(width: region.selectionRect.width,
                                height: image.size.height * region.selectionRect.width / image.size.width)
        }
        await MainActor.run {
            self.status = .completed
        }
        #if DEBUG
        MemoryTrace.mark("long_finish_completed")
        #endif
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
        guard let progress = frames.process(frame: frame) else { return }
        #if DEBUG
        if progress.acceptedFrameCount > lastReportedFrameCount {
            lastReportedFrameCount = progress.acceptedFrameCount
            if progress.acceptedFrameCount == 1 { MemoryTrace.mark("long_first_frame") }
            if progress.acceptedFrameCount == 10 { MemoryTrace.mark("long_tenth_frame") }
        }
        #endif
        Task { @MainActor [weak self] in
            guard let self, self.status == .capturing else { return }
            self.progress = progress
        }
    }
}

/// Owns the accepted-frame baseline and completion validation on the capture queue.
/// An unmatched final frame must not turn into a successful one-screen "long" image.
final class LongCaptureFrameAccumulator {
    private let deduplicator = LongCaptureFrameDeduplicator()
    private let stitcher = LongCaptureStitcher()
    private var hasUnmatchedFrame = false

    func process(frame: LongCaptureFrame) -> LongCaptureProgress? {
        switch deduplicator.process(frame: frame) {
        case .ignore:
            // Returning to the last accepted position clears the retry warning.
            guard hasUnmatchedFrame else { return nil }
            hasUnmatchedFrame = false
        case .accept:
            let result = stitcher.append(frame: frame)
            hasUnmatchedFrame = !result.accepted
            // Revisiting captured content must not move the forward matching baseline.
            if result.accepted, result.appendedPixelHeight > 0 { deduplicator.markAccepted(frame) }
        }
        return LongCaptureProgress(acceptedFrameCount: stitcher.acceptedFrameCount,
                                   appendedPixelHeight: stitcher.totalPixelHeight,
                                   warning: hasUnmatchedFrame ? "当前画面未接上，请回滚到上次位置，再小幅向下滚动。" : nil)
    }

    func renderFinalImage() throws -> NSImage {
        guard !hasUnmatchedFrame else { throw LongCaptureError.incompleteCapture }
        guard let image = stitcher.renderFinalImage() else { throw LongCaptureError.noStableFrame }
        return image
    }
}

enum LongCaptureFrameDecision {
    case ignore
    case accept(LongCaptureFrame)
}

final class LongCaptureFrameDeduplicator {
    private var acceptedImage: CGImage?

    func process(frame: LongCaptureFrame) -> LongCaptureFrameDecision {
        // Repeated Finder rows may differ only in a few number glyphs. A thumbnail
        // tolerance can discard real motion and leave the next frame without overlap.
        if let acceptedImage, Self.samePixels(acceptedImage, frame.image) { return .ignore }
        return .accept(frame)
    }

    /// Failed matches remain retryable and never become the deduplication baseline.
    func markAccepted(_ frame: LongCaptureFrame) {
        acceptedImage = frame.image
    }

    private static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              a.bitsPerComponent == b.bitsPerComponent, a.bitsPerPixel == b.bitsPerPixel,
              a.bitmapInfo == b.bitmapInfo, a.decode == nil, b.decode == nil,
              let ac = a.colorSpace, let bc = b.colorSpace, CFEqual(ac, bc),
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        let rowBytes = (a.width * a.bitsPerPixel + 7) / 8
        guard rowBytes > 0, a.bytesPerRow >= rowBytes, b.bytesPerRow >= rowBytes,
              CFDataGetLength(ad) >= (a.height - 1) * a.bytesPerRow + rowBytes,
              CFDataGetLength(bd) >= (b.height - 1) * b.bytesPerRow + rowBytes else { return false }
        // Padding is not image content and may differ between capture buffers.
        for y in 0..<a.height {
            if memcmp(ap + y * a.bytesPerRow, bp + y * b.bytesPerRow, rowBytes) != 0 { return false }
        }
        return true
    }
}

final class LongCaptureStitcher {
    private let overlapMatcher = LongCaptureOverlapMatcher()
    private var segments: [LongCaptureSegment] = []
    private var previousImage: CGImage?
    private var footerImage: CGImage?
    private var fixedFooterHeight: Int?
    private var initialFrameHeight = 0
    private(set) var totalPixelHeight = 0
    private(set) var acceptedFrameCount = 0
    
    func append(frame: LongCaptureFrame) -> LongCaptureAppendResult {
        if segments.isEmpty {
            guard let first = Self.detachedImage(frame.image) else {
                return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
            }
            totalPixelHeight = frame.image.height
            initialFrameHeight = frame.image.height
            acceptedFrameCount = 1
            segments = [LongCaptureSegment(image: first, yOffset: 0)]
            previousImage = frame.image
            return LongCaptureAppendResult(accepted: true, appendedPixelHeight: frame.image.height)
        }

        guard let previousImage else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }
        let forward = overlapMatcher.match(previous: previousImage, current: frame.image)
        let reverse = overlapMatcher.match(previous: frame.image, current: previousImage)
        // Do not guess direction in repeating content with two equally plausible seams.
        if let forward, let reverse, abs(forward.confidence - reverse.confidence) < 0.025 {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }
        if let reverse, reverse.confidence > (forward?.confidence ?? -.infinity) {
            let distance = frame.image.height - reverse.overlapHeight
            guard distance <= totalPixelHeight - initialFrameHeight else {
                return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
            }
            return LongCaptureAppendResult(accepted: true, appendedPixelHeight: 0)
        }
        guard let match = forward else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }

        let appendStartY = match.overlapHeight
        let appendHeight = frame.image.height - appendStartY
        guard appendHeight >= 1 else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }

        let footerHeight = fixedFooterHeight ?? match.footerHeight
        let cropRect = CGRect(x: 0, y: appendStartY - footerHeight, width: frame.image.width, height: appendHeight)
        guard let crop = frame.image.cropping(to: cropRect.integral),
              let appendedImage = Self.detachedImage(crop) else {
            return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
        }

        // Prepare every fragment before committing the new matching baseline.
        // A failed allocation must leave the previously accepted document intact.
        var nextFooter: CGImage?
        var trimmedFirst: CGImage?
        if footerHeight > 0 {
            guard let crop = frame.image.cropping(to: CGRect(x: 0, y: frame.image.height - footerHeight,
                                                            width: frame.image.width, height: footerHeight)),
                  let footer = Self.detachedImage(crop) else {
                return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
            }
            nextFooter = footer
            if footerImage == nil, let first = segments.first {
                guard let crop = first.image.cropping(to: CGRect(x: 0, y: 0, width: first.image.width,
                                                                 height: first.image.height - footerHeight)),
                      let trimmed = Self.detachedImage(crop) else {
                    return LongCaptureAppendResult(accepted: false, appendedPixelHeight: 0)
                }
                trimmedFirst = trimmed
            }
        }
        if let trimmedFirst { segments[0] = LongCaptureSegment(image: trimmedFirst, yOffset: 0) }
        footerImage = nextFooter
        fixedFooterHeight = footerHeight
        segments.append(LongCaptureSegment(image: appendedImage, yOffset: totalPixelHeight - footerHeight))
        self.previousImage = frame.image
        totalPixelHeight += appendHeight
        acceptedFrameCount += 1
        return LongCaptureAppendResult(accepted: true, appendedPixelHeight: appendHeight)
    }

    /// CGImage crops retain their original backing store. Materialize only the pixels
    /// needed by the document, using the same sRGB format as the final renderer.
    private static func detachedImage(_ image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    func renderFinalImage() -> NSImage? {
        guard let firstSegment = segments.first else { return nil }
        let width = firstSegment.image.width
        guard width > 0, totalPixelHeight > 0 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
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
        
        if let footerImage {
            context.draw(footerImage, in: CGRect(x: 0, y: 0, width: width, height: footerImage.height))
        }
        guard let cgImage = context.makeImage() else { return nil }
        let logicalSize = NSSize(width: width, height: totalPixelHeight)
        return NSImage(cgImage: cgImage, size: logicalSize)
    }
}

private struct LongCaptureSegment {
    let image: CGImage
    let yOffset: Int
}

struct LongCaptureOverlapMatch {
    let overlapHeight: Int
    let confidence: Double
    var footerHeight: Int = 0
}


/// Search vertical translations in original pixel rows. Only the horizontal axis is sampled:
/// reducing height aliases small scrolls and can select a different repeated text row.
final class LongCaptureOverlapMatcher {
    private let sampleWidth = 240

    func match(previous: CGImage, current: CGImage) -> LongCaptureOverlapMatch? {
        guard previous.width == current.width, previous.height == current.height else { return nil }
        let width = min(sampleWidth, current.width), height = current.height
        guard height >= 32,
              let a = LongCaptureImageSampling.scale(image: previous, to: CGSize(width: width, height: height)),
              let b = LongCaptureImageSampling.scale(image: current, to: CGSize(width: width, height: height)),
              let ap = LongCaptureImageSampling.grayscalePixels(from: a),
              let bp = LongCaptureImageSampling.grayscalePixels(from: b) else { return nil }

        // Ignore static sidebars when locating the scrolling content.
        let columns = (0..<width).filter { x in
            var difference = 0.0
            for y in 0..<height {
                difference += abs(Double(ap[y * width + x]) - Double(bp[y * width + x]))
            }
            return difference / Double(height) > 1.0
        }
        guard columns.count >= 8 else { return nil }
        let rows = (0..<height).filter { y in
            columns.reduce(0.0) { $0 + abs(Double(ap[y * width + $1]) - Double(bp[y * width + $1])) }
                / Double(columns.count) > 1.0
        }
        guard let top = rows.first, let last = rows.last, last - top >= 24 else { return nil }
        let bottom = last + 1
        let minOverlap = max(24, (bottom - top) / 4)
        let contrastA = Self.contrast(ap, width: width), contrastB = Self.contrast(bp, width: width)
        let candidates = (1...(bottom - top - minOverlap)).map { shift in
            (shift: shift, error: Self.error(contrastA, contrastB, width: width, top: top, bottom: bottom,
                                            columns: columns, shift: shift, exhaustive: false))
        }.filter { $0.error < 0.20 }.sorted { $0.error < $1.error }
        // Validate multiple candidates using every row, including competing repeated periods.
        // Too many equally plausible candidates are ambiguous, not evidence to guess a seam.
        guard let coarseBest = candidates.first else { return nil }
        let contenders = candidates.filter { $0.error < coarseBest.error + 0.05 }
        guard contenders.count <= 64 else { return nil }
        let verified = contenders.map { candidate in
            (shift: candidate.shift, error: Self.error(contrastA, contrastB, width: width, top: top, bottom: bottom,
                                                       columns: columns, shift: candidate.shift, exhaustive: true))
        }.sorted { $0.error < $1.error }
        guard let best = verified.first, best.error < 0.08 else { return nil }
        if let second = verified.first(where: { abs($0.shift - best.shift) > 2 }),
           second.error - best.error < 0.025 { return nil }

        let footer = Self.fixedFooterHeight(ap, bp, width: width, height: height, unchangedFrom: bottom)
        guard best.shift + footer < height else { return nil }
        return LongCaptureOverlapMatch(overlapHeight: height - best.shift,
                                       confidence: 1 - best.error, footerHeight: footer)
    }

    private static func fixedFooterHeight(_ a: [UInt8], _ b: [UInt8], width: Int,
                                          height: Int, unchangedFrom bottom: Int) -> Int {
        guard bottom < height else { return 0 }
        // A fixed bar needs both a stable suffix and an actual horizontal boundary.
        // Blank spacing after the last text row is not a footer, regardless of its height.
        for y in bottom..<height {
            var boundaryColumns = 0
            var unchanged = 0.0
            for x in 0..<width {
                if abs(Int(a[y * width + x]) - Int(a[(y - 1) * width + x])) > 3 { boundaryColumns += 1 }
                unchanged += abs(Double(a[y * width + x]) - Double(b[y * width + x]))
            }
            if boundaryColumns > width / 2, unchanged / Double(width) < 0.5 {
                return height - y
            }
        }
        return 0
    }

    private static func contrast(_ pixels: [UInt8], width: Int) -> [Double] {
        var result = [Double](repeating: 0, count: pixels.count)
        for y in 0..<(pixels.count / width) {
            let row = y * width
            let samples = stride(from: 0, to: width, by: max(1, width / 24)).map { pixels[row + $0] }.sorted()
            let background = Double(samples[samples.count / 2])
            for x in 0..<width { result[row + x] = Double(pixels[row + x]) - background }
        }
        return result
    }

    private static func error(_ a: [Double], _ b: [Double], width: Int, top: Int, bottom: Int,
                              columns: [Int], shift: Int, exhaustive: Bool) -> Double {
        var difference = 0.0, energy = 0.0
        let rowStep = exhaustive ? 1 : max(1, (bottom - top - shift) / 64)
        let colStep = max(1, columns.count / (exhaustive ? 120 : 32))
        for y in stride(from: top, to: bottom - shift, by: rowStep) {
            let ay = (y + shift) * width, by = y * width
            for i in stride(from: 0, to: columns.count, by: colStep) {
                let x = columns[i]
                let av = a[ay + x], bv = b[by + x]
                difference += abs(av - bv)
                energy += max(abs(av), abs(bv))
            }
        }
        return energy > 1000 ? difference / energy : .infinity
    }
}

// Frame state is confined to outputQueue; start/stop own stream lifecycle and drain that queue before teardown.
private final class LongCaptureStreamService: @unchecked Sendable {
    private let context = CIContext()
    private let outputQueue = DispatchQueue(label: "com.libreshot.long-capture")
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private var region: LongCaptureRegion?
    private var onFrame: ((LongCaptureFrame) -> Void)?
    private var minimumFrameInterval: CFTimeInterval = 0.10
    private(set) var isRunning = false
    private var isPaused = false
    private var settleWork: DispatchWorkItem?
    private var pendingFrame: LongCaptureFrame?
    #if DEBUG
    private var processedFrameCount = 0
    #endif
    
    func start(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws {
        let content = try await ScreenCaptureAccess.content {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureServiceError.noDisplay
        }
        
        try Task.checkCancellation()
        self.region = region
        self.onFrame = onFrame
        self.isPaused = false
        
        let excludedApplications: [SCRunningApplication]
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            excludedApplications = content.applications.filter { $0.bundleIdentifier == bundleIdentifier }
        } else {
            excludedApplications = []
        }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
        let pixelSize = await MainActor.run { () -> CGSize in
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == region.displayID
            }
            let scale = screen?.backingScaleFactor ?? 1
            return CGSize(width: region.screenFrame.width * scale, height: region.screenFrame.height * scale)
        }
        let configuration = CaptureService.displayConfiguration(width: Int(pixelSize.width), height: Int(pixelSize.height))
        configuration.minimumFrameInterval = CMTime(seconds: minimumFrameInterval, preferredTimescale: 600)
        
        let output = CaptureStreamOutput { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
        self.streamOutput = output
        self.stream = stream
        outputQueue.sync { self.isRunning = true }
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            await stop()
            throw error
        }
    }
    
    func pause() {
        outputQueue.async { self.isPaused = true; self.settleWork?.cancel() }
    }
    
    func resume() {
        outputQueue.async {
            self.isPaused = false
        }
    }
    
    func stop() async {
        guard let stream else {
            outputQueue.sync { self.isRunning = false }
            return
        }
        try? await stream.stopCapture()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            outputQueue.async {
                self.settleWork?.cancel()
                self.settleWork = nil
                if !self.isPaused, let frame = self.pendingFrame {
                    self.onFrame?(LongCaptureFrame(image: frame.image, timestamp: frame.timestamp + 0.2))
                }
                self.pendingFrame = nil
                self.isRunning = false
                continuation.resume()
            }
        }
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
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let fullImage = context.createCGImage(ciImage, from: ciImage.extent),
              let croppedImage = LongCaptureImageSampling.crop(image: fullImage, screenRect: region.screenRect, screenFrame: region.screenFrame) else {
            return
        }
        
        let frame = LongCaptureFrame(image: croppedImage, timestamp: timestamp)
        pendingFrame = frame
        settleWork?.cancel()
        onFrame(frame)
        #if DEBUG
        processedFrameCount += 1
        if processedFrameCount == 10 { MemoryTrace.mark("long_10_frames_processed") }
        if processedFrameCount == 100 { MemoryTrace.mark("long_100_frames_processed") }
        #endif
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, !self.isPaused, let frame = self.pendingFrame else { return }
            self.onFrame?(LongCaptureFrame(image: frame.image, timestamp: frame.timestamp + 0.2))
        }
        settleWork = work
        outputQueue.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}

enum LongCaptureImageSampling {
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
        guard let crop = image.cropping(to: finalRect),
              let context = CGContext(data: nil, width: crop.width, height: crop.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: crop.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            return nil
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
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
