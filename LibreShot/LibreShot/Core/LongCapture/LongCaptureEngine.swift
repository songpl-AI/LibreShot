import AppKit
import OSLog

/// Owns the accepted-frame baseline and completion validation on the capture queue.
/// An unmatched final frame must not turn into a successful one-screen "long" image.
enum LongCaptureConnectionState {
    case empty
    case atFrontier
    case revisiting
    case unresolved(LongCaptureError)
}

final class LongCaptureFrameAccumulator {
    private let deduplicator = LongCaptureFrameDeduplicator()
    private let stitcher: LongCaptureStitcher
    private let diagnosticTrace: LongCaptureTrace
    private(set) var connection: LongCaptureConnectionState = .empty
    private var hasUnmatchedFrame: Bool {
        if case .unresolved = connection { return true }
        return false
    }
    private var frameSequence = 0
    private var previousTimestamp: CFTimeInterval?
    /// Per-frame matcher traces are opt-in because formatting/logging on the
    /// serial ScreenCaptureKit output queue can perturb capture timing.
    private let traceEnabled = ProcessInfo.processInfo.environment["LIBRESHOT_LONG_CAPTURE_TRACE"] == "1"
    private let logger = Logger(subsystem: "com.allensong.LibreShot", category: "LongCapture")

    init(trace: LongCaptureTrace = LongCaptureTrace(), limits: LongCaptureLimits = LongCaptureLimits()) {
        diagnosticTrace = trace
        stitcher = LongCaptureStitcher(trace: trace, limits: limits)
    }

    /// Commit the frozen selection before input is returned to the source app.
    /// This is a real preview image, not a fabricated stream observation.
    func seed(image: CGImage) throws -> LongCaptureProgress {
        guard case .empty = connection else { throw LongCaptureError.noStableFrame }
        let result = stitcher.append(image: image)
        guard result.accepted else {
            connection = .unresolved(stitcher.lastFailure ?? .noStableFrame)
            throw stitcher.lastFailure ?? LongCaptureError.noStableFrame
        }
        deduplicator.markAccepted(image: image)
        connection = .atFrontier
        diagnosticTrace.event("event=initial-preview-committed width=\(image.width) height=\(image.height)")
        return LongCaptureProgress(acceptedFrameCount: stitcher.acceptedFrameCount,
                                   appendedPixelHeight: stitcher.totalPixelHeight)
    }

    func process(frame: LongCaptureFrame) -> LongCaptureProgress? {
        let processingStart = CFAbsoluteTimeGetCurrent()
        frameSequence += 1
        let sequence = frameSequence
        let timestampDelta = previousTimestamp.map { frame.timestamp - $0 }
        previousTimestamp = frame.timestamp
        let wasUnmatched = hasUnmatchedFrame
        switch deduplicator.process(frame: frame) {
        case .ignore:
            // Returning to the last accepted position clears the retry warning.
            connection = .atFrontier
            stitcher.restoreFrontier()
            guard wasUnmatched else {
                if traceEnabled {
                    let elapsed = (CFAbsoluteTimeGetCurrent() - processingStart) * 1000
                    logger.notice("Long capture frame=\(sequence) ts=\(String(format: "%.3f", frame.timestamp), privacy: .public) delta=\(timestampDelta.map { String(format: "%.3f", $0) } ?? "-", privacy: .public) decision=ignore accepted=\(self.stitcher.acceptedFrameCount) height=\(self.stitcher.totalPixelHeight) elapsedMs=\(String(format: "%.2f", elapsed), privacy: .public) reason=deduplicated")
                }
                return nil
            }
            if traceEnabled {
                let elapsed = (CFAbsoluteTimeGetCurrent() - processingStart) * 1000
                logger.notice("Long capture frame=\(sequence) ts=\(String(format: "%.3f", frame.timestamp), privacy: .public) delta=\(timestampDelta.map { String(format: "%.3f", $0) } ?? "-", privacy: .public) decision=ignore accepted=\(self.stitcher.acceptedFrameCount) height=\(self.stitcher.totalPixelHeight) elapsedMs=\(String(format: "%.2f", elapsed), privacy: .public) reason=retry-frontier")
            }
        case .accept:
            let result = stitcher.append(frame: frame)
            if result.accepted {
                connection = stitcher.lastAppendDiagnostics.outcome == "reverse-revisit" ? .revisiting : .atFrontier
            } else {
                connection = .unresolved(stitcher.lastFailure ?? .incompleteCapture)
            }
            // Revisiting captured content must not move the forward matching baseline.
            if result.accepted, result.appendedPixelHeight > 0 { deduplicator.markAccepted(frame) }
            if traceEnabled {
                let elapsed = (CFAbsoluteTimeGetCurrent() - processingStart) * 1000
                logger.notice("Long capture frame=\(sequence) ts=\(String(format: "%.3f", frame.timestamp), privacy: .public) delta=\(timestampDelta.map { String(format: "%.3f", $0) } ?? "-", privacy: .public) accepted=\(result.accepted) appended=\(result.appendedPixelHeight) totalAccepted=\(self.stitcher.acceptedFrameCount) height=\(self.stitcher.totalPixelHeight) elapsedMs=\(String(format: "%.2f", elapsed), privacy: .public) match={\(self.stitcher.lastAppendDiagnostics.traceSummary, privacy: .public)}")
            }
        }
        if hasUnmatchedFrame != wasUnmatched {
            if traceEnabled {
                logger.notice("Long capture unmatched=\(self.hasUnmatchedFrame), accepted=\(self.stitcher.acceptedFrameCount), height=\(self.stitcher.totalPixelHeight), frame=\(frame.image.width)x\(frame.image.height), match={\(self.stitcher.lastAppendDiagnostics.summary, privacy: .public)}")
            } else {
                logger.notice("Long capture unmatched=\(self.hasUnmatchedFrame), accepted=\(self.stitcher.acceptedFrameCount), height=\(self.stitcher.totalPixelHeight), frame=\(frame.image.width)x\(frame.image.height)")
            }
        }
        return LongCaptureProgress(acceptedFrameCount: stitcher.acceptedFrameCount,
                                   appendedPixelHeight: stitcher.totalPixelHeight,
                                   warning: hasUnmatchedFrame ? (stitcher.lastFailure == .incompleteCapture ? "当前画面未接上，请回滚到上次位置，再小幅向下滚动。" : stitcher.lastFailure?.localizedDescription) : nil)
    }

    func renderFinalImage() throws -> NSImage {
        let renderStart = diagnosticTrace.startTime()
        var outcome = "no-stable-frame"
        diagnosticTrace.event("event=render-validation-start accepted=\(stitcher.acceptedFrameCount) height=\(stitcher.totalPixelHeight) unmatched=\(hasUnmatchedFrame)")
        defer {
            diagnosticTrace.event("event=render-validation-ended outcome=\(outcome) elapsedMs=\(diagnosticTrace.elapsed(since: renderStart))")
        }
        guard !hasUnmatchedFrame else {
            outcome = "incomplete-capture"
            logger.error("Long capture final incomplete accepted=\(self.stitcher.acceptedFrameCount), height=\(self.stitcher.totalPixelHeight), lastMatch={\(self.stitcher.lastAppendDiagnostics.summary, privacy: .public)}")
            throw stitcher.lastFailure ?? LongCaptureError.incompleteCapture
        }
        let image = try stitcher.renderValidatedImage()
        outcome = "success"
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
        markAccepted(image: frame.image)
    }

    func markAccepted(image: CGImage) { acceptedImage = image }

    nonisolated static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              a.bitsPerComponent == b.bitsPerComponent, a.bitsPerPixel == b.bitsPerPixel,
              a.bitmapInfo == b.bitmapInfo, a.decode == nil, b.decode == nil,
              let ac = a.colorSpace, let bc = b.colorSpace, CFEqual(ac, bc),
              let ad = a.dataProvider?.data, let bd = b.dataProvider?.data,
              let ap = CFDataGetBytePtr(ad), let bp = CFDataGetBytePtr(bd) else { return false }
        defer { withExtendedLifetime(ad) {}; withExtendedLifetime(bd) {} }
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

/// A document advances only after a unique motion candidate, an independent
/// original-pixel seam check, and a successful strip transaction. The latest
/// observation is never promoted to the frontier merely because it repeats.
final class LongCaptureStitcher {
    private let overlapMatcher = LongCaptureOverlapMatcher()
    private let document: LongCaptureDocumentStore
    private var previousImage: CGImage?
    private var footerImage: CGImage?
    private var fixedFooterHeight: Int?
    private var initialFrameHeight = 0
    private(set) var totalPixelHeight = 0
    private(set) var acceptedFrameCount = 0
    private(set) var lastAppendDiagnostics = LongCaptureAppendDiagnostics()
    private(set) var lastFailure: LongCaptureError?
    private let diagnosticTrace: LongCaptureTrace

    init(trace: LongCaptureTrace = LongCaptureTrace(), limits: LongCaptureLimits = LongCaptureLimits()) {
        diagnosticTrace = trace
        document = LongCaptureDocumentStore(limits: limits)
    }

    /// Exact return to the committed frontier is evidence of recovery; replaying
    /// an unmatched observation, including with a new timestamp, is not.
    func restoreFrontier() { lastFailure = nil }

    private func result(accepted: Bool, appendedPixelHeight: Int, outcome: String,
                        error: LongCaptureError? = nil) -> LongCaptureAppendResult {
        lastFailure = accepted ? nil : (error ?? .incompleteCapture)
        lastAppendDiagnostics.outcome = outcome
        lastAppendDiagnostics.totalHeightAfter = totalPixelHeight
        lastAppendDiagnostics.segmentCount = document.count
        return LongCaptureAppendResult(accepted: accepted, appendedPixelHeight: appendedPixelHeight)
    }

    func append(frame: LongCaptureFrame) -> LongCaptureAppendResult {
        append(image: frame.image)
    }

    func append(image: CGImage) -> LongCaptureAppendResult {
        lastAppendDiagnostics = LongCaptureAppendDiagnostics()
        lastAppendDiagnostics.frameWidth = image.width
        lastAppendDiagnostics.frameHeight = image.height
        lastAppendDiagnostics.cachedFooterHeight = fixedFooterHeight
        lastAppendDiagnostics.totalHeightBefore = totalPixelHeight
        guard image.width > 0, image.width <= document.limits.maximumFrameBytes / 4,
              image.height > 0,
              image.height <= document.limits.maximumFrameBytes / (image.width * 4) else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "frame-limit", error: .resourceLimit)
        }
        if document.count == 0 {
            guard document.permits(width: image.width, height: image.height) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "output-limit", error: .resourceLimit)
            }
            guard let first = LongCaptureDocumentStore.detached(image, maximumBytes: document.limits.maximumFrameBytes) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "initial-copy-failed", error: .rendererFailed)
            }
            do { try document.append(first, at: 0) }
            catch { return storageFailure(error) }
            totalPixelHeight = image.height
            initialFrameHeight = image.height
            acceptedFrameCount = 1
            lastAppendDiagnostics.segmentYOffset = 0
            lastAppendDiagnostics.segmentWidth = first.width
            lastAppendDiagnostics.segmentHeight = first.height
            previousImage = image
            return result(accepted: true, appendedPixelHeight: image.height, outcome: "initial-frame")
        }
        guard let previousImage else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "missing-previous-frame")
        }
        guard previousImage.width == image.width, previousImage.height == image.height else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "dimension-mismatch")
        }
        let forward = overlapMatcher.match(previous: previousImage, current: image)
        let forwardDiagnostics = overlapMatcher.lastDiagnostics
        let reverse = overlapMatcher.match(previous: image, current: previousImage)
        lastAppendDiagnostics.forward = forwardDiagnostics
        lastAppendDiagnostics.reverse = overlapMatcher.lastDiagnostics
        if forward == nil, reverse == nil {
            let stationary = overlapMatcher.isStationaryRedraw(previous: previousImage, current: image)
            lastAppendDiagnostics.stationary = overlapMatcher.lastStationaryDiagnostics
            diagnosticTrace.event("event=stationary-proof accepted=\(stationary) details={\(overlapMatcher.lastStationaryDiagnostics.traceSummary)}")
            if stationary {
                restoreFrontier()
                lastAppendDiagnostics.stationaryRedraw = true
                return result(accepted: true, appendedPixelHeight: 0, outcome: "stationary-redraw")
            }
        }
        if let forward, let reverse, abs(forward.confidence - reverse.confidence) < 0.025 {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "ambiguous-direction")
        }
        if let reverse, reverse.confidence > (forward?.confidence ?? -.infinity) {
            let distance = image.height - reverse.overlapHeight
            guard distance <= totalPixelHeight - initialFrameHeight,
                  LongCaptureSeamVerifier.verify(previous: image, current: previousImage,
                                                 shift: distance, footerHeight: fixedFooterHeight ?? reverse.footerHeight,
                                                 bodyStart: lastAppendDiagnostics.reverse?.rowTop) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "reverse-outside-frontier")
            }
            return result(accepted: true, appendedPixelHeight: 0, outcome: "reverse-revisit")
        }
        guard let match = forward else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "forward-unmatched")
        }
        let appendHeight = image.height - match.overlapHeight
        guard appendHeight >= 1 else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "empty-forward-append")
        }
        // A stable blank suffix is only a proposal. First verify the complete
        // moving body: if it connects, no pixels need to be trimmed at all.
        // Once a real fixed bar is committed, every subsequent frame must prove
        // that same geometry; a changing bar may not be hidden in the output.
        let footerHeight: Int
        if let fixedFooterHeight, fixedFooterHeight > 0 {
            guard (match.footerHeight == 0 || match.footerHeight == fixedFooterHeight),
                  LongCaptureSeamVerifier.sameSuffix(previous: previousImage, current: image,
                                                     height: fixedFooterHeight),
                  LongCaptureSeamVerifier.verify(previous: previousImage, current: image,
                                                 shift: appendHeight, footerHeight: fixedFooterHeight, bodyStart: forwardDiagnostics.rowTop) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "footer-geometry-changed")
            }
            footerHeight = fixedFooterHeight
        } else if LongCaptureSeamVerifier.verify(previous: previousImage, current: image,
                                                 shift: appendHeight, footerHeight: 0,
                                                 allowRedraw: match.footerHeight == 0, bodyStart: forwardDiagnostics.rowTop) {
            footerHeight = 0
        } else {
            guard fixedFooterHeight == nil, match.footerHeight > 0,
                  LongCaptureSeamVerifier.sameSuffix(previous: previousImage, current: image,
                                                     height: match.footerHeight),
                  LongCaptureSeamVerifier.verify(previous: previousImage, current: image,
                                                 shift: appendHeight, footerHeight: match.footerHeight, bodyStart: forwardDiagnostics.rowTop) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "original-pixel-seam-rejected")
            }
            footerHeight = match.footerHeight
        }
        let (nextHeight, overflow) = totalPixelHeight.addingReportingOverflow(appendHeight)
        guard !overflow, document.permits(width: image.width, height: nextHeight) else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "output-limit", error: .resourceLimit)
        }
        let cropRect = CGRect(x: 0, y: match.overlapHeight - footerHeight,
                              width: image.width, height: appendHeight)
        lastAppendDiagnostics.effectiveFooterHeight = footerHeight
        lastAppendDiagnostics.cropRect = cropRect.integral
        guard let crop = image.cropping(to: cropRect),
              let appended = LongCaptureDocumentStore.detached(crop, maximumBytes: document.limits.maximumFrameBytes) else {
            return result(accepted: false, appendedPixelHeight: 0, outcome: "append-copy-failed", error: .rendererFailed)
        }
        var nextFooter: CGImage?
        var initialTrim: CGImage?
        if footerHeight > 0 {
            let rect = CGRect(x: 0, y: image.height - footerHeight,
                              width: image.width, height: footerHeight)
            lastAppendDiagnostics.footerCropRect = rect
            guard let cropped = image.cropping(to: rect),
                  let detached = LongCaptureDocumentStore.detached(cropped, maximumBytes: document.limits.maximumFrameBytes) else {
                return result(accepted: false, appendedPixelHeight: 0, outcome: "footer-copy-failed", error: .rendererFailed)
            }
            nextFooter = detached
            if fixedFooterHeight == nil {
                guard document.count == 1, let first = document.image(at: 0), first.height > footerHeight else {
                    return result(accepted: false, appendedPixelHeight: 0, outcome: "footer-trim-unavailable")
                }
                let rect = CGRect(x: 0, y: 0, width: first.width, height: first.height - footerHeight)
                lastAppendDiagnostics.initialTrimCropRect = rect
                guard let cropped = first.cropping(to: rect),
                      let detached = LongCaptureDocumentStore.detached(cropped, maximumBytes: document.limits.maximumFrameBytes) else {
                    return result(accepted: false, appendedPixelHeight: 0, outcome: "initial-trim-copy-failed", error: .rendererFailed)
                }
                initialTrim = detached
            }
        }
        let placement = totalPixelHeight - footerHeight
        do {
            if let initialTrim {
                try document.replace(with: [LongCaptureSegment(image: initialTrim, yOffset: 0),
                                             LongCaptureSegment(image: appended, yOffset: placement)])
            } else {
                try document.append(appended, at: placement)
            }
        } catch { return storageFailure(error) }
        // Every potential allocation and disk failure precedes this commit.
        footerImage = nextFooter
        fixedFooterHeight = footerHeight
        self.previousImage = image
        totalPixelHeight = nextHeight
        acceptedFrameCount += 1
        lastAppendDiagnostics.segmentYOffset = placement
        lastAppendDiagnostics.segmentWidth = appended.width
        lastAppendDiagnostics.segmentHeight = appended.height
        diagnosticTrace.event("event=document-commit segments=\(document.count) residentBytes=\(document.residentBytes) spilledBytes=\(document.spilledBytes) height=\(totalPixelHeight)")
        return result(accepted: true, appendedPixelHeight: appendHeight, outcome: "forward-append")
    }

    private func storageFailure(_ error: Error) -> LongCaptureAppendResult {
        let failure: LongCaptureError
        switch error {
        case LongCaptureDocumentStoreError.outputLimit, LongCaptureDocumentStoreError.frameLimit,
             LongCaptureDocumentStoreError.segmentLimit: failure = .resourceLimit
        case LongCaptureDocumentStoreError.storageFailure: failure = .storageFailed
        default: failure = .rendererFailed
        }
        return result(accepted: false, appendedPixelHeight: 0,
                      outcome: LongCaptureTrace.errorLabel(failure), error: failure)
    }

    func renderValidatedImage() throws -> NSImage {
        if let lastFailure { throw lastFailure }
        guard document.count > 0 else { throw LongCaptureError.noStableFrame }
        let start = diagnosticTrace.startTime()
        diagnosticTrace.event("event=render-start output=\(document.width ?? 0)x\(totalPixelHeight) segmentCount=\(document.count) footerHeight=\(footerImage?.height ?? 0)")
        do {
            let image = try document.render(height: totalPixelHeight, footer: footerImage)
            diagnosticTrace.event("event=render-ended outcome=success elapsedMs=\(diagnosticTrace.elapsed(since: start))")
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            _ = storageFailure(error)
            throw lastFailure ?? .rendererFailed
        }
    }

    /// Kept for the direct-engine checks; sessions use the throwing API.
    func renderFinalImage() -> NSImage? { try? renderValidatedImage() }
}
