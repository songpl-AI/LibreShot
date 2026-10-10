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
    case saveAndCopy
    case translate
    case pin
    case ocr
}

enum CaptureMode: Equatable {
    case normal
    case longScreenshot
    case imageEditor
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

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

class OverlayViewModel: ObservableObject {
    // Selection State
    @Published var startPoint: CGPoint?
    @Published var currentPoint: CGPoint?
    @Published var selectionRect: CGRect = .zero {
        didSet { if selectionRect != oldValue { clearImageTranslation(); scheduleEffectPreview() } }
    }
    @Published var state: OverlayState = .idle
    
    // Freeze visibility for the current capture session.
    @Published private(set) var toolbarConfiguration: ToolbarConfiguration
    private let settings: SettingsService
    @Published private(set) var useRoundedCorners: Bool

    var selectionCornerRadius: CGFloat {
        useRoundedCorners && captureMode != .longScreenshot ? min(16, selectionRect.width / 2, selectionRect.height / 2) : 0
    }

    init(settings: SettingsService = .shared) {
        self.settings = settings
        self.toolbarConfiguration = settings.toolbarConfiguration
        self.useRoundedCorners = settings.useRoundedCorners
        self.selectedNumberStyle = settings.numberAnnotationStyle
    }

    var visibleToolbarItems: [ToolbarItem] {
        toolbarConfiguration.visibleItems.filter { $0 != .longCapture || captureMode == .normal }
    }

    // Editor State
    @Published var selectedTool: AnnotationType? {
        didSet { if let tool = selectedTool, tool != oldValue { loadToolDefaults(for: tool) } }
    }
    @Published var annotations: [Annotation] = [] { didSet { scheduleEffectPreview() } }
    @Published var currentAnnotation: Annotation? { didSet { scheduleEffectPreview() } }
    private var pendingDrawing: Annotation?
    var hasDrawingGesture: Bool { currentAnnotation != nil || pendingDrawing != nil }
    private indirect enum AnnotationUndo {
        case numbered(AnnotationUndo, Int, UUID?, CGFloat, Color, NumberAnnotationStyle)
        case effect(AnnotationUndo, CGFloat, CGFloat, CGFloat)
        case remove(UUID)
        case restore(Annotation, Int)
    }
    private var annotationUndo: [AnnotationUndo] = []
    @Published var selectedColor: Color = .red
    @Published var selectedNumberStyle: NumberAnnotationStyle = .filled
    @Published var selectedNumberFontSize: CGFloat = Annotation.numberFontSize
    @Published var selectedFontSize: CGFloat = Annotation.textInputFontSize
    @Published var activeSelectionHandle: SelectionHandle?
    @Published var isMovingSelection: Bool = false
    @Published var previewImage: CGImage? { didSet { scheduleEffectPreview() } }
    @Published var previewScale: CGFloat = 1.0 { didSet { scheduleEffectPreview() } }
    @Published var captureMode: CaptureMode = .normal
    @Published var longCaptureStatusText: String = "拖动选择滚动区域"
    @Published var showsStylePopover = false
    @Published private(set) var translationSource: NSImage?
    @Published private(set) var translationSessionID = UUID()
    @Published var translatedSelection: CGImage? { didSet { scheduleEffectPreview() } }
    @Published var showsOriginalTranslation = false { didSet { scheduleEffectPreview() } }
    @Published var translationCanExport = false
    @Published var showsTranslationControls = false

    var canExportSelection: Bool { translationSource == nil || translationCanExport }

    func clearImageTranslation() {
        #if DEBUG
        let hadTranslation = translationSource != nil || translatedSelection != nil
        #endif
        translationSource = nil
        translatedSelection = nil
        translationCanExport = false
        showsOriginalTranslation = false
        showsTranslationControls = false
        translationSessionID = UUID()
        #if DEBUG
        if hadTranslation { MemoryTrace.markAfterRelease("inline_translation_cleared") }
        #endif
    }

    func imageForExport() -> CGImage? {
        guard let original = previewImage, translationSource != nil,
              !showsOriginalTranslation, let translated = translatedSelection else { return previewImage }
        return ImageTranslationRenderer.replacingSelection(in: original, with: translated,
                                                           selection: selectionRect, scale: previewScale)
    }

    func isToolbarItemEnabled(_ item: ToolbarItem) -> Bool {
        if [.complete, .save, .saveAs, .pin, .ocr].contains(item), !canExportSelection { return false }
        if item == .style { return visibleToolbarItems.contains(.style) }
        if item == .translate {
            if #available(macOS 26.0, *) { return true }
            return false
        }
        if item == .undo { return !annotations.isEmpty || !annotationUndo.isEmpty }
        if item == .longCapture { return captureMode == .normal && annotations.isEmpty && !isEditingText && translationSource == nil }
        return true
    }

    func performToolbarItem(_ item: ToolbarItem) {
        guard isToolbarItemEnabled(item) else { return }
        if let tool = item.annotationType {
            selectTool(selectedTool == tool ? nil : tool)
            return
        }
        switch item {
        case .select: selectTool(nil)
        case .style: showsStylePopover.toggle()
        case .undo: undoLastAnnotation()
        case .cancel: cancel()
        case .pin: confirmPin()
        case .ocr: confirmOCR()
        case .translate: confirmImageTranslation()
        case .longCapture: startLongCaptureFromToolbar()
        case .complete: confirmCopy()
        case .save: confirmSave()
        case .saveAs: confirmSaveAs()
        default: break
        }
    }

    func performEditorShortcut(_ event: NSEvent, textResponder: Bool = false) -> Bool {
        guard state == .editing, !selectionRect.isEmpty, event.type == .keyDown else { return false }
        if isEditingNumber, event.keyCode == 53 {
            cancelTextInput(); return true
        }
        if isEditingNumber, [36, 76].contains(event.keyCode),
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            commitTextInput(); return true
        }
        let editing = isEditingText || textResponder
        let modifiers = ShortcutUtils.carbonModifiers(from: event.modifierFlags)
        if [51, 117].contains(event.keyCode), modifiers == 0, !editing, !showsStylePopover {
            guard selectedAnnotationID != nil else { return false }
            if !event.isARepeat { return deleteSelectedAnnotation() }
            return true
        }
        if event.keyCode == 49, modifiers == 0, !editing, !showsStylePopover {
            guard settings.editorSpaceAction != .disabled else { return false }
            if !event.isARepeat {
                if settings.editorSpaceAction == .complete { confirmCopy() }
                else { confirmSaveAndCopy() }
            }
            return true
        }
        guard let item = ToolbarItem.allCases.first(where: { settings.editorShortcuts[$0.rawValue]?.matches(event) == true }) else { return false }
        // Only save commands can commit active text. Letters, Return and undo belong to the text editor.
        if editing || showsStylePopover {
            guard (item == .save || item == .saveAs), event.modifierFlags.contains(.command) else { return false }
        }
        guard isToolbarItemEnabled(item) else { return false }
        if !event.isARepeat { performToolbarItem(item) }
        return true
    }

    func shortcutTitle(for item: ToolbarItem) -> String? {
        item == .cancel ? "Esc" : settings.editorShortcuts[item.rawValue]?.title
    }
    
    // Actions
    var onCapture: ((CGRect, [Annotation], CaptureAction, CGImage?) -> Void)?
    var onCancel: (() -> Void)?
    var onLongCaptureStart: ((CGRect) -> Void)?
    
    // MARK: - Finalize

    private var confirmationClick: (point: CGPoint, annotations: [Annotation], undoCount: Int)?

    func canConfirmDoubleClick(at point: CGPoint) -> Bool {
        settings.doubleClickCompletesCapture && state == .editing
            && !selectionRect.isEmpty && selectionRect.contains(point) && !showsStylePopover
    }

    /// Observe the first click without delaying drawing or text input. Only the
    /// number tool creates a valid annotation on a stationary first click.
    func beginConfirmationClick(at point: CGPoint) {
        confirmationClick = canConfirmDoubleClick(at: point) && selectedTool == .number && !isEditingText
            ? (point, annotations, annotationUndo.count) : nil
    }

    func endConfirmationClick(at point: CGPoint) {
        if let click = confirmationClick, hypot(point.x - click.point.x, point.y - click.point.y) >= 5 {
            confirmationClick = nil
        }
    }

    @discardableResult
    func confirmDoubleClick(at point: CGPoint) -> Bool {
        guard canConfirmDoubleClick(at: point) else { return false }
        if let click = confirmationClick, hypot(point.x - click.point.x, point.y - click.point.y) < 5,
           annotations.count == click.annotations.count + 1,
           Array(annotations.dropLast()) == click.annotations,
           annotations.last?.type == .number, annotationUndo.count == click.undoCount + 1 {
            undoLastAnnotation()
        }
        confirmationClick = nil
        // Confirmation wins over text selection/editing and every drawing tool.
        currentAnnotation = nil
        pendingDrawing = nil
        clearAnnotationPress()
        confirmCopy()
        return true
    }
    
    func confirmCopy() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .copy, imageForExport())
    }
    
    func confirmSave() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .save, imageForExport())
    }

    func confirmSaveAndCopy() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .saveAndCopy, imageForExport())
    }
    
    func confirmPin() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .pin, imageForExport())
    }

    func confirmOCR() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .ocr, imageForExport())
    }

    func confirmImageTranslation() {
        commitTextInput()
        guard !isEditingText else { return }
        if translationSource != nil { showsTranslationControls.toggle(); return }
        guard #available(macOS 26.0, *), let image = previewImage,
              !selectionRect.isEmpty, previewScale > 0 else { return }
        let pixels = CGRect(x: selectionRect.minX * previewScale, y: selectionRect.minY * previewScale,
                            width: selectionRect.width * previewScale, height: selectionRect.height * previewScale).integral
        guard let crop = image.cropping(to: pixels) else { return }
        translationSessionID = UUID()
        translationSource = NSImage(cgImage: crop, size: selectionRect.size)
        #if DEBUG
        MemoryTrace.mark("inline_translation_source_ready")
        #endif
        showsTranslationControls = true
        selectedTool = nil
        selectedAnnotationID = nil
    }

    func canToggleTranslationPreview(from start: CGPoint, to end: CGPoint) -> Bool {
        guard state == .editing, translationSource != nil, translatedSelection != nil,
              selectedTool == nil, !isEditingText,
              abs(end.x - start.x) < 5, abs(end.y - start.y) < 5,
              selectionRect.insetBy(dx: min(8, selectionRect.width / 4),
                                    dy: min(8, selectionRect.height / 4)).contains(start),
              annotationID(at: start) == nil else { return false }
        return true
    }

    func toggleTranslationPreview() {
        showsOriginalTranslation.toggle()
    }

    func confirmSaveAs() {
        guard canExportSelection else { return }
        commitTextInput()
        guard !isEditingText else { return }
        onCapture?(selectionRect, annotations, .saveAs, imageForExport())
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
        annotationUndo = []
        pendingDrawing = nil
        currentAnnotation = nil
        selectedTool = nil
        selectedAnnotationID = nil
        cancelTextInput()
        
        confirmLongCaptureRegion()
    }

    func updatePreviewImage(_ image: CGImage?, scale: CGFloat = 1.0) {
        previewImage = image
        previewScale = scale
    }

    @Published private(set) var effectPreview: CGImage?
    @Published private(set) var effectPreviewRect: CGRect = .zero
    @Published var selectedMosaicBlockSize: CGFloat = 16
    @Published var selectedEffectBrushWidth: CGFloat = 20
    @Published var selectedBlurRadius: CGFloat = 12
    private let effectQueue = DispatchQueue(label: "LibreShot.effects", qos: .userInitiated)
    @Published var selectedMosaicMode: EffectDrawingMode = .rectangle
    @Published var selectedBlurMode: EffectDrawingMode = .brush
    private var effectRendering = false
    private var pendingEffectRender: (UUID, () -> (CGImage?, CGRect))?
    private var effectGeneration = UUID()
    private weak var effectSource: CGImage?
    private var effectAnnotations: [Annotation] = []
    private var effectSelection: CGRect = .zero
    private var effectScale: CGFloat = 1

    var activeEffectTool: AnnotationType? {
        if let a = annotations.first(where: { $0.id == selectedAnnotationID }), a.type == .mosaic || a.type == .blur { return a.type }
        return selectedTool == .mosaic || selectedTool == .blur ? selectedTool : nil
    }

    var isDrawingEffectBrush: Bool {
        guard let tool = selectedTool, tool == .mosaic || tool == .blur else { return false }
        return effectDrawingMode(for: tool) == .brush
    }

    func effectDrawingMode(for tool: AnnotationType) -> EffectDrawingMode {
        if let annotation = annotations.first(where: { $0.id == selectedAnnotationID }), annotation.type == tool {
            return annotation.isEffectBrush ? .brush : .rectangle
        }
        return tool == .mosaic ? selectedMosaicMode : selectedBlurMode
    }

    func setEffectDrawingMode(_ mode: EffectDrawingMode, for tool: AnnotationType) {
        guard tool == .mosaic || tool == .blur else { return }
        selectedAnnotationID = nil
        selectedTool = tool
        var style = settings.annotationStyle(for: tool)
        style.effectMode = mode
        settings.setAnnotationStyle(style, for: tool)
        loadToolDefaults(for: tool)
    }

    func setEffectValue(_ value: CGFloat, parameter: String) {
        changeToolStyle { style in
            switch parameter {
            case "block": style.blockSize = value
            case "width": style.brushWidth = value
            default: style.blurRadius = value
            }
        }
    }

    func effectValue(_ parameter: String) -> CGFloat {
        let style = currentToolStyle
        switch parameter {
        case "block": return style.blockSize
        case "width": return style.brushWidth
        default: return style.blurRadius
        }
    }

    private func scheduleEffectPreview() {
        let effects = (annotations + (currentAnnotation.map { [$0] } ?? [])).filter { $0.type == .mosaic || $0.type == .blur }
        guard !effects.isEmpty, let source = imageForExport(), previewScale > 0, !selectionRect.isEmpty else {
            pendingEffectRender = nil; effectGeneration = UUID()
            effectSource = nil; effectAnnotations = []
            effectPreview = nil; effectPreviewRect = .zero; return
        }
        guard effects != effectAnnotations || source !== effectSource || selectionRect != effectSelection || previewScale != effectScale else { return }
        // A new source/crop invalidates old frames. Pointer updates do not: while
        // rendering, retain the newest request and publish intermediate frames.
        if source !== effectSource || selectionRect != effectSelection || previewScale != effectScale {
            effectGeneration = UUID()
            effectPreview = nil; effectPreviewRect = .zero
        }
        effectSource = source; effectAnnotations = effects; effectSelection = selectionRect; effectScale = previewScale
        let generation = effectGeneration
        let rect = selectionRect, scale = previewScale
        let union = effects.reduce(CGRect.null) { $0.union($1.selectionBounds) }.intersection(rect)
        guard !union.isEmpty else { pendingEffectRender = nil; effectGeneration = UUID(); effectPreview = nil; effectPreviewRect = .zero; return }
        let localPixels = CGRect(x: (union.minX - rect.minX) * scale,
                                 y: (rect.maxY - union.maxY) * scale,
                                 width: union.width * scale, height: union.height * scale).integral
        let displayRect = CGRect(x: rect.minX + localPixels.minX / scale,
                                 y: rect.maxY - localPixels.maxY / scale,
                                 width: localPixels.width / scale, height: localPixels.height / scale)
        pendingEffectRender = (generation, {
            let result: CGImage? = autoreleasepool {
                let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
                guard let crop = source.cropping(to: pixels) else { return nil }
                let local = effects.map { original -> Annotation in
                    var a = original
                    a.startPoint.x -= rect.minX; a.startPoint.y -= rect.minY
                    a.endPoint.x -= rect.minX; a.endPoint.y -= rect.minY
                    a.points = a.points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
                    return a
                }
                return AnnotationEffectRenderer.render(source: crop, logicalSize: rect.size, annotations: local, outputRect: localPixels)
            }
            return (result, displayRect)
        })
        startNextEffectPreview()
    }

    /// One render in flight, one latest request: continuous input cannot starve
    /// the preview or accumulate a queue of obsolete pointer positions.
    private func startNextEffectPreview() {
        guard !effectRendering, let (generation, render) = pendingEffectRender else { return }
        pendingEffectRender = nil
        effectRendering = true
        effectQueue.async { [weak self] in
            let (image, rect) = render()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.effectRendering = false
                if self.effectGeneration == generation {
                    self.effectPreview = image; self.effectPreviewRect = rect
                }
                self.startNextEffectPreview()
            }
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
                applyInitialTool()
            }
        }
    }
    
    func applyInitialTool() {
        selectedTool = settings.initialAnnotationTool
    }

    // MARK: - Annotation Logic
    
    @Published var selectedAnnotationID: UUID?
    
    func annotationID(at point: CGPoint) -> UUID? {
        hitTest(at: point)
    }
    
    private struct AnnotationPress {
        var candidate: UUID?
        var tool: AnnotationType?
        var dragged = false
    }
    private var annotationPress: AnnotationPress?
    private let annotationClickTolerance: CGFloat = 5

    /// Decide once at pointer-down. Wait for pointer-up before stealing a drawing
    /// gesture; moving away and back remains a drag, never a click.
    @discardableResult
    func handleAnnotationPressChanged(from start: CGPoint, to point: CGPoint) -> Bool {
        if annotationPress == nil {
            let canSelect = state == .editing && selectedTool != nil && !isEditingText && !isDrawingEffectBrush
                && currentAnnotation == nil && activeSelectionHandle == nil && selectionRect.contains(start)
            annotationPress = AnnotationPress(candidate: canSelect ? hitTest(at: start) : nil, tool: selectedTool)
        }
        guard var press = annotationPress, press.candidate != nil else { return false }
        press.dragged = press.dragged || hypot(point.x - start.x, point.y - start.y) >= annotationClickTolerance
        annotationPress = press
        if press.dragged {
            if let id = press.candidate,
               let annotation = annotations.first(where: { $0.id == id }),
               [.text, .number].contains(annotation.type), press.tool == .text || press.tool == .number {
                // A first drag selects and moves the same object, without a preliminary click.
                selectedAnnotationID = id
                selectedColor = annotation.color
                selectedTool = annotation.type
                if annotation.type == .text { selectedFontSize = annotation.fontSize }
                else { selectedNumberFontSize = annotation.fontSize; selectedNumberStyle = annotation.numberStyle }
                lastTextTapAnnotationID = nil; lastTextTapDate = nil
                _ = handleSelectedShapeDrag(from: start, to: point, within: selectionRect)
            } else if press.tool != .text, press.tool != .number {
                if !hasDrawingGesture { startDrawing(at: start) }
                updateDrawing(to: point)
            }
        }
        return true
    }

    @discardableResult
    func handleAnnotationPressEnded(from start: CGPoint, to point: CGPoint) -> Bool {
        guard let press = annotationPress, let id = press.candidate else { return false }
        let dragged = press.dragged || hypot(point.x - start.x, point.y - start.y) >= annotationClickTolerance
        if dragged {
            if isTransformingShape {
                _ = handleSelectedShapeDrag(from: start, to: point, within: selectionRect)
                endSelectedShapeDrag()
            } else if press.tool != .text, press.tool != .number {
                if !hasDrawingGesture { startDrawing(at: start) }
                updateDrawing(to: point)
                endDrawing()
            }
        } else if state == .editing, selectionRect.contains(point), annotations.contains(where: { $0.id == id }) {
            selectExistingAnnotation(id: id)
        }
        currentPoint = nil
        return true
    }

    func clearAnnotationPress() {
        annotationPress = nil
    }

    private struct ShapeDrag {
        let annotation: Annotation
        let start: CGPoint
        let handle: SelectionHandle?
        var arrowEndpoint: Bool? = nil
        var moved = false
    }
    private var shapeDrag: ShapeDrag?
    var isTransformingShape: Bool { shapeDrag != nil }

    var selectedShapeRect: CGRect? {
        guard state == .editing, !isEditingText,
              let annotation = annotations.first(where: { $0.id == selectedAnnotationID }),
              ([.rectangle, .ellipse].contains(annotation.type) || ((annotation.type == .mosaic || annotation.type == .blur) && !annotation.isEffectBrush)) else { return nil }
        return CGRect(from: annotation.startPoint, to: annotation.endPoint)
    }

    private var selectedMoveRect: CGRect? {
        guard let annotation = annotations.first(where: { $0.id == selectedAnnotationID }) else { return nil }
        if annotation.type == .pen || annotation.isEffectBrush { return annotation.selectionBounds.insetBy(dx: -5, dy: -5) }
        return selectedShapeRect
    }

    /// After a shape is selected, its empty interior can move it. Visible content
    /// from another annotation still takes precedence, and crop handles run first.
    @discardableResult
    func handleSelectedShapeDrag(from start: CGPoint, to point: CGPoint, within bounds: CGRect) -> Bool {
        if shapeDrag == nil {
            guard state == .editing, !isEditingText, !isMovingSelection, !isResizingText, activeSelectionHandle == nil,
                  let annotation = annotations.first(where: { $0.id == selectedAnnotationID }) else { return false }
            let rect = annotation.selectionBounds
            let handle = (selectedShapeRect == nil ? [] : SelectionHandle.allCases).filter {
                let p = $0.position(in: rect)
                return abs(start.x - p.x) <= 8 && abs(start.y - p.y) <= 8
            }.min {
                let a = $0.position(in: rect), b = $1.position(in: rect)
                return hypot(start.x - a.x, start.y - a.y) < hypot(start.x - b.x, start.y - b.y)
            }
            let arrowEndpoint: Bool?
            if annotation.type == .arrow, hypot(start.x - annotation.startPoint.x, start.y - annotation.startPoint.y) <= 8 { arrowEndpoint = true }
            else if annotation.type == .arrow, hypot(start.x - annotation.endPoint.x, start.y - annotation.endPoint.y) <= 8 { arrowEndpoint = false }
            else { arrowEndpoint = nil }
            if handle == nil && arrowEndpoint == nil {
                let hit = hitTest(at: start)
                guard hit == annotation.id || (hit == nil && selectedMoveRect?.contains(start) == true) else { return false }
                if [.text, .number].contains(annotation.type), hypot(point.x - start.x, point.y - start.y) < 5 { return false }
            }
            shapeDrag = ShapeDrag(annotation: annotation, start: start, handle: handle, arrowEndpoint: arrowEndpoint)
        }
        guard var drag = shapeDrag, let index = annotations.firstIndex(where: { $0.id == drag.annotation.id }) else { return false }
        drag.moved = drag.moved || hypot(point.x - drag.start.x, point.y - drag.start.y) >= annotationClickTolerance
        shapeDrag = drag
        guard drag.moved else { return true }
        if let tail = drag.arrowEndpoint {
            let originalPoint = tail ? drag.annotation.startPoint : drag.annotation.endPoint
            let endpoint = clampPoint(CGPoint(x: originalPoint.x + point.x - drag.start.x,
                                             y: originalPoint.y + point.y - drag.start.y), to: bounds)
            let opposite = tail ? drag.annotation.endPoint : drag.annotation.startPoint
            if hypot(endpoint.x - opposite.x, endpoint.y - opposite.y) >= 5 {
                if tail { annotations[index].startPoint = endpoint }
                else { annotations[index].endPoint = endpoint }
            }
            return true
        }
        let original = CGRect(from: drag.annotation.startPoint, to: drag.annotation.endPoint)
        let dx = point.x - drag.start.x, dy = point.y - drag.start.y
        let updated: CGRect
        if let handle = drag.handle {
            let minimum: CGFloat = 12
            var left = original.minX, right = original.maxX
            var top = original.minY, bottom = original.maxY
            if [.left, .topLeft, .bottomLeft].contains(handle) {
                left = min(max(left + dx, bounds.minX), right - minimum)
            }
            if [.right, .topRight, .bottomRight].contains(handle) {
                right = max(min(right + dx, bounds.maxX), left + minimum)
            }
            if [.top, .topLeft, .topRight].contains(handle) {
                top = min(max(top + dy, bounds.minY), bottom - minimum)
            }
            if [.bottom, .bottomLeft, .bottomRight].contains(handle) {
                bottom = max(min(bottom + dy, bounds.maxY), top + minimum)
            }
            updated = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        } else {
            updated = original.offsetBy(dx: dx, dy: dy)
        }
        if drag.handle == nil {
            annotations[index].startPoint = CGPoint(x: drag.annotation.startPoint.x + dx, y: drag.annotation.startPoint.y + dy)
            annotations[index].endPoint = CGPoint(x: drag.annotation.endPoint.x + dx, y: drag.annotation.endPoint.y + dy)
            annotations[index].points = drag.annotation.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else {
            annotations[index].startPoint = updated.origin
            annotations[index].endPoint = CGPoint(x: updated.maxX, y: updated.maxY)
        }
        return true
    }

    func endSelectedShapeDrag() {
        if let drag = shapeDrag, let index = annotations.firstIndex(where: { $0.id == drag.annotation.id }),
           annotations[index] != drag.annotation {
            annotationUndo.append(.restore(drag.annotation, index))
        }
        shapeDrag = nil
        currentPoint = nil
    }

    private func selectExistingAnnotation(id: UUID) {
        guard let annotation = annotations.first(where: { $0.id == id }) else { return }
        selectedAnnotationID = id
        selectedTool = visibleToolbarItems.contains(where: { $0.annotationType == annotation.type }) ? annotation.type : nil
        selectedColor = annotation.color
        if annotation.type == .number { selectedNumberFontSize = annotation.fontSize; selectedNumberStyle = annotation.numberStyle }
        if annotation.type == .text || annotation.type == .number {
            if annotation.type == .text { selectedFontSize = annotation.fontSize }
            if lastTextTapAnnotationID == id, let last = lastTextTapDate,
               Date().timeIntervalSince(last) < 0.35 {
                if annotation.type == .number { startNumberEdit(annotationID: id) }
                else { startTextEdit(annotationID: id) }
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
    }

    func startDrawing(at point: CGPoint) {
        // A second click on selected text remains an edit gesture.
        if let id = selectedAnnotationID, hitTest(at: point) == id,
           annotations.first(where: { $0.id == id })?.type == .text {
            selectExistingAnnotation(id: id)
            return
        }
        // If no tool selected, try to select an annotation
        if selectedTool == nil {
            if let id = hitTest(at: point) {
                selectExistingAnnotation(id: id)
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
        annotation.lineWidth = settings.annotationStyle(for: tool).lineWidth
        let startPoint = (tool == .mosaic || tool == .blur) ? clampPoint(point, to: selectionRect) : point
        annotation.startPoint = startPoint
        annotation.endPoint = startPoint
        if tool == .pen || ((tool == .mosaic || tool == .blur) && effectDrawingMode(for: tool) == .brush) {
            annotation.points = [startPoint]
        }
        if tool == .mosaic || tool == .blur {
            annotation.lineWidth = selectedEffectBrushWidth
            annotation.mosaicBlockSize = selectedMosaicBlockSize
            annotation.blurRadius = selectedBlurRadius
        }
        if [.rectangle, .ellipse, .arrow, .mosaic, .pen, .blur].contains(tool) {
            pendingDrawing = annotation
            currentAnnotation = nil
        } else {
            currentAnnotation = annotation
        }

        // Deselect any existing annotation when drawing new one
        selectedAnnotationID = nil
    }
    
    func updateDrawing(to point: CGPoint) {
        if selectedTool == nil, selectedAnnotationID != nil { return }

        guard state == .editing, var annotation = currentAnnotation ?? pendingDrawing else { return }
        
        let nextPoint = (annotation.type == .mosaic || annotation.type == .blur) ? clampPoint(point, to: selectionRect) : point
        annotation.endPoint = nextPoint
        if annotation.type == .pen || annotation.isEffectBrush {
            if annotation.points.last != nextPoint { annotation.points.append(nextPoint) }
        }
        let distance = hypot(annotation.endPoint.x - annotation.startPoint.x, annotation.endPoint.y - annotation.startPoint.y)
        let rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
        let valid: Bool
        if annotation.type == .pen || annotation.isEffectBrush {
            valid = annotation.points.contains { hypot($0.x - annotation.startPoint.x, $0.y - annotation.startPoint.y) >= annotationClickTolerance }
        } else {
            switch annotation.type {
            case .rectangle, .ellipse, .mosaic, .blur: valid = rect.width >= 3 && rect.height >= 3 && distance >= 5
            case .arrow: valid = distance >= 5
            default: valid = true
            }
        }
        currentAnnotation = valid ? annotation : nil
        pendingDrawing = valid ? nil : annotation
    }

    /// Preserve the pointer-down location, even if SwiftUI's first callback has moved.
    func handleDrawingDrag(from start: CGPoint, to point: CGPoint) {
        if !hasDrawingGesture { startDrawing(at: start) }
        updateDrawing(to: point)
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
            annotationUndo.append(.remove(annotation.id))
            // Brush effects stay ready for overlapping strokes; use Select/Move to edit them.
            selectedAnnotationID = annotation.isEffectBrush ? nil : annotation.id
        }
        currentAnnotation = nil
        pendingDrawing = nil
    }

    @discardableResult
    func deleteSelectedAnnotation() -> Bool {
        guard state == .editing, !isEditingText, let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        let removed = annotations[index]
        recordNumberUndo(.restore(removed, index))
        annotations.remove(at: index)
        if removed.type == .number, removed.id == lastNumberID {
            nextNumber = Int(removed.text) ?? nextNumber
            lastNumberID = annotations.last(where: { $0.type == .number && Int($0.text) == nextNumber - 1 })?.id
        }
        selectedAnnotationID = nil
        endSelectedShapeDrag()
        clearAnnotationPress()
        currentAnnotation = nil
        pendingDrawing = nil
        return true
    }

    func undoLastAnnotation() {
        if let edit = annotationUndo.popLast() {
            var action = edit
            if case .numbered(let wrapped, let next, let last, let size, let color, let style) = edit {
                nextNumber = next; lastNumberID = last
                selectedNumberFontSize = size; selectedColor = color; selectedNumberStyle = style
                action = wrapped
            }
            if case .effect(let wrapped, let block, let width, let radius) = edit {
                selectedMosaicBlockSize = block; selectedEffectBrushWidth = width; selectedBlurRadius = radius
                action = wrapped
            }
            switch action {
            case .numbered, .effect: break
            case .remove(let id): annotations.removeAll { $0.id == id }
            case .restore(let annotation, let index):
                annotations.removeAll { $0.id == annotation.id }
                annotations.insert(annotation, at: min(index, annotations.count))
            }
        } else if !annotations.isEmpty {
            annotations.removeLast()
        }
        if let annotation = annotations.first(where: { $0.id == selectedAnnotationID }) {
            selectedColor = annotation.color
            if annotation.type == .text { selectedFontSize = annotation.fontSize }
            if annotation.type == .number { selectedNumberFontSize = annotation.fontSize; selectedNumberStyle = annotation.numberStyle }
            if annotation.type == .mosaic || annotation.type == .blur {
                selectedMosaicBlockSize = annotation.mosaicBlockSize
                selectedBlurRadius = annotation.blurRadius
                if annotation.isEffectBrush { selectedEffectBrushWidth = annotation.lineWidth }
            }
        } else { selectedAnnotationID = nil }
    }
    
    func reset() {
        confirmationClick = nil
        clearImageTranslation()
        showsStylePopover = false
        endSelectedShapeDrag()
        clearAnnotationPress()
        endTextInputPress()
        toolbarConfiguration = settings.toolbarConfiguration
        useRoundedCorners = settings.useRoundedCorners
        startPoint = nil
        currentPoint = nil
        selectionRect = .zero
        state = .idle
        annotations = []
        annotationUndo = []
        pendingDrawing = nil
        currentAnnotation = nil
        selectedTool = nil
        selectedAnnotationID = nil
        cancelTextInput()
        nextNumber = 1
        lastNumberID = nil
        selectedNumberFontSize = Annotation.numberFontSize
        lastTextTapAnnotationID = nil
        lastTextTapDate = nil
        activeSelectionHandle = nil
        isMovingSelection = false
        isResizingText = false
        textResizeOriginal = nil
        previewImage = nil
        previewScale = 1.0
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
    private(set) var didCommitTextOnPress = false

    /// Consume the entire outside press, including its release, so dismissing an
    /// empty editor cannot immediately create another editor at the same point.
    func handleTextInputPress(from point: CGPoint) -> Bool {
        if didCommitTextOnPress { return true }
        guard isEditingText else { return false }
        if !editingTextEditorFrame.contains(point) {
            didCommitTextOnPress = true
            commitTextInput()
        }
        return true
    }

    func endTextInputPress() { didCommitTextOnPress = false }

    /// 文字编辑器当前尺寸（由视图上报，随内容自动增长，用于定位与外部点击判定）
    @Published var editingTextSize: CGSize = CGSize(width: 120, height: 34)

    var editingNumberCircleRect: CGRect? {
        guard isEditingNumber, var number = annotations.first(where: { $0.id == editingTextAnnotationID }) else { return nil }
        number.text = editingTextContent; number.fontSize = inputFontSize
        return number.selectionBounds
    }

    var editingTextContentFrame: CGRect {
        if let circle = editingNumberCircleRect {
            return CGRect(x: circle.midX - editingTextSize.width / 2,
                          y: circle.midY - editingTextSize.height / 2,
                          width: editingTextSize.width, height: editingTextSize.height)
        }
        return CGRect(origin: editingTextPosition, size: editingTextSize)
    }

    /// The circle counts as inside the number editor, not an outside commit click.
    var editingTextEditorFrame: CGRect {
        editingNumberCircleRect?.union(editingTextContentFrame) ?? editingTextContentFrame
    }

    func updateEditingTextSize(_ size: CGSize) {
        if size != editingTextSize { editingTextSize = size }
    }

    func startTextInput(at point: CGPoint) {
        guard state == .editing, selectedTool == .text else { return }

        // Restriction: Input must be inside selection rect
        if !selectionRect.contains(point) {
             return
        }

        if let id = hitTest(at: point) {
            selectExistingAnnotation(id: id)
            return
        }

        editingTextSize = AnnotationTextLayout(text: "", fontSize: selectedFontSize, isNumber: false).size
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

        cancelTextInput()
        selectedFontSize = annotation.fontSize
        selectedColor = annotation.color
        editingTextSize = annotation.textBoundingSize
        isEditingText = true
        editingTextPosition = annotation.startPoint
        editingTextContent = annotation.text
        editingTextAnnotationID = annotationID
        selectedAnnotationID = annotationID
    }
    
    var isEditingNumber: Bool {
        isEditingText && annotations.contains { $0.id == editingTextAnnotationID && $0.type == .number }
    }

    var inputFontSize: CGFloat { isEditingNumber ? selectedNumberFontSize : selectedFontSize }

    func startNumberEdit(annotationID: UUID) {
        guard state == .editing, let a = annotations.first(where: { $0.id == annotationID }), a.type == .number else { return }
        cancelTextInput()
        isEditingText = true
        editingTextSize = a.textBoundingSize
        selectedColor = a.color
        editingTextAnnotationID = a.id
        editingTextContent = a.text
        editingTextPosition = a.selectionBounds.origin
        selectedAnnotationID = a.id
        selectedNumberFontSize = a.fontSize
        selectedNumberStyle = a.numberStyle
    }

    func commitTextInput() {
        guard isEditingText else { return }
        if isEditingNumber {
            let value = editingTextContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(value), (1...9999).contains(number),
                  let index = annotations.firstIndex(where: { $0.id == editingTextAnnotationID }) else {
                NSSound.beep(); return
            }
            recordNumberUndo(.restore(annotations[index], index))
            annotations[index].text = String(number)
            nextNumber = number + 1
            lastNumberID = annotations[index].id
            cancelTextInput()
            selectedAnnotationID = nil
            selectedTool = .number
            return
        }

        if let editingID = editingTextAnnotationID,
           let index = annotations.firstIndex(where: { $0.id == editingID }) {
            // Keep text edits and removal in the same undo history as other edits.
            if annotations[index].text != editingTextContent {
                annotationUndo.append(.restore(annotations[index], index))
            }
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
            annotationUndo.append(.remove(annotation.id))
        }

        isEditingText = false
        editingTextContent = ""
        editingTextAnnotationID = nil
        // Keep continuous text entry; explicit tool changes remain in selectTool.
        selectedAnnotationID = nil
        selectedTool = .text
    }
    
    func cancelTextInput() {
        isEditingText = false
        editingTextContent = ""
        editingTextAnnotationID = nil
    }

    /// 切换标注工具。切离文字工具时取消未完成的文字输入（连带 bug 1）。
    func selectTool(_ tool: AnnotationType?) {
        endSelectedShapeDrag()
        clearAnnotationPress()
        selectedTool = tool
        selectedAnnotationID = nil
        currentAnnotation = nil
        pendingDrawing = nil
        if let tool { loadToolDefaults(for: tool) }
        if tool != .text {
            cancelTextInput()
        }
    }

    // MARK: - Number Annotation
    private(set) var nextNumber = 1
    private var lastNumberID: UUID?

    private func recordNumberUndo(_ edit: AnnotationUndo) {
        annotationUndo.append(.numbered(edit, nextNumber, lastNumberID, selectedNumberFontSize, selectedColor, selectedNumberStyle))
    }

    func placeNumber(at point: CGPoint) {
        guard state == .editing, selectedTool == .number, !isEditingText, nextNumber <= 9999 else { return }
        guard selectionRect.contains(point) else { return }

        var annotation = Annotation(type: .number, color: selectedColor)
        annotation.startPoint = point
        annotation.text = String(nextNumber)
        annotation.fontSize = selectedNumberFontSize
        annotation.numberStyle = selectedNumberStyle
        recordNumberUndo(.remove(annotation.id))
        annotations.append(annotation)
        lastNumberID = annotation.id
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
        annotation.containsSelectionPoint(point)
    }

    private func clampPoint(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return CGPoint(x: x, y: y)
    }

    enum CursorStyle: Equatable {
        case crosshair, move, horizontal, vertical, diagonalDown, diagonalUp
    }

    func cursorStyle(at point: CGPoint) -> CursorStyle {
        func nearest(_ rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
            SelectionHandle.allCases.filter {
                let p = $0.position(in: rect)
                return abs(point.x - p.x) <= tolerance && abs(point.y - p.y) <= tolerance
            }.min {
                let a = $0.position(in: rect), b = $1.position(in: rect)
                return hypot(point.x - a.x, point.y - a.y) < hypot(point.x - b.x, point.y - b.y)
            }
        }
        func style(_ handle: SelectionHandle) -> CursorStyle {
            switch handle {
            case .left, .right: return .horizontal
            case .top, .bottom: return .vertical
            case .topLeft, .bottomRight: return .diagonalDown
            case .topRight, .bottomLeft: return .diagonalUp
            }
        }
        if canResizeSelection, let handle = nearest(selectionRect, tolerance: 10) { return style(handle) }
        guard state == .editing || state == .longCaptureReady, !isEditingText else { return .crosshair }
        if let handle = selectedTextResizeHandle, abs(point.x - handle.x) <= 8, abs(point.y - handle.y) <= 8 { return .diagonalDown }
        if let rect = selectedShapeRect, let handle = nearest(rect, tolerance: 8) { return style(handle) }
        if let a = annotations.first(where: { $0.id == selectedAnnotationID }) {
            if a.type == .arrow, [a.startPoint, a.endPoint].contains(where: { hypot(point.x - $0.x, point.y - $0.y) <= 8 }) { return .move }
            let hit = hitTest(at: point)
            if hit == a.id || (hit == nil && selectedMoveRect?.contains(point) == true) { return .move }
        }
        // Advertise the same visible hit area used by clicking to select.
        // Effect brushes keep painting across existing content; their unselected
        // strokes do not gain a hover affordance meant for editable shapes.
        if !isDrawingEffectBrush,
           let id = hitTest(at: point), let a = annotations.first(where: { $0.id == id }),
           !a.isEffectBrush { return .move }
        if canMoveSelection(from: point) { return .move }
        return .crosshair
    }

    func handleTextResizeDrag(from start: CGPoint, to point: CGPoint) -> Bool {
        guard state == .editing, !isEditingText else { return false }
        if !isResizingText {
            guard let handle = selectedTextResizeHandle,
                  abs(start.x - handle.x) <= 8, abs(start.y - handle.y) <= 8 else { return false }
            beginTextResize(at: start)
        }
        updateTextResize(to: point)
        return true
    }

    // MARK: - Tool Properties
    var propertyTool: AnnotationType? {
        annotations.first(where: { $0.id == selectedAnnotationID })?.type ?? selectedTool
    }

    var propertyTitle: String {
        propertyTool.flatMap { ToolbarItem(rawValue: $0.rawValue) }.map { "\($0.title)属性" } ?? "工具属性"
    }

    var currentToolStyle: AnnotationToolStyle {
        guard let tool = propertyTool else { return .factory(for: .text) }
        var style = settings.annotationStyle(for: tool)
        if let annotation = annotations.first(where: { $0.id == selectedAnnotationID }) {
            style.color = annotation.color
            style.lineWidth = annotation.lineWidth
            style.fontSize = annotation.fontSize
            style.numberStyle = annotation.numberStyle
            style.blockSize = annotation.mosaicBlockSize
            style.blurRadius = annotation.blurRadius
            if tool == .mosaic || tool == .blur { style.effectMode = annotation.isEffectBrush ? .brush : .rectangle }
            if annotation.isEffectBrush { style.brushWidth = annotation.lineWidth }
        }
        return style
    }

    private func loadToolDefaults(for tool: AnnotationType) {
        let style = settings.annotationStyle(for: tool)
        selectedColor = style.color
        if tool == .text { selectedFontSize = style.fontSize }
        if tool == .number { selectedNumberFontSize = style.fontSize; selectedNumberStyle = style.numberStyle }
        if tool == .mosaic { selectedMosaicMode = style.effectMode }
        if tool == .blur { selectedBlurMode = style.effectMode }
        selectedMosaicBlockSize = style.blockSize
        selectedBlurRadius = style.blurRadius
        selectedEffectBrushWidth = style.brushWidth
    }

    /// Changing an object is undoable; reading/selecting it never changes saved defaults.
    private func changeToolStyle(_ change: (inout AnnotationToolStyle) -> Void) {
        guard let tool = propertyTool else { return }
        var style = currentToolStyle
        change(&style)
        applyToolStyle(style.validated, for: tool)
    }

    private func applyToolStyle(_ style: AnnotationToolStyle, for tool: AnnotationType) {
        settings.setAnnotationStyle(style, for: tool)
        loadToolDefaults(for: tool)
        guard let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }), annotations[index].type == tool else { return }
        let original = annotations[index]
        var updated = original
        if tool == .mosaic || tool == .blur {
            updated.mosaicBlockSize = style.blockSize
            updated.blurRadius = style.blurRadius
            if updated.isEffectBrush { updated.lineWidth = style.brushWidth }
        } else {
            updated.color = style.color
            if [.pen, .rectangle, .ellipse, .arrow].contains(tool) { updated.lineWidth = style.lineWidth }
            if tool == .text || tool == .number { updated.fontSize = style.fontSize }
            if tool == .number { updated.numberStyle = style.numberStyle }
        }
        if updated != original {
            annotationUndo.append(.restore(original, index))
            annotations[index] = updated
        }
    }

    func restoreCurrentToolDefaults() {
        guard let tool = propertyTool else { return }
        applyToolStyle(.factory(for: tool), for: tool)
    }

    func setColor(_ color: Color) { changeToolStyle { $0.color = color } }
    func setLineWidth(_ width: CGFloat) { changeToolStyle { $0.lineWidth = width } }
    func setNumberStyle(_ style: NumberAnnotationStyle) { changeToolStyle { $0.numberStyle = style } }
    func setFontSize(_ size: CGFloat) { changeToolStyle { $0.fontSize = size } }

    var editingNumberAnnotation: Annotation? {
        annotations.first { $0.id == editingTextAnnotationID && $0.type == .number }
    }

    var editingTextColor: NSColor {
        editingNumberAnnotation?.textColor ?? NSColor(selectedColor)
    }

    // MARK: - Text Resize（拖拽角标缩放字号）
    @Published var isResizingText: Bool = false
    private var textResizeAnchor: CGPoint = .zero
    private var textResizeStartFontSize: CGFloat = 24
    private var textResizeStartDiag: CGFloat = 1
    private var textResizeOriginal: Annotation?
    private var numberResizeState: (Int, UUID?, CGFloat, Color, NumberAnnotationStyle)?

    /// 文字与序号共用右下角字号缩放手柄；序号保持中心锚点。
    var selectedTextResizeHandle: CGPoint? {
        guard let id = selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == id }),
              [.text, .number].contains(annotation.type) else { return nil }
        let rect = annotation.selectionBounds
        return CGPoint(x: rect.maxX, y: rect.maxY)
    }

    func beginTextResize(at point: CGPoint) {
        guard let id = selectedAnnotationID,
              let annotation = annotations.first(where: { $0.id == id }),
              [.text, .number].contains(annotation.type) else { return }
        isResizingText = true
        textResizeOriginal = annotation
        textResizeAnchor = annotation.startPoint
        textResizeStartFontSize = annotation.fontSize
        let handle = selectedTextResizeHandle ?? annotation.startPoint
        textResizeStartDiag = max(hypot(handle.x - textResizeAnchor.x, handle.y - textResizeAnchor.y), 1)
        numberResizeState = (nextNumber, lastNumberID, selectedNumberFontSize, selectedColor, selectedNumberStyle)
    }

    func updateTextResize(to point: CGPoint) {
        guard isResizingText, let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        let diag = hypot(point.x - textResizeAnchor.x, point.y - textResizeAnchor.y)
        let scale = diag / max(textResizeStartDiag, 1)
        let newSize = min(max(textResizeStartFontSize * scale, 8), 96)
        annotations[index].fontSize = newSize
        if annotations[index].type == .number { selectedNumberFontSize = newSize }
        else { selectedFontSize = newSize }
    }

    func endTextResize() {
        if let original = textResizeOriginal, let index = annotations.firstIndex(where: { $0.id == original.id }),
           annotations[index] != original {
            if original.type == .number, let old = numberResizeState {
                annotationUndo.append(.numbered(.restore(original, index), old.0, old.1, old.2, old.3, old.4))
            } else { annotationUndo.append(.restore(original, index)) }
            var style = settings.annotationStyle(for: original.type)
            style.fontSize = annotations[index].fontSize
            style.color = annotations[index].color
            settings.setAnnotationStyle(style, for: original.type)
        }
        numberResizeState = nil
        textResizeOriginal = nil
        isResizingText = false
    }

    func canMoveSelection(from point: CGPoint) -> Bool {
        guard captureMode != .imageEditor, selectedTool == nil, !isEditingText,
              state == .editing || state == .longCaptureReady,
              !selectionRect.isEmpty, hitTest(at: point) == nil else { return false }
        let tolerance: CGFloat = 6
        let outer = selectionRect.insetBy(dx: -tolerance, dy: -tolerance)
        let inner = selectionRect.insetBy(dx: tolerance, dy: tolerance)
        guard outer.contains(point), !inner.contains(point) else { return false }
        // The visible eight resize handles take precedence over the move band.
        return !SelectionHandle.allCases.contains { handle in
            let position = handle.position(in: selectionRect)
            return abs(point.x - position.x) <= 10 && abs(point.y - position.y) <= 10
        }
    }

    func beginMoveSelection(at point: CGPoint) {
        guard canMoveSelection(from: point) else { return }
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

    var canResizeSelection: Bool {
        captureMode != .imageEditor && (state == .editing || state == .longCaptureReady) && !selectionRect.isEmpty
    }

    /// Resize handles take priority over annotation tools for the entire drag.
    /// Use the gesture's start point so crossing a handle while drawing cannot resize the crop.
    @discardableResult
    func handleSelectionResizeDrag(from start: CGPoint, to point: CGPoint, within bounds: CGRect) -> Bool {
        guard canResizeSelection, !isMovingSelection, !isResizingText, currentAnnotation == nil else { return false }
        if activeSelectionHandle == nil {
            let candidates = SelectionHandle.allCases.filter {
                let position = $0.position(in: selectionRect)
                return abs(start.x - position.x) <= 10 && abs(start.y - position.y) <= 10
            }
            // Hit areas overlap for small selections; use the nearest visible handle.
            guard let handle = candidates.min(by: {
                let a = $0.position(in: selectionRect), b = $1.position(in: selectionRect)
                return hypot(start.x - a.x, start.y - a.y) < hypot(start.x - b.x, start.y - b.y)
            }) else { return false }
            let tool = selectedTool
            commitTextInput()
            selectedTool = tool
            beginResizeSelection(handle: handle, at: start)
        }
        updateResizeSelection(to: point, within: bounds)
        return true
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
