import Foundation
import Combine
import CoreGraphics
import SwiftUI

enum OverlayState {
    case idle
    case selecting
    case editing
}

enum CaptureAction {
    case copy
    case save
}

class OverlayViewModel: ObservableObject {
    // Selection State
    @Published var startPoint: CGPoint?
    @Published var currentPoint: CGPoint?
    @Published var selectionRect: CGRect = .zero
    @Published var state: OverlayState = .idle
    
    // Editor State
    @Published var selectedTool: AnnotationType?
    @Published var annotations: [Annotation] = []
    @Published var currentAnnotation: Annotation?
    @Published var selectedColor: Color = .red
    
    // Actions
    var onCapture: ((CGRect, [Annotation], CaptureAction) -> Void)?
    var onCancel: (() -> Void)?
    
    // MARK: - Finalize
    
    func confirmCopy() {
        onCapture?(selectionRect, annotations, .copy)
    }
    
    func confirmSave() {
        onCapture?(selectionRect, annotations, .save)
    }
    
    func cancel() {
        onCancel?()
    }
    
    // MARK: - Selection Logic
    
    func startSelection(at point: CGPoint) {
        guard state != .editing else { return }
        startPoint = point
        currentPoint = point
        selectionRect = .zero
        state = .selecting
    }
    
    func updateSelection(to point: CGPoint) {
        guard state == .selecting, let start = startPoint else { return }
        currentPoint = point
        selectionRect = CGRect(from: start, to: point)
    }
    
    func endSelection() {
        guard state == .selecting else { return }
        selectionRect = selectionRect.standardized
        
        // If selection is too small, cancel/reset
        if selectionRect.width < 10 || selectionRect.height < 10 {
            reset()
        } else {
            state = .editing
        }
    }
    
    // MARK: - Annotation Logic
    
    func startDrawing(at point: CGPoint) {
        guard state == .editing, let tool = selectedTool else { return }
        
        var annotation = Annotation(type: tool, color: selectedColor)
        annotation.startPoint = point
        annotation.endPoint = point
        if tool == .pen {
            annotation.points = [point]
        }
        currentAnnotation = annotation
    }
    
    func updateDrawing(to point: CGPoint) {
        guard state == .editing, var annotation = currentAnnotation else { return }
        
        annotation.endPoint = point
        if annotation.type == .pen {
            annotation.points.append(point)
        }
        currentAnnotation = annotation
    }
    
    func endDrawing() {
        guard let annotation = currentAnnotation else { return }
        annotations.append(annotation)
        currentAnnotation = nil
    }
    
    func undoLastAnnotation() {
        if !annotations.isEmpty {
            annotations.removeLast()
        }
    }
    
    func reset() {
        startPoint = nil
        currentPoint = nil
        selectionRect = .zero
        state = .idle
        annotations = []
        currentAnnotation = nil
        selectedTool = nil
    }
}


extension CGRect {
    init(from: CGPoint, to: CGPoint) {
        let x = min(from.x, to.x)
        let y = min(from.y, to.y)
        let width = abs(to.x - from.x)
        let height = abs(to.y - from.y)
        self.init(x: x, y: y, width: width, height: height)
    }
}
