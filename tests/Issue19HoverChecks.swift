import AppKit
import SwiftUI

@main struct Issue19HoverChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "LibreShot.Issue19.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let vm = OverlayViewModel(settings:SettingsService(defaults:defaults))
        vm.state = .editing
        vm.selectionRect = CGRect(x:0,y:0,width:800,height:600)
        vm.captureMode = .imageEditor // Empty space moves no crop in this mode.
        var failures = 0, count = 0
        func check(_ value:Bool, _ label:String) {
            count += 1; if !value { failures += 1 }
            print("\(value ? "PASS" : "FAIL"): \(label)")
        }
        let border = CGPoint(x:100,y:160)
        for type in [AnnotationType.rectangle,.ellipse,.arrow,.text,.number,.pen,.mosaic,.blur] {
            var a = Annotation(type:type,color:.red)
            a.startPoint = CGPoint(x:100,y:100); a.endPoint = CGPoint(x:260,y:220)
            a.text = "选择已有文字"
            let point:CGPoint
            switch type {
            case .rectangle,.ellipse: point = border
            case .arrow: point = CGPoint(x:180,y:160)
            case .text: point = CGPoint(x:110,y:110)
            case .number: point = a.startPoint
            case .pen: a.points = [CGPoint(x:100,y:160),CGPoint(x:260,y:160)]; point = CGPoint(x:180,y:160)
            default: point = CGPoint(x:180,y:160)
            }
            vm.annotations = [a]; vm.selectedAnnotationID = nil; vm.selectedTool = .text
            vm.clearAnnotationPress()
            check(vm.cursorStyle(at:point) == .move, "\(type) hover shows hand before selection")
            check(vm.annotationID(at:point) == a.id, "\(type) hover matches production hit geometry")
            _ = vm.handleAnnotationPressChanged(from:point,to:point)
            _ = vm.handleAnnotationPressEnded(from:point,to:point)
            vm.clearAnnotationPress()
            check(vm.selectedAnnotationID == a.id && vm.annotations.count == 1 && !vm.isEditingText,
                  "\(type) click selects existing annotation without creating text")
            vm.selectedAnnotationID = nil; vm.selectedTool = nil
            check(vm.cursorStyle(at:point) == .move, "\(type) selection mode hover shows hand")
            if type == .rectangle || type == .ellipse {
                vm.selectedTool = .rectangle
                check(vm.cursorStyle(at:CGPoint(x:180,y:160)) == .crosshair,
                      "\(type) empty interior stays available for drawing")
                vm.selectedAnnotationID = a.id
                check(vm.cursorStyle(at:CGPoint(x:180,y:160)) == .move,
                      "\(type) selected interior remains movable")
                check(vm.cursorStyle(at:CGPoint(x:100,y:100)) == .diagonalDown,
                      "\(type) resize handle takes precedence over hand")
            }
        }
        for tool in [AnnotationType.mosaic,.blur] {
            var brush = Annotation(type:tool,color:.red)
            brush.startPoint = CGPoint(x:100,y:160); brush.endPoint = CGPoint(x:260,y:160)
            brush.points = [brush.startPoint,brush.endPoint]; brush.lineWidth = 20
            vm.annotations = [brush]; vm.selectedAnnotationID = nil; vm.selectedTool = tool
            vm.setEffectDrawingMode(.brush,for:tool)
            let p = CGPoint(x:180,y:160)
            check(vm.cursorStyle(at:p) == .crosshair, "\(tool) brush hover keeps painting cursor")
            check(!vm.handleAnnotationPressChanged(from:p,to:p), "\(tool) brush press is not intercepted by selection")
            vm.clearAnnotationPress()
            vm.selectedTool = nil
            check(vm.cursorStyle(at:p) == .crosshair, "\(tool) unselected brush does not gain new hover hand")
            vm.startDrawing(at:p)
            check(vm.selectedAnnotationID == brush.id, "\(tool) explicit Select/Move still selects brush")
            check(vm.cursorStyle(at:p) == .move, "\(tool) explicitly selected brush remains movable")
        }
        print("RESULT: \(count) checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
