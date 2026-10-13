import AppKit
import ScreenCaptureKit
import CoreMedia
import OSLog

final class LongCaptureStreamService: @unchecked Sendable {
    private let outputQueue = DispatchQueue(label: "com.libreshot.long-capture")
    private let lifecycleGate = StreamLifecycleGate()
    private let traceEnabled = ProcessInfo.processInfo.environment["LIBRESHOT_LONG_CAPTURE_TRACE"] == "1"
    private let logger = Logger(subsystem: "com.allensong.LibreShot", category: "LongCapture")
    private let diagnosticTrace: LongCaptureTrace
    private var streamFrameSequence = 0
    private var previousStreamTimestamp: CFTimeInterval?
    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    // ScreenCaptureKit stopCapture() is asynchronous. Keep the in-flight
    // teardown so a new long-capture stream cannot overlap it.
    private var stopTask: Task<Void, Never>?
    private var region: LongCaptureRegion?
    private var geometry: LongCaptureStreamGeometry?
    private var finalFilter: SCContentFilter?
    private var finalConfiguration: SCStreamConfiguration?
    private var onFrame: ((LongCaptureFrame) -> Void)?
    private var minimumFrameInterval: CFTimeInterval = 0.10
    private(set) var isRunning = false
    private var isPaused = false
    #if DEBUG
    private var processedFrameCount = 0
    #endif

    init(trace: LongCaptureTrace = LongCaptureTrace()) {
        diagnosticTrace = trace
    }
    
    func start(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws {
        await lifecycleGate.acquire()
        do {
            try Task.checkCancellation()
            try await startUnlocked(region: region, onFrame: onFrame)
            await lifecycleGate.release()
        } catch {
            await stopUnlocked()
            finalFilter = nil
            finalConfiguration = nil
            await lifecycleGate.release()
            throw error
        }
    }

    private func startUnlocked(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws {
        await waitForPendingStop()
        guard outputQueue.sync(execute: { !isRunning }) else { return }

        let content = try await ScreenCaptureAccess.content {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureServiceError.noDisplay
        }
        
        try Task.checkCancellation()
        
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
        guard let geometry = LongCaptureStreamGeometry(region: region,
                                                        displayPixelWidth: Int(pixelSize.width),
                                                        displayPixelHeight: Int(pixelSize.height)) else {
            throw CaptureServiceError.captureFailed
        }
        let frameBudget = LongCaptureLimits().maximumFrameBytes
        guard geometry.width <= frameBudget / 4,
              geometry.height <= frameBudget / (geometry.width * 4) else {
            throw LongCaptureError.resourceLimit
        }
        let configuration = CaptureService.displayConfiguration(width: geometry.width, height: geometry.height,
                                                                 sourceRect: geometry.sourceRect)
        // SCK retains capture surfaces per queued frame. Keep the long stream
        // at Apple's documented minimum rather than inheriting a diagnostic
        // override used by one-shot capture experiments.
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(seconds: minimumFrameInterval, preferredTimescale: 600)
        try Task.checkCancellation()
        
        let output = CaptureStreamOutput { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        // Retain the local owner before adding output so that even an output
        // registration failure follows the same teardown path.
        self.finalFilter = filter
        self.finalConfiguration = configuration
        self.streamOutput = output
        self.stream = stream
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
        outputQueue.sync {
            self.region = region
            self.geometry = geometry
            self.onFrame = onFrame
            self.isPaused = false
            self.isRunning = true
            self.streamFrameSequence = 0
            self.previousStreamTimestamp = nil
            #if DEBUG
            self.processedFrameCount = 0
            #endif
        }
        try await stream.startCapture()
        try Task.checkCancellation()
    }
    
    func pause() {
        outputQueue.async { self.isPaused = true }
    }
    
    func resume() {
        outputQueue.async {
            self.isPaused = false
        }
    }
    
    /// Stop/drain the live stream, then let the actual finish position settle.
    /// A duplicate with an invented timestamp cannot provide this evidence. The
    /// fresh bounded stream uses the same excluded-app filter and native region,
    /// and never overlaps the continuous stream's surfaces (macOS 13 compatible).
    func finishFrame() async throws -> LongCaptureFrame? {
        await lifecycleGate.acquire()
        do {
            let context = (finalFilter, finalConfiguration)
            let paused = outputQueue.sync { isPaused }
            await stopUnlocked()
            finalFilter = nil
            finalConfiguration = nil
            try Task.checkCancellation()
            guard !paused else { await lifecycleGate.release(); return nil }
            guard let filter = context.0, let configuration = context.1 else {
                throw LongCaptureError.noStableFrame
            }
            let frame = try await captureFinalFrame(filter: filter, configuration: configuration)
            try Task.checkCancellation()
            await lifecycleGate.release()
            return frame
        } catch {
            await lifecycleGate.release()
            throw error
        }
    }

    private func captureFinalFrame(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> LongCaptureFrame {
        let request = CaptureRequestState<LongCaptureFrame>()
        let observer = LongCaptureFinalFrameObserver(queue: outputQueue, request: request,
            width: configuration.width, height: configuration.height, trace: diagnosticTrace)
        let output = CaptureStreamOutput { observer.handle(sampleBuffer: $0) }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        outputQueue.async { observer.start() }
        // Capture lifecycle drains this queue before returning, including on
        // startup failure/cancellation. Do not leave a timer owning frame data.
        defer { outputQueue.sync { observer.discard() } }
        return try await withTaskCancellationHandler {
            try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
                try await stream.startCapture()
            }, stop: {
                try? await stream.stopCapture()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    self.outputQueue.async { continuation.resume() }
                }
                try? stream.removeStreamOutput(output, type: .screen)
            })
        } onCancel: {
            request.fail(CancellationError())
            self.outputQueue.async { observer.discard() }
        }
    }

    func stop() async {
        diagnosticTrace.event("event=stop-requested")
        await lifecycleGate.acquire()
        await stopUnlocked()
        finalFilter = nil
        finalConfiguration = nil
        await lifecycleGate.release()
    }

    private func stopUnlocked() async {
        let stopStart = diagnosticTrace.startTime()
        diagnosticTrace.event("event=stop-start")
        defer { diagnosticTrace.event("event=stop-ended elapsedMs=\(diagnosticTrace.elapsed(since: stopStart))") }
        await waitForPendingStop()
        guard let stream else {
            outputQueue.sync { self.isRunning = false }
            diagnosticTrace.event("event=stop-no-stream")
            return
        }
        let streamOutput = self.streamOutput
        self.stream = nil
        self.streamOutput = nil
        let outputQueue = self.outputQueue

        let task = Task { [weak self] in
            try? await stream.stopCapture()
            self?.diagnosticTrace.event("event=stop-capture-returned")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                outputQueue.async {
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.isRunning = false
                    self.onFrame = nil
                    self.region = nil
                    self.geometry = nil
                    self.diagnosticTrace.event("event=stop-queue-drained paused=\(self.isPaused)")
                    continuation.resume()
                }
            }
            if let streamOutput {
                try? stream.removeStreamOutput(streamOutput, type: .screen)
            }
        }
        self.stopTask = task
        await task.value
        self.stopTask = nil
    }

    private func waitForPendingStop() async {
        guard let stopTask else { return }
        await stopTask.value
        self.stopTask = nil
    }
    
    private func handle(sampleBuffer: CMSampleBuffer) {
        guard isRunning, !isPaused, let geometry, let onFrame else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let processingStart = traceEnabled ? CFAbsoluteTimeGetCurrent() : 0
        var streamSequence = 0
        var timestampDelta: CFTimeInterval?
        if traceEnabled {
            streamFrameSequence += 1
            streamSequence = streamFrameSequence
            timestampDelta = previousStreamTimestamp.map { timestamp - $0 }
            previousStreamTimestamp = timestamp
        }
        
        // ScreenCaptureKit now produces only the selected native-pixel region.
        // Never crop it a second time with full-display coordinates.
        let pixelRect = CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height)
        guard CVPixelBufferGetWidth(imageBuffer) == geometry.width,
              CVPixelBufferGetHeight(imageBuffer) == geometry.height,
              let croppedImage = CaptureFrameImage.copy(from: imageBuffer) else {
            diagnosticTrace.event("event=stream-crop-failed frame=\(streamSequence) sourceSize=\(CVPixelBufferGetWidth(imageBuffer))x\(CVPixelBufferGetHeight(imageBuffer)) expected=\(geometry.width)x\(geometry.height)")
            return
        }

        let frame = LongCaptureFrame(image: croppedImage, timestamp: timestamp)
        onFrame(frame)
        if traceEnabled {
            // This is an interval estimate, not a measured dropped-frame count:
            // ScreenCaptureKit may skip identical or idle display updates.
            let inferredIntervalGap = timestampDelta.map { max(0, Int(($0 / minimumFrameInterval).rounded()) - 1) } ?? 0
            let elapsed = (CFAbsoluteTimeGetCurrent() - processingStart) * 1000
            logger.notice("Long capture source=stream frame=\(streamSequence) ts=\(String(format: "%.3f", timestamp), privacy: .public) delta=\(timestampDelta.map { String(format: "%.3f", $0) } ?? "-", privacy: .public) inferredIntervalGap=\(inferredIntervalGap) callbackElapsedMs=\(String(format: "%.2f", elapsed), privacy: .public) trace=\(self.diagnosticTrace.id, privacy: .public) sourceSize=\(CVPixelBufferGetWidth(imageBuffer))x\(CVPixelBufferGetHeight(imageBuffer)) cropRect=\(LongCaptureTrace.rect(pixelRect), privacy: .public) croppedSize=\(croppedImage.width)x\(croppedImage.height)")
        }
        #if DEBUG
        processedFrameCount += 1
        if processedFrameCount == 10 { MemoryTrace.mark("long_10_frames_processed") }
        if processedFrameCount == 100 { MemoryTrace.mark("long_100_frames_processed") }
        #endif
    }
}

/// Output-queue owner for final observation/timers. It retains one detached
/// latest frame, never an array of surfaces or frames. Stability only chooses
/// which real frame to validate; it cannot bypass document/seam validation.
nonisolated private final class LongCaptureFinalFrameObserver: @unchecked Sendable {
    private let queue: DispatchQueue
    private let request: CaptureRequestState<LongCaptureFrame>
    private let width: Int, height: Int
    private let trace: LongCaptureTrace
    private let window: LongCaptureFrameSettlement<LongCaptureFrame>
    private var timer: DispatchWorkItem?
    private var finished = false
    private var observedFrames = 0

    init(queue: DispatchQueue, request: CaptureRequestState<LongCaptureFrame>,
         width: Int, height: Int, trace: LongCaptureTrace) {
        self.queue = queue
        self.request = request
        self.width = width
        self.height = height
        self.trace = trace
        window = LongCaptureFrameSettlement(startedAt: ProcessInfo.processInfo.systemUptime,
            areEqual: { LongCaptureFrameDeduplicator.samePixels($0.image, $1.image) })!
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { return }
        update(window.poll(at: ProcessInfo.processInfo.systemUptime))
    }

    func handle(sampleBuffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return }
        if status == .idle {
            update(window.poll(at: ProcessInfo.processInfo.systemUptime))
            return
        }
        if status == .blank || status == .suspended || status == .stopped {
            // These statuses do not mean a quiet display. Never return a prior
            // complete frame after the display went blank or updates stopped.
            discard()
            request.fail(LongCaptureError.unstableFinish)
            return
        }
        guard status == .complete else { return }
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              let image = CaptureFrameImage.copy(from: buffer) else {
            discard()
            request.fail(CaptureServiceError.imageConversionFailed)
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard timestamp.isFinite else {
            discard()
            request.fail(LongCaptureError.noStableFrame)
            return
        }
        observedFrames += 1
        update(window.observe(LongCaptureFrame(image: image, timestamp: timestamp),
                              receivedAt: ProcessInfo.processInfo.systemUptime))
    }

    func discard() {
        dispatchPrecondition(condition: .onQueue(queue))
        finished = true
        timer?.cancel()
        timer = nil
        window.cancel()
    }

    private func update(_ update: LongCaptureFrameSettlement<LongCaptureFrame>.Update) {
        guard !finished else { return }
        timer?.cancel()
        timer = nil
        switch update {
        case .waiting(let nextCheckAt):
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.finished else { return }
                self.update(self.window.poll(at: ProcessInfo.processInfo.systemUptime))
            }
            timer = work
            queue.asyncAfter(deadline: .now() + max(0, nextCheckAt - ProcessInfo.processInfo.systemUptime), execute: work)
        case .settled(let frame):
            finished = true
            trace.event("event=finish-position-settled observed=\(observedFrames) ts=\(frame.timestamp)")
            request.succeed(frame)
        case .failed(let reason):
            finished = true
            trace.event("event=finish-position-failed observed=\(observedFrames) reason=\(reason)")
            request.fail(reason == .cancelled ? CancellationError() : LongCaptureError.unstableFinish)
        case .terminal:
            finished = true
        }
    }
}
