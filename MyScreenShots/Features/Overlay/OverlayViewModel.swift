import Foundation
import Combine
import CoreGraphics
import SwiftUI
import AppKit

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

enum SelectionHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
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
    @Published var activeSelectionHandle: SelectionHandle?
    @Published var isMovingSelection: Bool = false
    @Published var previewImage: CGImage?
    var previewBitmap: NSBitmapImageRep?
    
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

    func updatePreviewImage(_ image: CGImage?) {
        previewImage = image
        if let image {
            previewBitmap = makePreviewBitmap(from: image, maxDimension: 1200)
        } else {
            previewBitmap = nil
        }
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
    
    func annotationID(at point: CGPoint) -> UUID? {
        hitTest(at: point)
    }
    
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
        if (tool == .mosaic || tool == .blur), !selectionRect.contains(point) {
            return
        }
        
        // Start new annotation
        var annotation = Annotation(type: tool, color: selectedColor)
        let startPoint = (tool == .mosaic || tool == .blur) ? clampPoint(point, to: selectionRect) : point
        annotation.startPoint = startPoint
        annotation.endPoint = startPoint
        if tool == .pen || tool == .blur {
            annotation.points = [startPoint]
        }
        if tool == .mosaic || tool == .blur {
            annotation.lineWidth = 24
        }
        currentAnnotation = annotation
        
        // Deselect any existing annotation when drawing new one
        selectedAnnotationID = nil
    }
    
    func updateDrawing(to point: CGPoint) {
        // If moving an existing annotation
        if selectedTool == nil, let id = selectedAnnotationID, annotations.contains(where: { $0.id == id }) {
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
        
        let nextPoint = (annotation.type == .mosaic || annotation.type == .blur) ? clampPoint(point, to: selectionRect) : point
        annotation.endPoint = nextPoint
        if annotation.type == .pen || annotation.type == .blur {
            annotation.points.append(nextPoint)
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
        
        if annotation.type == .pen || annotation.type == .mosaic || annotation.type == .blur {
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
        activeSelectionHandle = nil
        isMovingSelection = false
        previewImage = nil
        previewBitmap = nil
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
            
        case .mosaic, .blur, .pen, .arrow:
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

    private func clampPoint(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return CGPoint(x: x, y: y)
    }

    private func makePreviewBitmap(from image: CGImage, maxDimension: CGFloat) -> NSBitmapImageRep? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        if width <= 0 || height <= 0 {
            return nil
        }
        let scale = min(maxDimension / max(width, height), 1)
        let targetWidth = Int(width * scale)
        let targetHeight = Int(height * scale)
        if targetWidth <= 0 || targetHeight <= 0 {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: targetWidth, height: targetHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)))
        guard let scaled = context.makeImage() else {
            return nil
        }
        return NSBitmapImageRep(cgImage: scaled)
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

    func beginMoveSelection(at point: CGPoint) {
        guard state == .editing, selectionRect != .zero else { return }
        isMovingSelection = true
        selectionDragStartPoint = point
        selectionDragStartRect = selectionRect
    }

    func updateMoveSelection(to point: CGPoint, within bounds: CGRect) {
        guard isMovingSelection else { return }
        let deltaX = point.x - selectionDragStartPoint.x
        let deltaY = point.y - selectionDragStartPoint.y
        let maxX = max(bounds.width - selectionDragStartRect.width, 0)
        let maxY = max(bounds.height - selectionDragStartRect.height, 0)
        let newX = min(max(selectionDragStartRect.minX + deltaX, 0), maxX)
        let newY = min(max(selectionDragStartRect.minY + deltaY, 0), maxY)
        let newRect = CGRect(x: newX, y: newY, width: selectionDragStartRect.width, height: selectionDragStartRect.height)
        let offset = CGSize(width: newRect.minX - selectionRect.minX, height: newRect.minY - selectionRect.minY)
        selectionRect = newRect
        moveAllAnnotations(offset: offset)
        moveEditingTextPosition(offset: offset)
    }

    func endMoveSelection() {
        isMovingSelection = false
    }

    func beginResizeSelection(handle: SelectionHandle, at point: CGPoint) {
        guard state == .editing, selectionRect != .zero else { return }
        activeSelectionHandle = handle
        selectionDragStartPoint = point
        selectionDragStartRect = selectionRect
    }

    func updateResizeSelection(to point: CGPoint, within bounds: CGRect) {
        guard let handle = activeSelectionHandle else { return }
        let deltaX = point.x - selectionDragStartPoint.x
        let deltaY = point.y - selectionDragStartPoint.y
        let minSize: CGFloat = 20
        var minX = selectionDragStartRect.minX
        var maxX = selectionDragStartRect.maxX
        var minY = selectionDragStartRect.minY
        var maxY = selectionDragStartRect.maxY

        switch handle {
        case .topLeft:
            minX += deltaX
            minY += deltaY
        case .top:
            minY += deltaY
        case .topRight:
            maxX += deltaX
            minY += deltaY
        case .right:
            maxX += deltaX
        case .bottomRight:
            maxX += deltaX
            maxY += deltaY
        case .bottom:
            maxY += deltaY
        case .bottomLeft:
            minX += deltaX
            maxY += deltaY
        case .left:
            minX += deltaX
        }

        minX = max(minX, 0)
        minY = max(minY, 0)
        maxX = min(maxX, bounds.width)
        maxY = min(maxY, bounds.height)

        if maxX - minX < minSize {
            if handle == .left || handle == .topLeft || handle == .bottomLeft {
                minX = max(maxX - minSize, 0)
            } else if handle == .right || handle == .topRight || handle == .bottomRight {
                maxX = min(minX + minSize, bounds.width)
            } else {
                maxX = min(minX + minSize, bounds.width)
            }
        }

        if maxY - minY < minSize {
            if handle == .top || handle == .topLeft || handle == .topRight {
                minY = max(maxY - minSize, 0)
            } else if handle == .bottom || handle == .bottomLeft || handle == .bottomRight {
                maxY = min(minY + minSize, bounds.height)
            } else {
                maxY = min(minY + minSize, bounds.height)
            }
        }

        selectionRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func endResizeSelection() {
        activeSelectionHandle = nil
    }

    var isManipulatingSelection: Bool {
        isMovingSelection || activeSelectionHandle != nil
    }

    private var selectionDragStartRect: CGRect = .zero
    private var selectionDragStartPoint: CGPoint = .zero

    private func moveAllAnnotations(offset: CGSize) {
        guard offset.width != 0 || offset.height != 0 else { return }
        annotations = annotations.map { annotation in
            var updated = annotation
            updated.startPoint.x += offset.width
            updated.startPoint.y += offset.height
            updated.endPoint.x += offset.width
            updated.endPoint.y += offset.height
            if updated.type == .pen || updated.type == .mosaic || updated.type == .blur {
                updated.points = updated.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
            }
            return updated
        }
        if var current = currentAnnotation {
            current.startPoint.x += offset.width
            current.startPoint.y += offset.height
            current.endPoint.x += offset.width
            current.endPoint.y += offset.height
            if current.type == .pen || current.type == .mosaic || current.type == .blur {
                current.points = current.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
            }
            currentAnnotation = current
        }
    }

    private func moveEditingTextPosition(offset: CGSize) {
        guard offset.width != 0 || offset.height != 0 else { return }
        if isEditingText {
            editingTextPosition = CGPoint(x: editingTextPosition.x + offset.width, y: editingTextPosition.y + offset.height)
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
