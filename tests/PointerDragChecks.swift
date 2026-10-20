import AppKit
import SwiftUI

@main struct PointerDragChecks {
    @MainActor static func main() {
        let suite = "LibreShot.PointerDrag.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)

        func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Annotation {
            var annotation = Annotation(type: .rectangle, color: .red)
            annotation.startPoint = CGPoint(x: x, y: y)
            annotation.endPoint = CGPoint(x: x + width, y: y + height)
            annotation.lineWidth = 3
            return annotation
        }

        func model(_ annotations: [Annotation], selection: CGRect = CGRect(x: 40, y: 40, width: 400, height: 300)) -> OverlayViewModel {
            let model = OverlayViewModel(settings: settings)
            model.state = .editing
            model.selectionRect = selection
            model.annotations = annotations
            return model
        }

        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

        // Rectangle interior: press and drag without a prior click.
        let rect = rectangle(100, 100, 200, 120)
        let interiorModel = model([rect])
        let interiorStart = CGPoint(x: 200, y: 160)
        let interiorEnd = CGPoint(x: 220, y: 175)
        precondition(interiorModel.handleSelectedShapeDrag(from: interiorStart, to: interiorStart, within: bounds),
                     "First callback starts a pointer drag from the rectangle interior")
        precondition(interiorModel.selectedAnnotationID == rect.id, "Rectangle interior press selects the shape")
        precondition(interiorModel.selectedTool == nil, "Pointer mode stays active after selecting a shape")
        precondition(interiorModel.annotations[0].startPoint == rect.startPoint, "No movement before the pointer moves")
        precondition(interiorModel.handleSelectedShapeDrag(from: interiorStart, to: interiorEnd, within: bounds))
        precondition(interiorModel.annotations[0].startPoint == CGPoint(x: 120, y: 115),
                     "Rectangle moves by the pointer delta without a preliminary click")
        precondition(interiorModel.selectionRect == CGRect(x: 40, y: 40, width: 400, height: 300),
                     "Dragging a shape does not move the capture selection")
        interiorModel.endSelectedShapeDrag()
        interiorModel.undoLastAnnotation()
        precondition(interiorModel.annotations[0].startPoint == rect.startPoint,
                     "One undo restores the whole pointer drag")

        // Rectangle border away from its resize handles remains directly draggable.
        let borderModel = model([rect])
        let borderStart = CGPoint(x: 160, y: 100)
        precondition(borderModel.handleSelectedShapeDrag(from: borderStart, to: CGPoint(x: 180, y: 112), within: bounds))
        precondition(borderModel.annotations[0].startPoint == CGPoint(x: 120, y: 112),
                     "Rectangle border drags on the first gesture")

        // Ellipse interior counts as a grab target, matching the hand cursor.
        var ellipse = Annotation(type: .ellipse, color: .blue)
        ellipse.startPoint = CGPoint(x: 100, y: 100)
        ellipse.endPoint = CGPoint(x: 300, y: 220)
        let ellipseModel = model([ellipse])
        precondition(ellipseModel.handleSelectedShapeDrag(from: CGPoint(x: 190, y: 155),
                                                          to: CGPoint(x: 205, y: 170), within: bounds),
                     "Ellipse interior starts a pointer drag")
        precondition(ellipseModel.annotations[0].startPoint == CGPoint(x: 115, y: 115),
                     "Ellipse moves by the pointer delta")

        // Pressing blank space still moves the whole capture.
        let blankModel = model([rect])
        let blankStart = CGPoint(x: 420, y: 320)
        precondition(!blankModel.handleSelectedShapeDrag(from: blankStart, to: CGPoint(x: 430, y: 330), within: bounds),
                     "Blank space is not a shape target")
        precondition(blankModel.handleSelectionMoveDrag(from: blankStart, to: CGPoint(x: 430, y: 330), within: bounds),
                     "Blank space keeps moving the capture")
        precondition(blankModel.selectionRect.origin == CGPoint(x: 50, y: 50),
                     "Capture moves from blank space")
        precondition(blankModel.annotations[0].startPoint == CGPoint(x: 110, y: 110),
                     "Annotations follow the capture move")

        // Consecutive shapes can be grabbed without reselecting a tool.
        let first = rectangle(100, 100, 120, 80)
        let second = rectangle(300, 100, 120, 80)
        let multiModel = model([first, second])
        precondition(multiModel.handleSelectedShapeDrag(from: CGPoint(x: 160, y: 140),
                                                        to: CGPoint(x: 170, y: 150), within: bounds))
        multiModel.endSelectedShapeDrag()
        precondition(multiModel.selectedAnnotationID == first.id)
        precondition(multiModel.handleSelectedShapeDrag(from: CGPoint(x: 360, y: 140),
                                                        to: CGPoint(x: 380, y: 160), within: bounds))
        precondition(multiModel.selectedAnnotationID == second.id, "A second shape selects directly")
        precondition(multiModel.selectedTool == nil, "Pointer mode survives consecutive shape drags")
        precondition(multiModel.annotations[1].startPoint == CGPoint(x: 320, y: 120),
                     "The second shape moves without clicking first")

        // Text keeps click-to-edit: the pointer must not steal the press.
        var text = Annotation(type: .text, color: .green)
        text.startPoint = CGPoint(x: 300, y: 220)
        text.text = "Pointer"
        text.fontSize = 24
        let textModel = model([text])
        let textPoint = CGPoint(x: 305, y: 230)
        precondition(!textModel.handleSelectedShapeDrag(from: textPoint, to: CGPoint(x: 315, y: 240), within: bounds),
                     "Text is not grabbed by the shape drag path")
        precondition(textModel.selectedAnnotationID == nil && textModel.selectedTool == nil,
                     "Text press is left for the existing click-to-edit path")
        textModel.startDrawing(at: textPoint)
        precondition(textModel.selectedAnnotationID == text.id && textModel.selectedTool == nil,
                     "Pointer click still selects text and keeps pointer mode")

        // An active drawing tool still draws a new shape inside an existing one.
        let drawingModel = model([rect])
        drawingModel.selectedTool = .rectangle
        drawingModel.handleDrawingDrag(from: CGPoint(x: 180, y: 150), to: CGPoint(x: 230, y: 200))
        drawingModel.endDrawing()
        precondition(drawingModel.annotations.count == 2, "Drawing tools still create annotations inside existing shapes")

        print("PASS: pointer press-and-drag moves shapes immediately, blank space moves the capture, and text/drawing keep their paths")
    }
}
