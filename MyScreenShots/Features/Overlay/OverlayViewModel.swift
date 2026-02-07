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
    case pin
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
    
    func confirmPin() {
        onCapture?(selectionRect, annotations, .pin)
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
    
    // MARK: - Annotation Logic
    
    @Published var selectedAnnotationID: UUID?
    
    func startDrawing(at point: CGPoint) {
        // If no tool selected, try to select an annotation
        if selectedTool == nil {
            if let id = hitTest(at: point) {
                selectedAnnotationID = id
                // Update selected properties to match annotation
                if let annotation = annotations.first(where: { $0.id == id }) {
                    selectedColor = annotation.color
                    // You might want to update a FontSize publisher here too if you had one
                }
            } else {
                selectedAnnotationID = nil
            }
            return
        }
        
        guard state == .editing, let tool = selectedTool else { return }
        
        // Start new annotation
        var annotation = Annotation(type: tool, color: selectedColor)
        annotation.startPoint = point
        annotation.endPoint = point
        if tool == .pen {
            annotation.points = [point]
        }
        currentAnnotation = annotation
        
        // Deselect any existing annotation when drawing new one
        selectedAnnotationID = nil
    }
    
    func updateDrawing(to point: CGPoint) {
        // If moving an existing annotation
        if selectedTool == nil, let id = selectedAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) {
            let start = startPoint ?? point // Should have been set in startSelection/Drawing? 
            // Wait, for move we need a reference point. 
            // Let's use currentPoint as 'previous' and point as 'new'
            
            // NOTE: This simple drag logic relies on the View calling updateDrawing continuously
            // We need 'startPoint' of the drag, or delta.
            // Let's assume the View calculates delta or we track 'currentPoint' as last position.
            
            // Actually, better to have a dedicated move function or handle it here.
            // Let's rely on `currentPoint` being the *previous* drag location in this context?
            // No, `currentPoint` is currently used for Selection Rect.
            
            // Let's use `editingTextPosition` as temporary storage for drag start? No, dirty.
            // Let's just calculate delta from the previous point passed to this function?
            // The View's DragGesture gives us `value.translation`.
            
            return // Actual move logic will be in `moveSelectedAnnotation(by:)`
        }
        
        guard state == .editing, var annotation = currentAnnotation else { return }
        
        annotation.endPoint = point
        if annotation.type == .pen {
            annotation.points.append(point)
        }
        currentAnnotation = annotation
    }
    
    func moveSelectedAnnotation(offset: CGSize) {
        guard let id = selectedAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var annotation = annotations[index]
        
        annotation.startPoint.x += offset.width
        annotation.startPoint.y += offset.height
        annotation.endPoint.x += offset.width
        annotation.endPoint.y += offset.height
        
        if annotation.type == .pen {
            annotation.points = annotation.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
        
        annotations[index] = annotation
    }
    
    func endDrawing() {
        if let annotation = currentAnnotation {
            annotations.append(annotation)
            currentAnnotation = nil
        }
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
        selectedAnnotationID = nil
        cancelTextInput()
    }
    
    // MARK: - Text Input State
    @Published var isEditingText: Bool = false
    @Published var editingTextPosition: CGPoint = .zero
    @Published var editingTextContent: String = ""
    
    func startTextInput(at point: CGPoint) {
        guard state == .editing, selectedTool == .text else { return }
        
        // Restriction: Input must be inside selection rect
        if !selectionRect.contains(point) {
             return
        }
        
        isEditingText = true
        editingTextPosition = point
        editingTextContent = ""
        selectedAnnotationID = nil 
    }
    
    func commitTextInput() {
        guard isEditingText else { return }
        
        if !editingTextContent.isEmpty {
            var annotation = Annotation(type: .text, color: selectedColor)
            annotation.startPoint = editingTextPosition
            annotation.text = editingTextContent
            annotation.fontSize = 24.0 // Default font size
            annotations.append(annotation)
        }
        
        isEditingText = false
        editingTextContent = ""
        // Optional: Deselect tool after text entry? 
        // selectedTool = nil 
    }
    
    func cancelTextInput() {
        isEditingText = false
        editingTextContent = ""
    }
    
    // MARK: - Hit Testing
    private func hitTest(at point: CGPoint) -> UUID? {
        // Iterate in reverse to select top-most
        for annotation in annotations.reversed() {
            if isPoint(point, in: annotation) {
                return annotation.id
            }
        }
        return nil
    }
    
    private func isPoint(_ point: CGPoint, in annotation: Annotation) -> Bool {
        let padding: CGFloat = 10.0
        switch annotation.type {
        case .rectangle, .ellipse, .text:
            var rect: CGRect
            if annotation.type == .text {
                 // Est text size since we don't have font metrics here easily without NSFont
                 // Simple approximation: length * fontSize * 0.6
                 let width = CGFloat(annotation.text.count) * annotation.fontSize * 0.6
                 let height = annotation.fontSize * 1.5
                 rect = CGRect(x: annotation.startPoint.x, y: annotation.startPoint.y, width: width, height: height)
            } else {
                 rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
            }
            return rect.insetBy(dx: -padding, dy: -padding).contains(point)
            
        case .pen, .arrow:
             // Simple bounding box check for now
             // Ideal: path hit testing
             let xs = annotation.points.map { $0.x } + [annotation.startPoint.x, annotation.endPoint.x]
             let ys = annotation.points.map { $0.y } + [annotation.startPoint.y, annotation.endPoint.y]
             
             guard let minX = xs.min(), let maxX = xs.max(),
                   let minY = ys.min(), let maxY = ys.max() else { return false }
             
             let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
             return rect.insetBy(dx: -padding, dy: -padding).contains(point)
        }
    }
    
    // MARK: - Style Updates
    func updateSelectedStyle(color: Color? = nil, fontSize: CGFloat? = nil) {
        guard let id = selectedAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        
        if let color = color {
            annotations[index].color = color
        }
        if let fontSize = fontSize, annotations[index].type == .text {
            annotations[index].fontSize = fontSize
        }
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
