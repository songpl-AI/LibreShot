import Foundation
import CoreGraphics
import Vision

nonisolated enum OCRError: Error, LocalizedError {
    case recognitionFailed(String)
    case missingImage
    
    var errorDescription: String? {
        switch self {
        case .recognitionFailed(let message):
            return "OCR Recognition Failed: \(message)"
        case .missingImage:
            return "无法获取图片内容"
        }
    }
}

nonisolated struct OCRTextRegion: Identifiable, Sendable, Codable {
    let id: Int
    var text: String
    /// Normalized image coordinates, with the origin at the top left.
    var bounds: CGRect
    var confidence: Float
    var lineCount: Int = 1

    static func readingOrder(from lines: [OCRTextRegion]) -> [OCRTextRegion] {
        // Keep original line bounds: proximity alone cannot distinguish paragraphs from table cells.
        var ordered: [OCRTextRegion] = []
        var remaining = lines.sorted { $0.bounds.minY < $1.bounds.minY }
        while let first = remaining.first {
            let row = remaining.filter {
                abs($0.bounds.minY - first.bounds.minY) <= min($0.bounds.height / CGFloat($0.lineCount), first.bounds.height / CGFloat(first.lineCount)) * 0.5
            }
            let ids = Set(row.map(\.id))
            ordered.append(contentsOf: row.sorted { $0.bounds.minX < $1.bounds.minX })
            remaining.removeAll { ids.contains($0.id) }
        }
        return ordered
    }
}

// Only cancellation crosses threads; request configuration is immutable once work starts.
nonisolated final class OCRRecognitionOperation: @unchecked Sendable {
    private static let workQueue = DispatchQueue(label: "LibreShot.OCR", qos: .userInitiated)
    private let request: VNRecognizeTextRequest
    private let lock = NSLock()
    private var cancelled = false

    init(request: VNRecognizeTextRequest = VNRecognizeTextRequest()) {
        self.request = request
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    private func cancel() {
        lock.withLock { cancelled = true }
        request.cancel()
    }

    func run(image: CGImage, queue: DispatchQueue = workQueue) async throws -> [OCRTextRegion] {
        let regions: [OCRTextRegion] = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    autoreleasepool {
                        do {
                            guard !self.isCancelled else { throw CancellationError() }
                            try VNImageRequestHandler(cgImage: image, options: [:]).perform([self.request])
                            guard !self.isCancelled else { throw CancellationError() }
                            let regions = (self.request.results ?? []).enumerated().compactMap { index, observation -> OCRTextRegion? in
                                guard let text = observation.topCandidates(1).first, !text.string.isEmpty else { return nil }
                                let rect = observation.boundingBox
                                return OCRTextRegion(id: index, text: text.string,
                                                     bounds: CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height),
                                                     confidence: text.confidence)
                            }
                            continuation.resume(returning: regions)
                        } catch {
                            continuation.resume(throwing: self.isCancelled ? CancellationError() : OCRError.recognitionFailed(error.localizedDescription))
                        }
                    }
                }
            }
        } onCancel: { self.cancel() }
        try Task.checkCancellation()
        return regions
    }
}
