import AppKit
import SwiftUI

@main
struct ToolPropertiesChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor
    static func main() throws {
        let suite = "LibreShot.ToolProperties.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("outline", forKey: "numberAnnotationStyle")
        defaults.set(["cancel", "style", "arrow", "complete"], forKey: "toolbarItemOrder")
        defaults.set(["style"], forKey: "hiddenToolbarItems")
        defaults.set(try JSONEncoder().encode(["style": EditorShortcut(keyCode: 3, modifiers: 0)]), forKey: "editorShortcuts")
        let settings = SettingsService(defaults: defaults)
        let vm = OverlayViewModel(settings: settings)
        vm.state = .editing
        vm.selectionRect = CGRect(x: 0, y: 0, width: 500, height: 400)
        require(settings.editorShortcuts["style"] == nil, "Retired gear shortcut does not reserve a key")
        require(!vm.visibleToolbarItems.contains(.style), "Legacy gear entry is retired")
        require(Array(vm.visibleToolbarItems.prefix(4)) == [.cancel, .arrow, .complete, .select], "Upgrade retains remaining custom order")
        require(vm.propertyTool == nil, "No properties without a tool or selected object")
        vm.selectTool(.rectangle)
        vm.setColor(.blue)
        vm.setLineWidth(8)
        vm.startDrawing(at: CGPoint(x: 40, y: 40))
        vm.updateDrawing(to: CGPoint(x: 200, y: 180))
        vm.endDrawing()
        require(vm.annotations.count == 1, "Rectangle must be created")
        let rectangle = vm.annotations[0]
        require(rectangle.lineWidth == 8, "Drawing must use configured stroke width")
        vm.selectTool(.arrow)
        require(vm.currentToolStyle.lineWidth == 3, "Arrow width must be independent")
        vm.setLineWidth(5)
        vm.selectTool(.rectangle)
        require(vm.currentToolStyle.lineWidth == 8, "Switching tools restores defaults")
        vm.selectedAnnotationID = rectangle.id
        vm.setLineWidth(12)
        require(vm.annotations[0].lineWidth == 12, "Selected shape updates")
        vm.undoLastAnnotation()
        require(vm.annotations[0] == rectangle, "Style edit must undo without removing shape")
        require(vm.currentToolStyle.lineWidth == 8, "Panel reads restored object")
        require(settings.annotationStyle(for: .rectangle).lineWidth == 12, "Canvas undo leaves next-object preference intact")
        vm.restoreCurrentToolDefaults()
        require(vm.annotations[0].lineWidth == 3, "Reset updates selected object")
        vm.undoLastAnnotation()
        require(vm.annotations[0] == rectangle, "Reset is one undoable edit")
        require(settings.annotationStyle(for: .arrow).lineWidth == 5, "Reset affects only current tool")
        vm.selectTool(.text)
        vm.setFontSize(40)
        vm.selectTool(.number)
        require(vm.currentToolStyle.numberStyle == .outline, "Legacy sequence style retained")
        vm.setFontSize(32)
        vm.setNumberStyle(.filled)
        vm.placeNumber(at: CGPoint(x: 250, y: 150))
        let number = vm.annotations.last!
        require(number.fontSize == 32 && number.numberStyle == .filled, "Number uses its own properties")
        vm.selectedAnnotationID = number.id
        vm.setFontSize(48)
        vm.undoLastAnnotation()
        require(vm.annotations.last == number, "Number font edit undoes")
        vm.selectTool(.mosaic)
        vm.setEffectDrawingMode(.brush, for: .mosaic)
        vm.setEffectValue(60, parameter: "width")
        vm.setEffectValue(24, parameter: "block")
        vm.selectTool(.blur)
        require(vm.effectValue("width") == 20, "Effect brush widths are independent")
        vm.setEffectValue(8, parameter: "radius")
        let relaunched = SettingsService(defaults: defaults)
        let second = OverlayViewModel(settings: relaunched)
        second.selectTool(.text)
        require(second.currentToolStyle.fontSize == 40, "Text size survives restart")
        second.selectTool(.number)
        require(second.currentToolStyle.fontSize == 48, "Number size survives restart independently")
        second.selectTool(.mosaic)
        require(second.effectDrawingMode(for: .mosaic) == .brush && second.effectValue("width") == 60 && second.effectValue("block") == 24, "Mosaic properties survive restart")
        second.selectTool(.blur)
        require(second.effectValue("radius") == 8 && second.effectValue("width") == 20, "Blur properties survive independently")
        second.selectTool(.rectangle)
        require(second.currentToolStyle == .factory(for: .rectangle), "Reset survives restart")
        // Merely selecting a differently styled object must not overwrite tool defaults.
        var old = Annotation(type: .rectangle, color: .green)
        old.lineWidth = 2
        second.annotations = [old]
        second.selectedAnnotationID = old.id
        require(second.currentToolStyle.lineWidth == 2, "Panel shows selected object's properties")
        require(relaunched.annotationStyle(for: .rectangle).lineWidth == 3, "Reading selected properties does not persist them")
        second.selectTool(.arrow)
        second.setLineWidth(1000)
        require(second.currentToolStyle.lineWidth == 20, "Invalid values are bounded")
        for width: CGFloat in [220, 400, 900] {
            let screen = CGSize(width: width, height: 700)
            for tool in [AnnotationType.arrow, .text, .number, .mosaic, .blur] {
                second.selectTool(tool)
                let propertySize = ToolPropertyBarView.size(for: second, availableWidth: width - 20)
                require(propertySize.width <= width - 20 && propertySize.height > 0, "Automatic property bar fits narrow widths")
                let layout = ToolbarLayout(items: second.visibleToolbarItems, availableWidth: width - 20)
                for y: CGFloat in [20, 300, 560] {
                    let crop = CGRect(x: 20, y: y, width: width - 40, height: 100)
                    let frame = layout.frame(selection: crop, screenSize: screen, accessorySize: CGSize(width: propertySize.width, height: propertySize.height + 8))
                    require(frame.minX >= 10 && frame.maxX <= width - 10 && frame.minY >= 10 && frame.maxY <= 690, "Toolbar and properties stay inside screen edges")
                    require(frame.contains(CGPoint(x: frame.midX, y: frame.maxY - 1)), "Property row belongs to toolbar hit exclusion")
                }
            }
        }
        second.selectTool(nil)
        require(ToolPropertyBarView.size(for: second, availableWidth: 400) == .zero, "Property bar hides when selection is cleared")
        print("PASS: automatic properties, legacy gear migration, narrow widths and edge placement")
        print("PASS: independent tool defaults, legacy migration, drawing, selected editing, undo/reset and relaunch persistence")
    }
}
