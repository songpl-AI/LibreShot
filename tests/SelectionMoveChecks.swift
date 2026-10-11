import AppKit
import SwiftUI

@main struct SelectionMoveChecks {
    @MainActor static func main() {
        let suite = "LibreShot.SelectionMove.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        func model() -> OverlayViewModel {
            let result = OverlayViewModel(settings: settings)
            result.state = .editing
            result.selectionRect = CGRect(x: 100, y: 100, width: 300, height: 200)
            result.selectTool(nil)
            return result
        }
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 700)
        let crop = model()
        let edge = CGPoint(x: 100, y: 150)
        precondition(crop.acceptsOverlayDrag(from: edge, excluding: CGRect(x: 100, y: 308, width: 300, height: 40)))
        crop.beginMoveSelection(at: edge)
        crop.updateMoveSelection(to: CGPoint(x: 100, y: 0), within: bounds)
        // The toolbar follows the crop; a drag begun on the canvas must retain ownership.
        precondition(crop.acceptsOverlayDrag(from: edge, excluding: CGRect(x: 100, y: 140, width: 300, height: 40)),
                     "A following toolbar must not stop an active crop drag")
        crop.endMoveSelection()
        crop.endOverlayDrag()
        print("PASS: a following toolbar cannot steal a canvas drag")
        precondition(!crop.acceptsOverlayDrag(from: edge, excluding: CGRect(x: 100, y: 140, width: 300, height: 40)))
        precondition(!crop.acceptsOverlayDrag(from: edge, excluding: .zero), "A drag started on toolbar stays excluded")
        crop.endOverlayDrag()
        precondition(crop.acceptsOverlayDrag(from: edge, excluding: .zero), "Next drag gets a fresh down-point decision")
        crop.endOverlayDrag()
        let blank = model()
        precondition(blank.canMoveSelection(from: CGPoint(x: 200, y: 200)),
                     "Select mode must allow dragging the crop from blank interior")
        let start = CGPoint(x: 200, y: 200)
        precondition(blank.handleSelectionMoveDrag(from: start, to: CGPoint(x: 225, y: 230), within: bounds))
        precondition(blank.selectionRect.origin == CGPoint(x: 125, y: 130), "First callback with translation starts movement from pointer-down")
        _ = blank.handleSelectionMoveDrag(from: start, to: CGPoint(x: 300, y: 250), within: bounds)
        precondition(blank.selectionRect.origin == CGPoint(x: 200, y: 150), "Callbacks use absolute displacement without accumulating it")
        _ = blank.handleSelectionMoveDrag(from: start, to: CGPoint(x: 2000, y: 2000), within: bounds)
        precondition(blank.selectionRect.origin == CGPoint(x: 600, y: 500), "Crop clamps to screen while keeping its size")
        _ = blank.handleSelectionMoveDrag(from: start, to: CGPoint(x: 210, y: 210), within: bounds)
        precondition(blank.selectionRect.origin == CGPoint(x: 110, y: 110), "Movement continues when pointer returns from a screen edge")
        blank.endMoveSelection()
        print("PASS: blank interior, translated first callback, repeated updates and screen-edge return")

        let annotated = model()
        annotated.selectTool(.rectangle)
        annotated.handleDrawingDrag(from: CGPoint(x: 140, y: 140), to: CGPoint(x: 250, y: 180)); annotated.endDrawing()
        let rectangle = annotated.annotations[0]
        annotated.setLineWidth(9)
        annotated.selectTool(nil)
        let empty = CGPoint(x: 310, y: 220)
        precondition(annotated.handleSelectionMoveDrag(from: empty, to: CGPoint(x: 360, y: 250), within: bounds))
        precondition(annotated.annotations[0].startPoint == CGPoint(x: rectangle.startPoint.x + 50, y: rectangle.startPoint.y + 30), "Crop movement carries annotations with it")
        annotated.endMoveSelection()
        annotated.undoLastAnnotation()
        precondition(annotated.annotations[0].lineWidth == rectangle.lineWidth
            && annotated.annotations[0].startPoint == CGPoint(x: rectangle.startPoint.x + 50, y: rectangle.startPoint.y + 30),
            "Undo of a prior style edit must keep the moved crop's annotation coordinates")
        let stroke = CGPoint(x: annotated.annotations[0].startPoint.x + 30, y: annotated.annotations[0].startPoint.y)
        precondition(!annotated.canMoveSelection(from: stroke), "Visible annotation belongs to object editing")
        annotated.startDrawing(at: stroke)
        precondition(annotated.handleSelectedShapeDrag(from: stroke, to: CGPoint(x: stroke.x + 20, y: stroke.y + 20), within: bounds))
        let movedCrop = annotated.selectionRect
        annotated.endSelectedShapeDrag()
        precondition(annotated.selectionRect == movedCrop, "Object dragging leaves the crop fixed")
        for tool in AnnotationType.allCases {
            annotated.selectTool(tool)
            precondition(!annotated.handleSelectionMoveDrag(from: empty, to: CGPoint(x: empty.x + 30, y: empty.y + 30), within: bounds), "Drawing tools retain blank-drag gestures")
        }
        print("PASS: draw then move crop, carried annotations, object priority and continuous drawing")

        let click = model()
        let original = click.selectionRect
        var exports = 0
        click.onCapture = { _, _, _, _ in exports += 1 }
        precondition(click.beginConfirmationClick(at: start), "Blank interior still arms double-click completion")
        _ = click.handleSelectionMoveDrag(from: start, to: CGPoint(x: start.x + 2, y: start.y + 1), within: bounds)
        click.endMoveSelection()
        precondition(click.selectionRect == original && click.confirmDoubleClick(at: start) && exports == 1, "Click jitter does not move the crop or break completion")
        precondition(click.beginConfirmationClick(at: start))
        _ = click.handleSelectionMoveDrag(from: start, to: CGPoint(x: start.x + 30, y: start.y + 20), within: bounds)
        _ = click.handleSelectionMoveDrag(from: start, to: start, within: bounds)
        click.endMoveSelection()
        precondition(click.selectionRect == original && !click.confirmDoubleClick(at: start), "A drag out and back cannot become a completion click")
        for handle in SelectionHandle.allCases {
            precondition(!click.canMoveSelection(from: handle.position(in: original)), "Crop resize handles retain priority")
        }
        click.captureMode = .imageEditor
        precondition(!click.canMoveSelection(from: start), "Image editor never moves the document crop")
        click.captureMode = .normal; click.state = .longCaptureReady
        precondition(click.canMoveSelection(from: start), "Long capture selection allows blank movement before capture")
        print("PASS: click jitter, blank double-click completion, handle priority and editor boundaries")
    }
}
