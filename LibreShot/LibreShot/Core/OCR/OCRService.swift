import Foundation
import Cocoa
import Vision

class OCRService {
    static let shared = OCRService()
    
    private init() {}

    func cancelAll() { OCRWorkerOperation.cancelAll() }
    
    func recognizeText(from image: NSImage) async throws -> String {
        try await recognizeRegions(from: image).map(\.text).joined(separator: "\n")
    }

    func recognizeRegions(from image: NSImage) async throws -> [OCRTextRegion] {
        #if DEBUG
        MemoryTrace.mark("vision_ocr_started")
        defer { MemoryTrace.mark("vision_ocr_finished") }
        #endif
        try Task.checkCancellation()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.recognitionFailed("Could not convert NSImage to CGImage")
        }
        
        return try await OCRWorkerOperation().run(image: cgImage)
    }
}
