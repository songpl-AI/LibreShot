import AppKit
import Combine
import SwiftUI

/// A finish attempt stops and drains frame delivery before it returns or throws.
nonisolated protocol LongCaptureFrameSource: AnyObject, Sendable {
    var isRunning: Bool { get }
    func start(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws
    func pause()
    func resume()
    func finishFrame() async throws -> LongCaptureFrame?
    func stop() async
}

final class LongCaptureSession: ObservableObject {
    enum FinishResult {
        case completed(NSImage)
        case resumedCapture
    }

    @Published private(set) var status: LongCaptureStatus = .idle
    @Published private(set) var progress = LongCaptureProgress(acceptedFrameCount: 0, appendedPixelHeight: 0)
    
    private let region: LongCaptureRegion
    private let captureService: any LongCaptureFrameSource
    private var frames: LongCaptureFrameAccumulator?
    private let diagnosticTrace: LongCaptureTrace
    private var isStarted = false
    private let progressLock = NSLock()
    private var latestProgress: LongCaptureProgress?
    private var progressPublicationQueued = false
    // Owned by the output queue until finish drains it. UI delivery is coalesced separately.
    private var lastObservedProgress: LongCaptureProgress?
    #if DEBUG
    private var lastReportedFrameCount = 0
    #endif
    
    init(region: LongCaptureRegion, initialImage: CGImage, frameSource: (any LongCaptureFrameSource)? = nil) throws {
        self.region = region
        let trace = LongCaptureTrace()
        diagnosticTrace = trace
        captureService = frameSource ?? LongCaptureStreamService(trace: trace)
        let accumulator = LongCaptureFrameAccumulator(trace: trace)
        progress = try accumulator.seed(image: initialImage)
        frames = accumulator
    }
    
    func start() async throws {
        try Task.checkCancellation()
        guard !isStarted else { return }
        #if DEBUG
        MemoryTrace.mark("long_stream_starting")
        #endif
        isStarted = true
        await MainActor.run {
            self.status = .capturing
        }
        do {
            try await startStream()
        } catch {
            await MainActor.run {
                self.isStarted = false
                self.status = error is CancellationError ? .cancelled : .failed(error.localizedDescription)
            }
            throw error
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
    
    func finish() async throws -> FinishResult {
        let finishStart = diagnosticTrace.startTime()
        // Frame state still belongs to outputQueue until stop has drained it.
        diagnosticTrace.event("event=finish-requested selectionRect=\(LongCaptureTrace.rect(region.selectionRect))")
        #if DEBUG
        MemoryTrace.mark("long_finish_started")
        #endif
        await MainActor.run {
            self.status = .finishing
        }
        let image: NSImage
        do {
            let finalFrame = try await captureService.finishFrame()
            try Task.checkCancellation()
            #if DEBUG
            MemoryTrace.mark("long_stream_stopped")
            #endif
            guard let frames else { throw LongCaptureError.noStableFrame }
            if let finalFrame {
                let finalProgress = frames.process(frame: finalFrame)
                if let finalProgress { lastObservedProgress = finalProgress }
                diagnosticTrace.event("event=finish-final-observation ts=\(finalFrame.timestamp) unmatched=\(finalProgress?.warning != nil) height=\(finalProgress?.appendedPixelHeight ?? 0)")
            }
            image = try frames.renderFinalImage()
            try Task.checkCancellation()
        } catch {
            diagnosticTrace.event("event=finish-ended outcome=\(LongCaptureTrace.errorLabel(error)) elapsedMs=\(diagnosticTrace.elapsed(since: finishStart))")
            var terminalError = error
            if frames != nil, let warning = Self.retryWarning(for: error), !Task.isCancelled {
                do {
                    try await resumeAfterFailedFinish(warning: warning)
                    return .resumedCapture
                } catch {
                    terminalError = error
                    diagnosticTrace.event("event=finish-recovery-failed outcome=\(LongCaptureTrace.errorLabel(error))")
                }
            }
            await captureService.stop()
            frames = nil
            let status: LongCaptureStatus = terminalError is CancellationError || Task.isCancelled
                ? .cancelled : .failed(terminalError.localizedDescription)
            await MainActor.run { self.status = status }
            throw terminalError
        }
        // stop() has drained the output queue. Drop raw frames, stored strips and
        // session temporary files before handing the sole output bitmap to UI.
        frames = nil
        #if DEBUG
        MemoryTrace.mark("long_image_rendered")
        #endif
        if image.size.width > 0 {
            image.size = NSSize(width: region.selectionRect.width,
                                height: image.size.height * region.selectionRect.width / image.size.width)
        }
        diagnosticTrace.event("event=finish-ended outcome=success logicalSize=\(image.size.width)x\(image.size.height) elapsedMs=\(diagnosticTrace.elapsed(since: finishStart))")
        await MainActor.run {
            self.status = .completed
        }
        #if DEBUG
        MemoryTrace.mark("long_finish_completed")
        #endif
        return .completed(image)
    }

    private func startStream() async throws {
        try await captureService.start(region: region) { [weak self] frame in
            self?.handle(frame: frame)
        }
    }

    private static func retryWarning(for error: Error) -> String? {
        switch error {
        case LongCaptureError.incompleteCapture:
            return "已保留截图内容。请滚回上次接上的位置，再按回车完成。"
        case LongCaptureError.unstableFinish:
            return "已保留截图内容。请等画面稳定后，再按回车完成。"
        default:
            return nil
        }
    }

    private func resumeAfterFailedFinish(warning: String) async throws {
        // finishFrame has drained the old stream. Publish the latest confirmed
        // height and skip queued progress from that stream before reopening it.
        let previousProgress = lastObservedProgress
        await MainActor.run {
            self.progressLock.withLock { self.latestProgress = nil }
            var retryProgress = previousProgress ?? self.progress
            retryProgress.warning = warning
            self.progress = retryProgress
            self.status = .capturing
        }
        try Task.checkCancellation()
        try await startStream()
        try Task.checkCancellation()
        diagnosticTrace.event("event=finish-recovery-resumed")
    }
    
    func cancel() async {
        let cancelStart = diagnosticTrace.startTime()
        diagnosticTrace.event("event=cancel-requested")
        await captureService.stop()
        frames = nil
        diagnosticTrace.event("event=cancel-ended elapsedMs=\(diagnosticTrace.elapsed(since: cancelStart))")
        await MainActor.run {
            self.status = .cancelled
        }
    }
    
    private func handle(frame: LongCaptureFrame) {
        guard captureService.isRunning else { return }
        guard let progress = frames?.process(frame: frame), progress != lastObservedProgress else { return }
        lastObservedProgress = progress
        #if DEBUG
        if progress.acceptedFrameCount > lastReportedFrameCount {
            lastReportedFrameCount = progress.acceptedFrameCount
            if progress.acceptedFrameCount == 1 { MemoryTrace.mark("long_first_frame") }
            if progress.acceptedFrameCount == 10 { MemoryTrace.mark("long_tenth_frame") }
        }
        #endif
        publish(progress)
    }

    private func publish(_ progress: LongCaptureProgress) {
        progressLock.lock()
        latestProgress = progress
        let shouldSchedule = !progressPublicationQueued
        progressPublicationQueued = true
        progressLock.unlock()
        guard shouldSchedule else { return }
        // At most one UI publication waits for MainActor, even when capture is
        // producing frames while the editor/menu temporarily blocks the UI.
        Task { @MainActor [weak self] in
            guard let self, let progress = self.takeLatestProgress(), self.status == .capturing else { return }
            self.progress = progress
        }
    }

    private func takeLatestProgress() -> LongCaptureProgress? {
        progressLock.lock()
        defer { progressLock.unlock() }
        progressPublicationQueued = false
        defer { latestProgress = nil }
        return latestProgress
    }
}
