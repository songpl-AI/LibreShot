import Foundation
import Cocoa
import Vision

enum OCRError: Error, LocalizedError {
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

class OCRService {
    static let shared = OCRService()
    
    private init() {}
    
    func recognizeText(from image: NSImage) async throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.recognitionFailed("Could not convert NSImage to CGImage")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                let fullText = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: fullText)
            }
            
            // Configure for accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"] // Prioritize Chinese and English
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}
