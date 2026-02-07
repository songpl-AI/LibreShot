import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                            // Highlight selected annotation
                            if annotation.id == viewModel.selectedAnnotationID {
                                // Draw selection halo/border
                                let rect: CGRect
                                if annotation.type == .text {
                                     // Approx text rect for halo
                                     let width = CGFloat(annotation.text.count) * annotation.fontSize * 0.6
                                     let height = annotation.fontSize * 1.5
                                     rect = CGRect(x: annotation.startPoint.x, y: annotation.startPoint.y, width: width, height: height)
                                } else {
                                     rect = CGRect(from: annotation.startPoint, to: annotation.endPoint)
                                }
                                
                                // Draw Halo
                                let haloPath = Path(rect.insetBy(dx: -5, dy: -5))
                                context.stroke(haloPath, with: .color(.blue.opacity(0.5)), lineWidth: 2)
                            }
                            
                            drawAnnotation(context: context, annotation: annotation)
                        }
                        // Draw current annotation being dragged
                        if let current = viewModel.currentAnnotation {
                            drawAnnotation(context: context, annotation: current)
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
                            .stroke(Color.white, lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                        
                        if viewModel.state == .editing && viewModel.selectedTool == nil {
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
                        
                    // Text Input Overlay
                    if viewModel.isEditingText {
                        TextField("输入文字", text: $viewModel.editingTextContent, onCommit: {
                            viewModel.commitTextInput()
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: viewModel.selectedColor == .clear ? 24 : 24, weight: .medium)) // Use actual font size logic if bound
                        // Note: For now using binding to VM content.
                        .font(.system(size: 24)) // Todo: Bind to viewModel.activeFontSize
                        .foregroundColor(viewModel.selectedColor)
                        .padding(4)
                        .background(Color.black.opacity(0.6)) // Darker background for visibility
                        .cornerRadius(4)
                        .frame(width: 200)
                        .position(viewModel.editingTextPosition)
                        .onSubmit {
                            viewModel.commitTextInput()
                        }
                    }
                }
            }
            .coordinateSpace(name: "overlay")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))
                    .onChanged { value in
                        if viewModel.isEditingText {
                            // Click outside commits text
                            viewModel.commitTextInput()
                            return
                        }
                        
                        if viewModel.state == .idle || viewModel.state == .selecting {
                            if viewModel.state != .selecting {
                                viewModel.startSelection(at: value.startLocation)
                            }
                            viewModel.updateSelection(to: value.location)
                        } else if viewModel.state == .editing {
                            // 1. Text Tool Logic
                            if viewModel.selectedTool == .text {
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
                                    
                                    if rect.contains(value.startLocation),
                                       viewModel.annotationID(at: value.startLocation) == nil {
                                        viewModel.beginMoveSelection(at: value.startLocation)
                                        viewModel.updateMoveSelection(to: value.location, within: bounds)
                                        return
                                    }
                                    
                                    viewModel.startDrawing(at: value.location)
                                } else {
                                    if viewModel.isMovingSelection {
                                        viewModel.updateMoveSelection(to: value.location, within: bounds)
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
                            if viewModel.selectedTool != nil {
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
                        } else if viewModel.state == .editing {
                            
                            // Text Tool Click
                            if viewModel.selectedTool == .text {
                                if !viewModel.isEditingText {
                                    // Check distance to ensure it was a click, not a drag attempt
                                    if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                                        viewModel.startTextInput(at: value.location)
                                    }
                                }
                            } 
                            // Selection Mode
                            else if viewModel.selectedTool == nil {
                                if viewModel.isMovingSelection {
                                    viewModel.endMoveSelection()
                                }
                                if viewModel.activeSelectionHandle != nil {
                                    viewModel.endResizeSelection()
                                }
                                viewModel.currentPoint = nil
                            }
                            // Drawing Mode
                            else {
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

    func drawAnnotation(context: GraphicsContext, annotation: Annotation) {
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
