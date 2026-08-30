import Foundation
import Combine
import CoreGraphics
import SwiftUI
import AppKit

enum OverlayState {
    case idle
    case selecting
    case editing
    case longCaptureReady
    case longCapturing
}

enum CaptureAction {
    case copy
    case save
    case saveAs
    case pin
    case ocr
}

enum CaptureMode: Equatable {
    case normal
    case longScreenshot
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
    @Published var selectedFontSize: CGFloat = Annotation.textInputFontSize
    @Published var activeSelectionHandle: SelectionHandle?
    @Published var isMovingSelection: Bool = false
    @Published var previewImage: CGImage?
    @Published var previewScale: CGFloat = 1.0
    var previewBitmap: NSBitmapImageRep?
    @Published var captureMode: CaptureMode = .normal
    @Published var longCaptureStatusText: String = "拖动选择滚动区域"
    
    // Actions
    var onCapture: ((CGRect, [Annotation], CaptureAction, CGImage?) -> Void)?
    var onCancel: (() -> Void)?
    var onLongCaptureStart: ((CGRect) -> Void)?
    
    // MARK: - Finalize
    
    func confirmCopy() {
        onCapture?(selectionRect, annotations, .copy, previewImage)
    }
    
    func confirmSave() {
        onCapture?(selectionRect, annotations, .save, previewImage)
    }
    
    func confirmPin() {
        onCapture?(selectionRect, annotations, .pin, previewImage)
    }

    func confirmOCR() {
        onCapture?(selectionRect, annotations, .ocr, previewImage)
    }

    func confirmSaveAs() {
        onCapture?(selectionRect, annotations, .saveAs, previewImage)
    }
    
    func cancel() {
        onCancel?()
    }

    func confirmLongCaptureRegion() {
        state = .longCapturing
        longCaptureStatusText = "滚动目标区域，按回车完成，按 Esc 取消"
        onLongCaptureStart?(selectionRect)
    }
    
    func startLongCaptureFromToolbar() {
        guard state == .editing, captureMode == .normal, !selectionRect.isEmpty else { return }
        
        annotations = []
        currentAnnotation = nil
        selectedTool = nil
        selectedAnnotationID = nil
        cancelTextInput()
        
        confirmLongCaptureRegion()
    }

    func updatePreviewImage(_ image: CGImage?, scale: CGFloat = 1.0) {
        previewImage = image
        previewScale = scale
        if let image {
            previewBitmap = makePreviewBitmap(from: image, maxDimension: 1200)
        } else {
            previewBitmap = nil
        }
    }
    
    // MARK: - Selection Logic
    
    func startSelection(at point: CGPoint) {
        guard state != .editing, state != .longCaptureReady, state != .longCapturing else { return }
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
        // 清除选区拖拽残留的 currentPoint/startPoint，
        // 否则后续拖动标注时会把旧坐标当成「上一次位置」算出巨大偏移，导致文字跳飞
        currentPoint = nil
        startPoint = nil

        // If selection is too small, cancel/reset
        if selectionRect.width < 10 || selectionRect.height < 10 {
            reset()
        } else {
            if captureMode == .longScreenshot {
                confirmLongCaptureRegion()
            } else {
                state = .editing
                // 进入编辑态默认选中矩形框（许愿功能 1）
                selectedTool = .rectangle
            }
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
                }
                // 双击文字标注 → 重新编辑
                if let annotation = annotations.first(where: { $0.id == id }),
                   annotation.type == .text {
                    if lastTextTapAnnotationID == id,
                       let last = lastTextTapDate,
                       Date().timeIntervalSince(last) < 0.35 {
                        startTextEdit(annotationID: id)
                        lastTextTapAnnotationID = nil
                        lastTextTapDate = nil
                    } else {
                        lastTextTapAnnotationID = id
                        lastTextTapDate = Date()
                    }
                } else {
                    lastTextTapAnnotationID = nil
                    lastTextTapDate = nil
                }
            } else {
                selectedAnnotationID = nil
                lastTextTapAnnotationID = nil
                lastTextTapDate = nil
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
        nextNumber = 1
        lastTextTapAnnotationID = nil
        lastTextTapDate = nil
        activeSelectionHandle = nil
        isMovingSelection = false
        isResizingText = false
        previewImage = nil
        previewScale = 1.0
        previewBitmap = nil
        captureMode = .normal
        longCaptureStatusText = "拖动选择滚动区域"
    }
    
    // MARK: - Text Input State
    @Published var isEditingText: Bool = false
    @Published var editingTextPosition: CGPoint = .zero
    @Published var editingTextContent: String = ""
    private(set) var editingTextAnnotationID: UUID?
    private var lastTextTapAnnotationID: UUID?
    private var lastTextTapDate: Date?

    /// 文字编辑器当前尺寸（由视图上报，随内容自动增长，用于定位与外部点击判定）
    @Published var editingTextSize: CGSize = CGSize(width: 120, height: 34)

    /// 当前文字编辑器的 frame（左上角对齐点击位置）
    var editingTextEditorFrame: CGRect {
        CGRect(origin: editingTextPosition, size: editingTextSize)
    }

    func startTextInput(at point: CGPoint) {
        guard state == .editing, selectedTool == .text else { return }

        // Restriction: Input must be inside selection rect
        if !selectionRect.contains(point) {
             return
        }

        isEditingText = true
        editingTextPosition = point
        editingTextContent = ""
        editingTextAnnotationID = nil
        selectedAnnotationID = nil
    }

    /// 重新编辑已有文字标注
    func startTextEdit(annotationID: UUID) {
        guard state == .editing,
              let annotation = annotations.first(where: { $0.id == annotationID }),
              annotation.type == .text else { return }

        isEditingText = true
        editingTextPosition = annotation.startPoint
        editingTextContent = annotation.text
        editingTextAnnotationID = annotationID
        selectedAnnotationID = annotationID
    }
    
    func commitTextInput() {
        guard isEditingText else { return }

        if let editingID = editingTextAnnotationID,
           let index = annotations.firstIndex(where: { $0.id == editingID }) {
            // 编辑已有文字：更新内容与位置；清空则删除
            if editingTextContent.isEmpty {
                annotations.remove(at: index)
            } else {
                annotations[index].text = editingTextContent
                annotations[index].startPoint = editingTextPosition
            }
        } else if !editingTextContent.isEmpty {
            // 新增文字
            var annotation = Annotation(type: .text, color: selectedColor)
            annotation.startPoint = editingTextPosition
            annotation.text = editingTextContent
            annotation.fontSize = selectedFontSize
            annotations.append(annotation)
        }

        isEditingText = false
        editingTextContent = ""
        editingTextAnnotationID = nil
        // 提交后回到选择模式（不自动选中，避免出现多余蓝框）；可直接拖拽或双击编辑
        selectedAnnotationID = nil
        selectedTool = nil
    }
    
    func cancelTextInput() {
        isEditingText = false
        editingTextContent = ""
        editingTextAnnotationID = nil
    }

    /// 切换标注工具。切离文字工具时取消未完成的文字输入（连带 bug 1）。
    func selectTool(_ tool: AnnotationType?) {
        selectedTool = tool
        if tool != .text {
            cancelTextInput()
        }
    }

    // MARK: - Number Annotation
    private var nextNumber = 1

    func placeNumber(at point: CGPoint) {
        guard state == .editing, selectedTool == .number else { return }
        guard selectionRect.contains(point) else { return }

        var annotation = Annotation(type: .number, color: selectedColor)
        annotation.startPoint = point
        annotation.text = String(nextNumber)
        annotation.fontSize = Annotation.numberFontSize
        annotations.append(annotation)
        nextNumber += 1
        selectedAnnotationID = nil
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
        case .rectangle, .ellipse, .text, .number:
            var rect: CGRect
            if annotation.type == .text {
                 rect = annotation.textBoundingRect
            } else if annotation.type == .number {
                 let radius = annotation.fontSize / 2 + 4
                 rect = CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2)
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

    /// 设置当前颜色：更新 selectedColor，并立即重染选中的标注（若有）
    func setColor(_ color: Color) {
        selectedColor = color
        updateSelectedStyle(color: color)
    }

    /// 设置字号：更新 selectedFontSize，并立即应用到选中的文字标注（若有）
    func setFontSize(_ size: CGFloat) {
        selectedFontSize = size
        updateSelectedStyle(fontSize: size)
    }

    // MARK: - Text Resize（拖拽角标缩放字号）
    @Published var isResizingText: Bool = false
    private var textResizeAnchor: CGPoint = .zero
    private var textResizeStartFontSize: CGFloat = 24
    private var textResizeStartDiag: CGFloat = 1

    /// 选中文字标注的右下角缩放手柄位置（无选中/非文字返回 nil）
    var selectedTextResizeHandle: CGPoint? {
        guard let id = selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == id }),
              annotation.type == .text else { return nil }
        let rect = annotation.textBoundingRect
        return CGPoint(x: rect.maxX, y: rect.maxY)
    }

    func beginTextResize(at point: CGPoint) {
        guard let id = selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == id }),
              annotation.type == .text else { return }
        isResizingText = true
        textResizeAnchor = annotation.startPoint
        textResizeStartFontSize = annotation.fontSize
        let size = annotation.textBoundingSize
        textResizeStartDiag = max(hypot(size.width, size.height), 1)
    }

    func updateTextResize(to point: CGPoint) {
        guard isResizingText, let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let diag = hypot(point.x - textResizeAnchor.x, point.y - textResizeAnchor.y)
        let scale = diag / max(textResizeStartDiag, 1)
        let newSize = min(max(textResizeStartFontSize * scale, 8), 96)
        annotations[index].fontSize = newSize
        selectedFontSize = newSize
    }

    func endTextResize() {
        isResizingText = false
    }

    func beginMoveSelection(at point: CGPoint) {
        guard (state == .editing || state == .longCaptureReady), selectionRect != .zero else { return }
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
        guard (state == .editing || state == .longCaptureReady), selectionRect != .zero else { return }
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
