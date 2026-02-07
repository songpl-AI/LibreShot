import SwiftUI

struct OverlayView: View {
    @StateObject var viewModel = OverlayViewModel()
    
    // We pass callbacks to VM for it to trigger
    var onCapture: (CGRect, [Annotation], CaptureAction) -> Void
    var onCancel: () -> Void
    
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
                // We clip drawing to selectionRect to look cleaner
                if viewModel.state == .editing {
                    Canvas { context, size in
                        // Draw existing annotations
                        for annotation in viewModel.annotations {
                            drawAnnotation(context: context, annotation: annotation)
                        }
                        // Draw current annotation being dragged
                        if let current = viewModel.currentAnnotation {
                            drawAnnotation(context: context, annotation: current)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                    // Optional: Clip to selection? Or allow drawing outside?
                    // Standard screenshot tools allow drawing slightly outside or clamp.
                    // Let's allow full screen drawing for now, but usually we want to crop later.
                }
                
                // Layer 3: Selection Border
                if viewModel.selectionRect != .zero {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: viewModel.selectionRect.width, height: viewModel.selectionRect.height)
                        .position(x: viewModel.selectionRect.midX, y: viewModel.selectionRect.midY)
                        .allowsHitTesting(false)
                }
                
                // Layer 4: Toolbar (Only in Editing mode)
                if viewModel.state == .editing {
                    EditorToolbarView(viewModel: viewModel)
                        .position(x: toolbarPosition.x, y: toolbarPosition.y)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if viewModel.state == .idle || viewModel.state == .selecting {
                            if viewModel.state != .selecting {
                                viewModel.startSelection(at: value.startLocation)
                            }
                            viewModel.updateSelection(to: value.location)
                        } else if viewModel.state == .editing {
                            // If tool selected, draw
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
                            if viewModel.selectedTool != nil {
                                viewModel.endDrawing()
                            }
                        }
                    }
            )
        }
        .background(Color.clear)
        .onAppear {
            NSCursor.crosshair.push()
            // Link callbacks
            viewModel.onCapture = onCapture
            viewModel.onCancel = onCancel
        }
        .onDisappear {
            NSCursor.pop()
        }
        // Handle Escape key
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            onCancel() // Simple cancel on resign
        }
    }
    
    // Calculate toolbar position (below selection, or above if near bottom)
    var toolbarPosition: CGPoint {
        let rect = viewModel.selectionRect
        let padding: CGFloat = 10
        let toolbarHeight: CGFloat = 50 // Est
        
        // Default: Below
        var y = rect.maxY + padding + toolbarHeight / 2
        
        // If too close to bottom, put above
        if let screen = NSScreen.main {
            if y > screen.frame.height - 50 {
                y = rect.minY - padding - toolbarHeight / 2
            }
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
            // Simple line for now, can add arrow head later
            path.move(to: annotation.startPoint)
            path.addLine(to: annotation.endPoint)
        }
        
        if annotation.type == .rectangle {
            context.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        } else {
            context.stroke(path, with: .color(annotation.color), lineWidth: annotation.lineWidth)
        }
    }
}
