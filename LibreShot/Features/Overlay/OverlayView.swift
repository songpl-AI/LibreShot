import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    var showsToolbar = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 0: Preview Image (Frozen Screen)
                if let image = viewModel.previewImage {
                    Image(decorative: image, scale: viewModel.previewScale, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }
                if viewModel.translationSource != nil, !viewModel.showsOriginalTranslation,
                   let translated = viewModel.translatedSelection {
                    Image(decorative: translated, scale: viewModel.previewScale, orientation: .up)
                        .resizable()
                        .frame(width: viewModel.selectionRect.width, height: viewModel.selectionRect.height)
                        .position(x: viewModel.selectionRect.midX, y: viewModel.selectionRect.midY)
                        .allowsHitTesting(false)
                }

                if let effects = viewModel.effectPreview {
                    Canvas { context, _ in
                        context.clip(to: Path(roundedRect: viewModel.selectionRect, cornerRadius: viewModel.selectionCornerRadius))
                        context.draw(Image(decorative: effects, scale: viewModel.previewScale, orientation: .up), in: viewModel.effectPreviewRect)
                    }
                    .allowsHitTesting(false)
                }

                // Layer 1: Dimmed Background
                Path { path in
                    path.addRect(geometry.frame(in: .local))
                    if viewModel.selectionRect != .zero {
                        path.addRoundedRect(in: viewModel.selectionRect, cornerSize: CGSize(width: viewModel.selectionCornerRadius, height: viewModel.selectionCornerRadius))
                    }
                }
                .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                
                // Layer 2: Annotations (Inside Selection)
                if viewModel.state == .editing {
                    Canvas { context, size in
                        var drawingContext = context
                        drawingContext.clip(to: Path(roundedRect: viewModel.selectionRect, cornerRadius: viewModel.selectionCornerRadius))
                        // Control points remain outside this clip so they are always visible.
                        for annotation in viewModel.annotations {
                            // 正在编辑的文字标注不渲染（避免与编辑器重叠显示）
                            if annotation.id == viewModel.editingTextAnnotationID {
                                continue
                            }
                            drawAnnotation(context: drawingContext, annotation: annotation, canvasSize: size)
                            // Highlight selected annotation
                            if annotation.id == viewModel.selectedAnnotationID {
                                // Draw selection halo/border
                                let rect = annotation.selectionBounds
                                
                                // Draw Halo
                                let haloRect = rect.insetBy(dx: -5, dy: -5)
                                let haloPath = annotation.type == .text
                                    ? Path(roundedRect: haloRect, cornerRadius: 4) : Path(haloRect)
                                if annotation.isEffectBrush || ![AnnotationType.rectangle, .ellipse, .arrow, .mosaic, .blur].contains(annotation.type) {
                                    context.stroke(haloPath, with: .color(.blue.opacity(annotation.type == .text ? 0.85 : 0.5)), lineWidth: annotation.type == .text ? 1.5 : 2)
                                }
                                if annotation.type == .arrow {
                                    for point in [annotation.startPoint, annotation.endPoint] {
                                        let circle = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                                        context.fill(circle, with: .color(.blue))
                                        context.stroke(circle, with: .color(.white), lineWidth: 1.5)
                                    }
                                }

                                if let shapeRect = viewModel.selectedShapeRect {
                                    for handle in SelectionHandle.allCases {
                                        let position = handle.position(in: shapeRect)
                                        let box = CGRect(x: position.x - 4, y: position.y - 4, width: 8, height: 8)
                                        let circle = Path(ellipseIn: box)
                                        context.fill(circle, with: .color(.blue))
                                        context.stroke(circle, with: .color(.white), lineWidth: 1.5)
                                    }
                                }
                                // 文字选中：右下角缩放手柄
                                if annotation.type == .text || annotation.type == .number {
                                    let handlePos = CGPoint(x: rect.maxX, y: rect.maxY)
                                    let handleRect = CGRect(x: handlePos.x - 5, y: handlePos.y - 5, width: 10, height: 10)
                                    context.fill(Path(ellipseIn: handleRect), with: .color(.white))
                                    context.stroke(Path(ellipseIn: handleRect), with: .color(.blue), lineWidth: 1.5)
                                }
                            }
                        }
                        // Draw current annotation being dragged
                        if let current = viewModel.currentAnnotation {
                            drawAnnotation(context: drawingContext, annotation: current, canvasSize: size)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                }
                
                // Layer 3: Selection Border
                if viewModel.selectionRect != .zero {
                    let rect = viewModel.selectionRect
                    ZStack {
                        RoundedRectangle(cornerRadius: viewModel.selectionCornerRadius)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        
                        if viewModel.canResizeSelection {
                            let handleSize: CGFloat = 8
                            let handleHitSize: CGFloat = 20
                            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                                ZStack {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                                        .frame(width: handleSize, height: handleSize)
                                }
                                .frame(width: handleHitSize, height: handleHitSize)
                                .position(handle.position(in: rect))
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
                
                // Layer 4: Toolbar (Only in Editing mode)
                if viewModel.state == .editing {
                    if showsToolbar {
                    let layout = ToolbarLayout(items: viewModel.visibleToolbarItems, availableWidth: geometry.size.width - 20)
                    let accessorySize = editorAccessorySize(screenSize: geometry.size)
                    let toolbarPos = layout.position(selection: viewModel.selectionRect, screenSize: geometry.size,
                                                     accessorySize: accessorySize)
                    let accessoriesAbove = toolbarPos.y < viewModel.selectionRect.midY
                    VStack(spacing: 0) {
                        if accessoriesAbove { editorAccessories(screenSize: geometry.size) }
                        EditorToolbarView(viewModel: viewModel, layout: layout,
                                          toolbarPosition: CGPoint(x: toolbarPos.x, y: toolbarPos.y + (accessoriesAbove ? accessorySize.height / 2 : -accessorySize.height / 2)),
                                          screenSize: geometry.size, tooltipAbove: !accessoriesAbove && viewModel.propertyTool != nil)
                        if !accessoriesAbove { editorAccessories(screenSize: geometry.size) }
                    }
                        .position(x: toolbarPos.x, y: toolbarPos.y)
                        .zIndex(1)
                        
                    }
                    // Text Input Overlay（内联编辑：所见即所得，随内容动态调整大小）
                    if viewModel.isEditingText {
                        if let circle = viewModel.editingNumberCircleRect {
                            Circle()
                                .fill(viewModel.editingNumberAnnotation?.numberStyle == .filled ? (viewModel.editingNumberAnnotation?.numberFillColor ?? viewModel.selectedColor) : .clear)
                                .overlay(Circle().stroke(viewModel.editingNumberAnnotation?.numberBorderColor ?? viewModel.selectedColor, lineWidth: viewModel.editingNumberAnnotation?.numberBorderWidth ?? 3))
                                .frame(width: circle.width, height: circle.height)
                                .position(x: circle.midX, y: circle.midY)
                                .allowsHitTesting(false)
                        }
                        InlineTextEditor(
                            text: $viewModel.editingTextContent,
                            fontSize: viewModel.inputFontSize,
                            color: viewModel.editingTextColor,
                            cursorAtEnd: viewModel.editingTextAnnotationID != nil,
                            isNumber: viewModel.isEditingNumber,
                            selectsAllOnFocus: viewModel.isEditingNumber,
                            allowsAncestorScrolling: viewModel.captureMode != .imageEditor,
                            onSizeChange: { size in
                                viewModel.updateEditingTextSize(size)
                            }
                        )
                        .id(viewModel.editingTextAnnotationID)
                        .frame(
                            width: max(viewModel.editingTextSize.width, 2),
                            height: viewModel.editingTextSize.height
                        )
                        .help(viewModel.isEditingNumber ? "输入 1–9999；回车确认，Esc 取消改号" : "输入文字，点击外部确认")
                        .overlay {
                            if !viewModel.isEditingNumber {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue.opacity(0.85), lineWidth: 1.5)
                                    .padding(-5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .position(
                            x: viewModel.editingTextContentFrame.midX,
                            y: viewModel.editingTextContentFrame.midY
                        )
                    }
                } else if viewModel.state == .longCapturing {
                    let statusPos = calculateLongCaptureStatusPosition(screenSize: geometry.size)
                    LongCaptureInlineStatusView(viewModel: viewModel)
                        .position(x: statusPos.x, y: statusPos.y)
                }
            }
            .background(CaptureConfirmationMouseView(model: viewModel, acceptsPoint: { point in
                !editorToolbarFrame(screenSize: geometry.size).contains(point)
            }))
            .onContinuousHover(coordinateSpace: .named("overlay")) { phase in
                switch phase {
                case .active(let point):
                    if editorToolbarFrame(screenSize: geometry.size).contains(point) { NSCursor.arrow.set() }
                    else { OverlayPointerCursor.cursor(for: viewModel.cursorStyle(at: point)).set() }
                case .ended: NSCursor.arrow.set()
                }
            }
            .coordinateSpace(name: "overlay")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if editorToolbarFrame(screenSize: geometry.size).contains(value.startLocation) { return }
                        if viewModel.handleTextInputPress(from: value.startLocation) { return }
                        if viewModel.handleSelectionResizeDrag(
                            from: value.startLocation, to: value.location,
                            within: geometry.frame(in: .named("overlay"))
                        ) {
                            return
                        }
                        if viewModel.handleTextResizeDrag(from: value.startLocation, to: value.location) { return }
                        if viewModel.handleSelectedShapeDrag(from: value.startLocation, to: value.location,
                                                             within: geometry.frame(in: .named("overlay"))) {
                            return
                        }
                        if viewModel.handleAnnotationPressChanged(from: value.startLocation, to: value.location) {
                            return
                        }
                        if viewModel.canToggleTranslationPreview(from: value.startLocation, to: value.location) {
                            return
                        }
                        
                        if viewModel.state == .idle || viewModel.state == .selecting {
                            if viewModel.state != .selecting {
                                viewModel.startSelection(at: value.startLocation)
                            }
                            viewModel.updateSelection(to: value.location)
                        } else if viewModel.state == .editing || viewModel.state == .longCaptureReady {
                            // 1. Text / Number Tool Logic
                            if viewModel.selectedTool == .text || viewModel.selectedTool == .number {
                                // Do nothing on drag, wait for click (ended)
                                return
                            }
                            
                            // 2. Selection/Move Logic (No tool selected)
                            if viewModel.selectedTool == nil {
                                let bounds = geometry.frame(in: .named("overlay"))
                                
                                if viewModel.isMovingSelection {
                                    viewModel.updateMoveSelection(to: value.location, within: bounds)
                                    return
                                }
                                
                                if value.translation == .zero {
                                    // 文字缩放手柄
                                    if let textHandle = viewModel.selectedTextResizeHandle,
                                       abs(value.startLocation.x - textHandle.x) <= 8,
                                       abs(value.startLocation.y - textHandle.y) <= 8 {
                                        viewModel.beginTextResize(at: value.startLocation)
                                        return
                                    }
                                    
                                    if viewModel.canMoveSelection(from: value.startLocation) {
                                        viewModel.beginMoveSelection(at: value.startLocation)
                                        viewModel.updateMoveSelection(to: value.location, within: bounds)
                                        return
                                    }
                                    
                                    if viewModel.state == .editing {
                                        viewModel.startDrawing(at: value.location)
                                    }
                                } else {
                                    if viewModel.isResizingText {
                                        viewModel.updateTextResize(to: value.location)
                                        return
                                    }

                                    if viewModel.isMovingSelection {
                                        viewModel.updateMoveSelection(to: value.location, within: bounds)
                                        return
                                    }
                                    
                                    if viewModel.state != .editing {
                                        return
                                    }
                                    
                                    // Dragging selected annotation
                                    let currentX = viewModel.currentPoint?.x ?? value.startLocation.x
                                    let currentY = viewModel.currentPoint?.y ?? value.startLocation.y
                                    
                                    let deltaX = value.location.x - currentX
                                    let deltaY = value.location.y - currentY
                                    
                                    viewModel.moveSelectedAnnotation(offset: CGSize(width: deltaX, height: deltaY))
                                    
                                    viewModel.currentPoint = value.location
                                }
                                return
                            }
                            
                            // 3. Drawing Logic
                            if viewModel.state == .editing, viewModel.selectedTool != nil {
                                viewModel.handleDrawingDrag(from: value.startLocation, to: value.location)
                            }
                        }
                    }
                    .onEnded { value in
                        if editorToolbarFrame(screenSize: geometry.size).contains(value.startLocation) { return }
                        defer {
                            viewModel.clearAnnotationPress()
                            viewModel.endTextInputPress()
                        }
                        if viewModel.didCommitTextOnPress { return }
                        if viewModel.state == .selecting {
                            viewModel.endSelection()
                        } else if viewModel.state == .editing || viewModel.state == .longCaptureReady {
                            if viewModel.activeSelectionHandle != nil {
                                viewModel.endResizeSelection()
                                viewModel.currentPoint = nil
                                return
                            }
                            
                            if viewModel.isResizingText {
                                viewModel.updateTextResize(to: value.location)
                                viewModel.endTextResize()
                                return
                            }
                            if viewModel.isTransformingShape {
                                viewModel.handleSelectedShapeDrag(from: value.startLocation, to: value.location,
                                                                  within: geometry.frame(in: .named("overlay")))
                                viewModel.endSelectedShapeDrag()
                                return
                            }
                            if viewModel.handleAnnotationPressEnded(from: value.startLocation, to: value.location) {
                                return
                            }
                            if viewModel.canToggleTranslationPreview(from: value.startLocation, to: value.location) {
                                viewModel.toggleTranslationPreview()
                                return
                            }
                            // Text Tool Click
                            if viewModel.selectedTool == .text {
                                if !viewModel.isEditingText {
                                    // Check distance to ensure it was a click, not a drag attempt
                                    if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                                        viewModel.startTextInput(at: value.location)
                                    }
                                }
                            }
                            // Number Tool Click
                            else if viewModel.selectedTool == .number {
                                if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                                    viewModel.placeNumber(at: value.location)
                                }
                            }
                            // Selection Mode
                            else if viewModel.selectedTool == nil {
                                if viewModel.isResizingText {
                                    viewModel.endTextResize()
                                }
                                if viewModel.isMovingSelection {
                                    viewModel.endMoveSelection()
                                }
                                viewModel.currentPoint = nil
                            }
                            // Drawing Mode
                            else if viewModel.state == .editing {
                                viewModel.updateDrawing(to: value.location)
                                viewModel.endDrawing()
                            }
                        }
                    }
            )
        }
        .background(Color.clear)
    }
    
    private func editorAccessorySize(screenSize: CGSize) -> CGSize {
        let properties = ToolPropertyBarView.size(for: viewModel, availableWidth: screenSize.width - 20)
        let translationVisible = viewModel.translationSource != nil && viewModel.showsTranslationControls
        return CGSize(width: max(properties.width, translationVisible ? min(430, screenSize.width - 20) : 0),
                      height: (properties.height > 0 ? properties.height + 8 : 0) + (translationVisible ? 78 : 0))
    }

    private func editorToolbarFrame(screenSize: CGSize) -> CGRect {
        guard showsToolbar && viewModel.state == .editing else { return .null }
        let layout = ToolbarLayout(items: viewModel.visibleToolbarItems, availableWidth: screenSize.width - 20)
        let accessory = editorAccessorySize(screenSize: screenSize)
        return layout.frame(selection: viewModel.selectionRect, screenSize: screenSize, accessorySize: accessory)
    }

    @ViewBuilder private func editorAccessories(screenSize: CGSize) -> some View {
        VStack(spacing: 0) {
            if viewModel.propertyTool != nil {
                ToolPropertyBarView(viewModel: viewModel, availableWidth: screenSize.width - 20)
                    .padding(.vertical, 4)
            }
            if #available(macOS 26.0, *), let source = viewModel.translationSource {
                InlineImageTranslationView(viewModel: viewModel, image: source)
                    .id(viewModel.translationSessionID).frame(width: min(430, screenSize.width - 20))
            }
        }
    }

    func calculateLongCaptureStatusPosition(screenSize: CGSize) -> CGPoint {
        let rect = viewModel.selectionRect
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 18
        let preferredY = rect.minY - verticalPadding
        let clampedY = max(preferredY, 44)
        let clampedX = min(max(rect.midX, horizontalPadding), max(screenSize.width - horizontalPadding, horizontalPadding))
        return CGPoint(x: clampedX, y: clampedY)
    }

    func drawAnnotation(context: GraphicsContext, annotation: Annotation, canvasSize: CGSize) {
        // Effects are rendered underneath the annotation canvas by the shared renderer.
        if annotation.type == .mosaic || annotation.type == .blur { return }

        var path = Path()
        
        switch annotation.type {
        case .pen:
            if let first = annotation.points.first {
                path.move(to: first)
                for point in annotation.points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        case .rectangle:
            path.addPath(Path(annotation.rectanglePath))
        case .arrow:
            let arrow = annotation.arrowGeometry
            context.stroke(Path(arrow.shaft), with: .color(annotation.color),
                           style: StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round))
            context.fill(Path(arrow.head), with: .color(annotation.color))
            return

        case .ellipse:
            let rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
            path.addEllipse(in: rect)
        case .number:
            let radius = annotation.numberRadius
            let circleRect = CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2)
            path.addEllipse(in: circleRect)
        case .mosaic, .blur:
            break
        case .text:
            break
        }

        if annotation.type == .number {
            if annotation.numberStyle == .filled { context.fill(path, with: .color(annotation.numberFillColor)) }
            if annotation.numberBorderWidth > 0 { context.stroke(path, with: .color(annotation.numberBorderColor), lineWidth: annotation.numberBorderWidth) }
        } else if annotation.type != .text {
            context.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        }

        if (annotation.type == .text || annotation.type == .number), !annotation.text.isEmpty {
            let layout = AnnotationTextLayout(text: annotation.text, fontSize: annotation.fontSize,
                                              isNumber: annotation.type == .number, color: annotation.textColor)
            let origin = annotation.type == .number
                ? CGPoint(x: annotation.startPoint.x - layout.size.width / 2,
                          y: annotation.startPoint.y - layout.size.height / 2)
                : annotation.startPoint
            context.draw(Image(nsImage: layout.image()), in: CGRect(origin: origin, size: layout.size))
        }
    }

}

/// Intercept the second mouse-down before SwiftUI drawing gestures or NSTextView
/// double-click editing. The observer never consumes ordinary clicks or drags.
private struct CaptureConfirmationMouseView: NSViewRepresentable {
    let model: OverlayViewModel
    let acceptsPoint: (CGPoint) -> Bool

    func makeNSView(context: Context) -> CaptureConfirmationObserver { CaptureConfirmationObserver() }
    func updateNSView(_ view: CaptureConfirmationObserver, context: Context) {
        view.model = model
        view.acceptsPoint = acceptsPoint
    }
    static func dismantleNSView(_ view: CaptureConfirmationObserver, coordinator: ()) { view.stopObserving() }
}

private final class CaptureConfirmationObserver: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    weak var model: OverlayViewModel?
    var acceptsPoint: ((CGPoint) -> Bool)?
    private var monitor: Any?
    private var consumesMouseUp = false
    private var confirmationPoint: CGPoint?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self, event.window === self.window, let model = self.model else { return event }
            if self.consumesMouseUp {
                if event.type == .leftMouseUp { self.consumesMouseUp = false }
                return nil
            }
            let point = self.convert(event.locationInWindow, from: nil)
            if event.type == .leftMouseDown {
                guard self.bounds.contains(point), self.acceptsPoint?(point) == true else {
                    self.confirmationPoint = nil
                    return event
                }
                if event.clickCount == 2, let first = self.confirmationPoint,
                   hypot(point.x - first.x, point.y - first.y) < 5,
                   model.confirmDoubleClick(at: point) {
                    self.confirmationPoint = nil
                    self.consumesMouseUp = true
                    return nil
                }
                self.confirmationPoint = model.canConfirmDoubleClick(at: point) ? point : nil
                model.beginConfirmationClick(at: point)
            } else {
                if let first = self.confirmationPoint, hypot(point.x - first.x, point.y - first.y) >= 5 {
                    self.confirmationPoint = nil
                }
                model.endConfirmationClick(at: point)
            }
            return event
        }
    }

    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        consumesMouseUp = false
        confirmationPoint = nil
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct LongCaptureInlineStatusView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
            Text(viewModel.longCaptureStatusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

/// Diagonal resize cursors also work on the deployment target, macOS 13.
private enum OverlayPointerCursor {
    static let diagonalDown = diagonal(rising: false)
    static let diagonalUp = diagonal(rising: true)
    static func cursor(for style: OverlayViewModel.CursorStyle) -> NSCursor {
        switch style {
        case .crosshair: return .crosshair
        case .move: return .openHand
        case .horizontal: return .resizeLeftRight
        case .vertical: return .resizeUpDown
        case .diagonalDown: return diagonalDown
        case .diagonalUp: return diagonalUp
        }
    }
    private static func diagonal(rising: Bool) -> NSCursor {
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: rising ? y : 24 - y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: 12, y: 12))
    }
}
