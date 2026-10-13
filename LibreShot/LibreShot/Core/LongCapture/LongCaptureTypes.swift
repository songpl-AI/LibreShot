import AppKit
import OSLog

struct LongCaptureRegion {
    let selectionRect: CGRect
    let screenRect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
}

struct LongCaptureProgress: Equatable {
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
    case unstableFinish
    case rendererFailed
    case incompleteCapture
    case resourceLimit
    case storageFailed
    
    var errorDescription: String? {
        switch self {
        case .noStableFrame:
            return "未采集到有效的滚动帧，请重试"
        case .unstableFinish:
            return "画面仍在滚动或持续变化，未能取得稳定的结束画面。请等待页面停止滚动后再完成长截图。"
        case .rendererFailed:
            return "长截图拼接失败"
        case .incompleteCapture:
            return "有滚动画面未能接上，本次未生成完整长截图。请重新框选可滚动内容，缓慢向下滚动，保留至少三分之一的重叠区域。"
        case .resourceLimit:
            return "长截图已达到图像内存上限。请回到上次接上的位置完成截图，或分段截取。"
        case .storageFailed:
            return "长截图临时存储失败，未生成完整图片。请检查可用磁盘空间后重试。"
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

/// Numeric lifecycle evidence only. Formatting and logging stay disabled unless
/// explicitly requested; tracing never decodes an image or retains frame data.
nonisolated struct LongCaptureTrace {
    let enabled = ProcessInfo.processInfo.environment["LIBRESHOT_LONG_CAPTURE_TRACE"] == "1"
    let id = UUID().uuidString
    private let logger = Logger(subsystem: "com.allensong.LibreShot", category: "LongCapture")

    func event(_ details: @autoclosure () -> String) {
        guard enabled else { return }
        let message = details()
        logger.notice("Long capture trace=\(self.id, privacy: .public) \(message, privacy: .public)")
    }

    func startTime() -> CFTimeInterval { enabled ? CFAbsoluteTimeGetCurrent() : 0 }

    func elapsed(since start: CFTimeInterval) -> String {
        String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    static func rect(_ rect: CGRect?) -> String {
        guard let rect else { return "-" }
        return String(format: "%.2f,%.2f,%.2f,%.2f", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func errorLabel(_ error: Error) -> String {
        switch error {
        case LongCaptureError.incompleteCapture: return "incomplete-capture"
        case LongCaptureError.noStableFrame: return "no-stable-frame"
        case LongCaptureError.unstableFinish: return "unstable-finish"
        case LongCaptureError.rendererFailed: return "renderer-failed"
        case LongCaptureError.resourceLimit: return "resource-limit"
        case LongCaptureError.storageFailed: return "storage-failed"
        case is CancellationError: return "cancelled"
        default: return "other-error"
        }
    }
}

/// Bounded, image-content-free evidence for a long-capture stitch decision.
///
/// This intentionally records matcher shape and scores only. It does not retain
/// frames or serialize pixels, so enabling the per-frame trace cannot make a
/// failed capture heavier or expose the captured document in the log.
struct LongCaptureMatchDiagnostics {
    var outcome = "not-run"
    var width = 0
    var height = 0
    var changingColumns = 0
    var changingRows = 0
    var rowTop: Int?
    var rowBottom: Int?
    var candidateCount = 0
    var contenderCount = 0
    var coarseShift: Int?
    var coarseError: Double?
    var bestShift: Int?
    var bestError: Double?
    var secondShift: Int?
    var secondError: Double?
    var overlapHeight: Int?
    var confidence: Double?
    var previousWidth = 0
    var previousHeight = 0
    var currentWidth = 0
    var currentHeight = 0
    var footerHeight: Int?

    var summary: String {
        func optionalInt(_ value: Int?) -> String { value.map(String.init) ?? "-" }
        func optionalDouble(_ value: Double?) -> String {
            value.map { String(format: "%.4f", $0) } ?? "-"
        }
        return "outcome=\(outcome) size=\(width)x\(height) cols=\(changingColumns) rows=\(changingRows) range=\(optionalInt(rowTop))-\(optionalInt(rowBottom)) candidates=\(candidateCount) contenders=\(contenderCount) coarse=\(optionalInt(coarseShift))/\(optionalDouble(coarseError)) best=\(optionalInt(bestShift))/\(optionalDouble(bestError)) second=\(optionalInt(secondShift))/\(optionalDouble(secondError)) overlap=\(optionalInt(overlapHeight)) confidence=\(optionalDouble(confidence))"
    }

    var traceSummary: String {
        "\(summary) original=\(previousWidth)x\(previousHeight)/\(currentWidth)x\(currentHeight) footerHeight=\(footerHeight.map(String.init) ?? "-")"
    }
}

/// Numeric-only proof for a no-motion decision; never retains capture pixels.
struct LongCaptureStationaryDiagnostics {
    var outcome = "not-run"
    var changedPixels = 0
    var left = 0, top = 0, width = 0, height = 0
    var maximumDelta = 0
    var uniformColorPair = false
    var anchorBands = [Int](repeating: 0, count: 4)
    var uniqueZeroRequired = false

    var traceSummary: String {
        "outcome=\(outcome) changedPixels=\(changedPixels) bbox=\(left),\(top),\(width),\(height) maxDelta=\(maximumDelta) uniformPair=\(uniformColorPair) anchorBands=\(anchorBands) uniqueZeroRequired=\(uniqueZeroRequired)"
    }
}

struct LongCaptureAppendDiagnostics {
    var outcome = "not-run"
    var forward: LongCaptureMatchDiagnostics?
    var reverse: LongCaptureMatchDiagnostics?
    var stationaryRedraw = false
    var stationary: LongCaptureStationaryDiagnostics?
    var frameWidth = 0
    var frameHeight = 0
    var cachedFooterHeight: Int?
    var effectiveFooterHeight: Int?
    var cropRect: CGRect?
    var footerCropRect: CGRect?
    var initialTrimCropRect: CGRect?
    var segmentYOffset: Int?
    var segmentWidth: Int?
    var segmentHeight: Int?
    var segmentCount = 0
    var totalHeightBefore = 0
    var totalHeightAfter = 0

    var summary: String {
        let forwardSummary = forward?.summary ?? "-"
        let reverseSummary = reverse?.summary ?? "-"
        return "outcome=\(outcome) stationaryRedraw=\(stationaryRedraw) stationary=[\(stationary?.traceSummary ?? "-")] forward=[\(forwardSummary)] reverse=[\(reverseSummary)]"
    }

    var traceSummary: String {
        func optionalInt(_ value: Int?) -> String { value.map(String.init) ?? "-" }
        return "outcome=\(outcome) stationaryRedraw=\(stationaryRedraw) stationary=[\(stationary?.traceSummary ?? "-")] frame=\(frameWidth)x\(frameHeight) cachedFooter=\(optionalInt(cachedFooterHeight)) effectiveFooter=\(optionalInt(effectiveFooterHeight)) cropRect=\(LongCaptureTrace.rect(cropRect)) footerCropRect=\(LongCaptureTrace.rect(footerCropRect)) initialTrimCropRect=\(LongCaptureTrace.rect(initialTrimCropRect)) segmentYOffset=\(optionalInt(segmentYOffset)) segmentSize=\(optionalInt(segmentWidth))x\(optionalInt(segmentHeight)) segmentCount=\(segmentCount) totalBefore=\(totalHeightBefore) totalAfter=\(totalHeightAfter) forward=[\(forward?.traceSummary ?? "-")] reverse=[\(reverse?.traceSummary ?? "-")]"
    }
}

struct LongCaptureOverlapMatch {
    let overlapHeight: Int
    let confidence: Double
    var footerHeight: Int = 0
}


