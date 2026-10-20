import AppKit
import SwiftUI

@main struct AnnotationHoverChecks {
    @MainActor static func main() {
        let suite = "LibreShot.Hover.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)

        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 40, y: 40, width: 500, height: 400)

        var rectangle = Annotation(type: .rectangle, color: .red)
        rectangle.startPoint = CGPoint(x: 100, y: 100)
        rectangle.endPoint = CGPoint(x: 220, y: 200)

        var text = Annotation(type: .text, color: .blue)
        text.startPoint = CGPoint(x: 250, y: 100)
        text.text = "Hover"
        text.fontSize = 24

        var number = Annotation(type: .number, color: .green)
        number.startPoint = CGPoint(x: 400, y: 150)
        number.text = "1"
        number.fontSize = 16

        var pen = Annotation(type: .pen, color: .orange)
        pen.startPoint = CGPoint(x: 100, y: 300)
        pen.endPoint = CGPoint(x: 180, y: 320)
        pen.points = [pen.startPoint, pen.endPoint]
        pen.lineWidth = 4

        var effectBrush = Annotation(type: .mosaic, color: .black)
        effectBrush.startPoint = CGPoint(x: 300, y: 300)
        effectBrush.endPoint = CGPoint(x: 360, y: 340)
        effectBrush.points = [effectBrush.startPoint, effectBrush.endPoint]

        model.annotations = [rectangle, text, number, pen, effectBrush]

        let rectangleEdge = CGPoint(x: 100, y: 150)
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == rectangle.id, "Hover finds the rectangle stroke")

        model.updateHover(at: CGPoint(x: 255, y: 110))
        precondition(model.hoveredAnnotationID == text.id, "Hover finds committed text")

        model.updateHover(at: number.startPoint)
        precondition(model.hoveredAnnotationID == number.id, "Hover finds a number circle")

        model.updateHover(at: CGPoint(x: 140, y: 310))
        precondition(model.hoveredAnnotationID == nil, "Pen ink is committed and has no hover affordance")

        model.updateHover(at: CGPoint(x: 330, y: 320))
        precondition(model.hoveredAnnotationID == nil, "Effect-brush strokes keep their painting affordance")

        model.updateHover(at: CGPoint(x: 480, y: 380))
        precondition(model.hoveredAnnotationID == nil, "Blank canvas clears hover")

        model.updateHover(at: nil)
        precondition(model.hoveredAnnotationID == nil, "Leaving the overlay clears hover")

        let annotationCount = model.annotations.count
        model.selectedAnnotationID = rectangle.id
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == nil, "Selected annotation does not repeat hover feedback")
        model.selectedAnnotationID = nil
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == rectangle.id, "Hover returns after deselection")

        model.selectedTool = .text
        model.startTextInput(at: CGPoint(x: 470, y: 300))
        precondition(model.isEditingText)
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == nil, "Text editing suppresses hover feedback")
        model.cancelTextInput()
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == rectangle.id, "Hover returns after text editing ends")

        model.state = .idle
        model.updateHover(at: rectangleEdge)
        precondition(model.hoveredAnnotationID == nil, "Hover is editing-only")
        precondition(model.annotations.count == annotationCount, "Hover never changes annotations")
        precondition(model.selectedAnnotationID == nil, "Hover never changes selection")

        let overlap = OverlayViewModel(settings: settings)
        overlap.state = .editing
        overlap.selectionRect = CGRect(x: 40, y: 40, width: 500, height: 400)
        var lower = Annotation(type: .rectangle, color: .red)
        lower.startPoint = CGPoint(x: 120, y: 120)
        lower.endPoint = CGPoint(x: 260, y: 240)
        var upper = Annotation(type: .rectangle, color: .blue)
        upper.startPoint = CGPoint(x: 120, y: 120)
        upper.endPoint = CGPoint(x: 260, y: 240)
        overlap.annotations = [lower, upper]
        overlap.updateHover(at: CGPoint(x: 120, y: 180))
        precondition(overlap.hoveredAnnotationID == upper.id, "Hover uses the same topmost order as selection")

        print("PASS: hover marks the topmost editable annotation, clears on selection/editing, and skips pen/effect ink")
    }
}
