import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

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

                // Layer 1: Dimmed Background
                Path { path in
                    path.addRect(geometry.frame(in: .local))
                    if viewModel.selectionRect != .zero {
                        path.addRect(viewModel.selectionRect)
                    }
                }
                .fill(Color.black.opacity(0.3), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                
                // Layer 2: Annotations (Inside Selection)
                if viewModel.state == .editing {
                    Canvas { context, size in
                        // Draw existing annotations
                        for annotation in viewModel.annotations {
                            // 正在编辑的文字标注不渲染（避免与编辑器重叠显示）
                            if annotation.id == viewModel.editingTextAnnotationID {
                                continue
                            }
                            // Highlight selected annotation
                            if annotation.id == viewModel.selectedAnnotationID {
                                // Draw selection halo/border
                                let rect: CGRect
                                if annotation.type == .text {
                                     rect = annotation.textBoundingRect
                                } else if annotation.type == .number {
                                     let radius = annotation.fontSize / 2 + 4
                                     rect = CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2)
                                } else {
                                     rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
                                }
                                
                                // Draw Halo
                                let haloPath = Path(rect.insetBy(dx: -5, dy: -5))
                                context.stroke(haloPath, with: .color(.blue.opacity(0.5)), lineWidth: 2)

                                // 文字选中：右下角缩放手柄
                                if annotation.type == .text {
                                    let handlePos = CGPoint(x: rect.maxX, y: rect.maxY)
                                    let handleRect = CGRect(x: handlePos.x - 5, y: handlePos.y - 5, width: 10, height: 10)
                                    context.fill(Path(ellipseIn: handleRect), with: .color(.white))
                                    context.stroke(Path(ellipseIn: handleRect), with: .color(.blue), lineWidth: 1.5)
                                }
                            }
                            
                            drawAnnotation(context: context, annotation: annotation, canvasSize: size)
                        }
                        // Draw current annotation being dragged
                        if let current = viewModel.currentAnnotation {
                            drawAnnotation(context: context, annotation: current, canvasSize: size)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                }
                
                // Layer 3: Selection Border
                if viewModel.selectionRect != .zero {
                    let rect = viewModel.selectionRect
                    ZStack {
                        Rectangle()
                            .stroke(viewModel.state == .longCapturing ? Color.blue : Color.white, lineWidth: viewModel.state == .longCapturing ? 2 : 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        
                        if (viewModel.state == .editing || viewModel.state == .longCaptureReady) && viewModel.selectedTool == nil {
                            let handleSize: CGFloat = 8
                            let handleHitSize: CGFloat = 20
                            ForEach(SelectionHandle.allCases, id: \.self) { handle in
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: handleSize, height: handleSize)
                                }
                                .frame(width: handleHitSize, height: handleHitSize)
                                .position(handlePosition(for: handle, in: rect))
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
                
                // Layer 4: Toolbar (Only in Editing mode)
                if viewModel.state == .editing {
                    let toolbarPos = calculateToolbarPosition(screenSize: geometry.size)
                    EditorToolbarView(viewModel: viewModel)
                        .position(x: toolbarPos.x, y: toolbarPos.y)
                        
                    // Text Input Overlay（内联编辑：所见即所得，随内容动态调整大小）
                    if viewModel.isEditingText {
                        InlineTextEditor(
                            text: $viewModel.editingTextContent,
                            fontSize: viewModel.selectedFontSize,
                            color: NSColor(viewModel.selectedColor),
                            cursorAtEnd: viewModel.editingTextAnnotationID != nil,
                            onSizeChange: { size in
                                if size != viewModel.editingTextSize {
                                    viewModel.editingTextSize = size
                                }
                            }
                        )
                        .frame(
                            width: max(viewModel.editingTextSize.width, 2),
                            height: max(viewModel.editingTextSize.height, viewModel.selectedFontSize * 1.4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.blue.opacity(0.55), lineWidth: 1.5)
                                .padding(-3)
                        )
                        .position(
                            x: viewModel.editingTextPosition.x + viewModel.editingTextSize.width / 2,
                            y: viewModel.editingTextPosition.y + viewModel.editingTextSize.height / 2
                        )
                    }
                } else if viewModel.state == .longCapturing {
                    let statusPos = calculateLongCaptureStatusPosition(screenSize: geometry.size)
                    LongCaptureInlineStatusView(viewModel: viewModel)
                        .position(x: statusPos.x, y: statusPos.y)
                }
            }
            .coordinateSpace(name: "overlay")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if viewModel.isEditingText {
                            // 点击编辑器外部提交
                            let editorRect = viewModel.editingTextEditorFrame
                            if !editorRect.contains(value.location) {
                                viewModel.commitTextInput()
                            }
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
                                let rect = viewModel.selectionRect
                                
                                if viewModel.isManipulatingSelection {
                                    if viewModel.activeSelectionHandle != nil {
                                        viewModel.updateResizeSelection(to: value.location, within: bounds)
                                    } else if viewModel.isMovingSelection {
                                        viewModel.updateMoveSelection(to: value.location, within: bounds)
                                    }
                                    return
                                }
                                
                                if value.translation == .zero {
                                    if let handle = selectionHandle(at: value.startLocation, in: rect, hitSize: 20) {
                                        viewModel.beginResizeSelection(handle: handle, at: value.startLocation)
                                        viewModel.updateResizeSelection(to: value.location, within: bounds)
                                        return
                                    }

                                    // 文字缩放手柄
                                    if let textHandle = viewModel.selectedTextResizeHandle,
                                       abs(value.startLocation.x - textHandle.x) <= 8,
                                       abs(value.startLocation.y - textHandle.y) <= 8 {
                                        viewModel.beginTextResize(at: value.startLocation)
                                        return
                                    }
                                    
                                    if rect.contains(value.startLocation),
                                       viewModel.annotationID(at: value.startLocation) == nil {
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
                                if viewModel.currentAnnotation == nil {
                                    viewModel.startDrawing(at: value.location)
                                }
                                viewModel.updateDrawing(to: value.location)
                            }
                        }
                    }
                    .onEnded { value in
                        if viewModel.state == .selecting {
                            viewModel.endSelection()
                        } else if viewModel.state == .editing || viewModel.state == .longCaptureReady {
                            
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
                                if viewModel.activeSelectionHandle != nil {
                                    viewModel.endResizeSelection()
                                }
                                viewModel.currentPoint = nil
                            }
                            // Drawing Mode
                            else if viewModel.state == .editing {
                                if viewModel.currentAnnotation != nil {
                                    viewModel.endDrawing()
                                }
                            }
                        }
                    }
            )
        }
        .background(Color.clear)
    }
    
    // Calculate toolbar position based on selection and screen bounds
    func calculateToolbarPosition(screenSize: CGSize) -> CGPoint {
        let rect = viewModel.selectionRect
        let padding: CGFloat = 10
        let toolbarHeight: CGFloat = 80 // Increased height for color picker
        
        var y = rect.maxY + padding + toolbarHeight / 2
        
        // If toolbar would be off-screen at bottom, move it above selection
        if y > screenSize.height - 80 {
            y = rect.minY - padding - toolbarHeight / 2
        }
         
        return CGPoint(x: rect.midX, y: y)
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
        if annotation.type == .mosaic {
            let blockSize = max(annotation.lineWidth * 0.8, 10)
            let rect: CGRect
            if annotation.points.isEmpty {
                rect = CGRect(from: annotation.startPoint, to: annotation.endPoint).standardized
            } else {
                let xs = annotation.points.map { $0.x } + [annotation.startPoint.x, annotation.endPoint.x]
                let ys = annotation.points.map { $0.y } + [annotation.startPoint.y, annotation.endPoint.y]
                let minX = xs.min() ?? 0
                let maxX = xs.max() ?? 0
                let minY = ys.min() ?? 0
                let maxY = ys.max() ?? 0
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
            }
            if rect.width <= 0 || rect.height <= 0 {
                return
            }
            let startX = (rect.minX / blockSize).rounded(.down) * blockSize
            let startY = (rect.minY / blockSize).rounded(.down) * blockSize
            if let bitmap = viewModel.previewBitmap, canvasSize.width > 0, canvasSize.height > 0 {
                let scaleX = CGFloat(bitmap.pixelsWide) / canvasSize.width
                let scaleY = CGFloat(bitmap.pixelsHigh) / canvasSize.height
                var y = startY
                while y < rect.maxY {
                    var x = startX
                    while x < rect.maxX {
                        let block = CGRect(x: x, y: y, width: blockSize, height: blockSize).intersection(rect)
                        if !block.isEmpty {
                            let rawSampleX = Int((x + blockSize * 0.5) * scaleX)
                            let rawSampleY = Int((y + blockSize * 0.5) * scaleY)
                            let sampleX = min(max(rawSampleX, 0), bitmap.pixelsWide - 1)
                            let flippedY = bitmap.pixelsHigh - 1 - rawSampleY
                            let sampleY = min(max(flippedY, 0), bitmap.pixelsHigh - 1)
                            if let nsColor = bitmap.colorAt(x: sampleX, y: sampleY) {
                                context.fill(Path(block), with: .color(Color(nsColor)))
                            } else {
                                context.fill(Path(block), with: .color(Color.black))
                            }
                        }
                        x += blockSize
                    }
                    y += blockSize
                }
            } else {
                var lightBlocks = Path()
                var darkBlocks = Path()
                var y = startY
                while y < rect.maxY {
                    var x = startX
                    while x < rect.maxX {
                        let block = CGRect(x: x, y: y, width: blockSize, height: blockSize).intersection(rect)
                        if !block.isEmpty {
                            let ix = Int(((x - startX) / blockSize).rounded(.down))
                            let iy = Int(((y - startY) / blockSize).rounded(.down))
                            if (ix + iy) % 2 == 0 {
                                lightBlocks.addRect(block)
                            } else {
                                darkBlocks.addRect(block)
                            }
                        }
                        x += blockSize
                    }
                    y += blockSize
                }
                context.fill(lightBlocks, with: .color(Color.black.opacity(0.65)))
                context.fill(darkBlocks, with: .color(Color.black.opacity(0.85)))
            }
            return
        }
        
        if annotation.type == .blur {
            var path = Path()
            if let first = annotation.points.first {
                path.move(to: first)
                for point in annotation.points.dropFirst() {
                    path.addLine(to: point)
                }
            } else {
                let rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
                path.addRect(rect)
            }
            let stroke = StrokeStyle(lineWidth: annotation.lineWidth, lineCap: .round, lineJoin: .round)
            let filled = path.strokedPath(stroke)
            context.fill(filled, with: .color(Color.black.opacity(0.28)))
            context.stroke(path, with: .color(Color.black.opacity(0.55)), style: stroke)
            return
        }
        
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
            let rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
            path.addRect(rect)
        case .arrow:
            path.move(to: annotation.startPoint)
            path.addLine(to: annotation.endPoint)
            // Draw rudimentary arrow head
            // ... (keep existing)
            let start = annotation.startPoint
            let end = annotation.endPoint
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = 15.0
            let arrowAngle: CGFloat = .pi / 6
            let p1 = CGPoint(x: end.x - arrowLength * cos(angle - arrowAngle), y: end.y - arrowLength * sin(angle - arrowAngle))
            let p2 = CGPoint(x: end.x - arrowLength * cos(angle + arrowAngle), y: end.y - arrowLength * sin(angle + arrowAngle))
            path.move(to: end); path.addLine(to: p1)
            path.move(to: end); path.addLine(to: p2)
            
        case .ellipse:
            let rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
            path.addEllipse(in: rect)
        case .number:
            let radius = annotation.fontSize / 2 + 4
            let circleRect = CGRect(x: annotation.startPoint.x - radius, y: annotation.startPoint.y - radius, width: radius * 2, height: radius * 2)
            path.addEllipse(in: circleRect)
        case .mosaic, .blur:
            break
        case .text:
            break
        }

        if annotation.type != .text {
            context.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        }

        if annotation.type == .text && !annotation.text.isEmpty {
            let text = Text(annotation.text)
                .font(.system(size: annotation.fontSize, weight: .medium))
                .foregroundColor(annotation.color)
            context.draw(text, at: annotation.startPoint, anchor: .topLeading)
        }

        if annotation.type == .number && !annotation.text.isEmpty {
            let text = Text(annotation.text)
                .font(.system(size: annotation.fontSize, weight: .semibold))
                .foregroundColor(annotation.color)
            context.draw(text, at: annotation.startPoint, anchor: .center)
        }
    }

    func handlePosition(for handle: SelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .right:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .left:
            return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func selectionHandle(at point: CGPoint, in rect: CGRect, hitSize: CGFloat) -> SelectionHandle? {
        let half = hitSize / 2
        for handle in SelectionHandle.allCases {
            let position = handlePosition(for: handle, in: rect)
            if abs(point.x - position.x) <= half && abs(point.y - position.y) <= half {
                return handle
            }
        }
        return nil
    }
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
