import AppKit
import SwiftUI

@main struct Issue23Checks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "LibreShot.Issue23.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        settings.setToolbarItem(.select, visible: false)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 100, y: 100, width: 700, height: 500)
        var failures = 0
        func check(_ result: Bool, _ label: String) {
            if !result { failures += 1 }
            print("\(result ? "PASS" : "FAIL"): \(label)")
        }
        model.selectTool(.text)
        model.startTextInput(at: CGPoint(x: 150, y: 150))
        model.editingTextContent = "已有文字"
        model.commitTextInput()
        check(model.annotations.count == 1 && model.selectedTool == .text,
              "committing text retains the text tool even with Select hidden")
        model.selectTool(.text)
        model.startTextInput(at: CGPoint(x: 400, y: 250))
        model.commitTextInput()
        check(model.annotations.count == 1 && !model.isEditingText && model.selectedTool == .text,
              "empty input is cancelled without switching tool or creating an annotation")
        model.selectTool(nil)
        let original = model.selectionRect
        model.beginMoveSelection(at: CGPoint(x: 400, y: 350))
        model.updateMoveSelection(to: CGPoint(x: 450, y: 390), within: CGRect(x: 0, y: 0, width: 1200, height: 900))
        check(!model.isMovingSelection && model.selectionRect == original,
              "dragging empty crop interior does not move the capture")
        model.endMoveSelection()

        let outside = CGPoint(x: 600, y: 400)
        model.selectTool(.text)
        model.startTextInput(at: CGPoint(x: 350, y: 200))
        check(model.handleTextInputPress(from: outside) && model.didCommitTextOnPress &&
              !model.isEditingText && model.selectedTool == .text,
              "outside press cancels empty input and consumes the gesture")
        check(model.handleTextInputPress(from: outside) && !model.isEditingText,
              "subsequent drag callbacks cannot reopen the input")
        model.endTextInputPress()
        model.startTextInput(at: outside)
        check(model.isEditingText && model.editingTextPosition == outside,
              "the next separate click starts a new input")
        model.editingTextContent = "第二段文字"
        _ = model.handleTextInputPress(from: CGPoint(x: 400, y: 450))
        model.endTextInputPress()
        check(model.annotations.count == 2 && model.selectedTool == .text,
              "outside press commits nonempty input exactly once")
        let second = model.annotations.last!
        model.startTextEdit(annotationID: second.id)
        model.editingTextContent = "修改文字"
        model.commitTextInput()
        model.undoLastAnnotation()
        check(model.annotations.last == second && model.selectedTool == .text,
              "reediting text retains placement and participates in undo")
        model.startTextInput(at: CGPoint(x: 400, y: 450))
        model.selectTool(.arrow)
        check(!model.isEditingText && model.selectedTool == .arrow,
              "explicit tool changes still cancel unfinished input")
        model.selectTool(nil)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
        for point in [CGPoint(x: 100, y: 240), CGPoint(x: 800, y: 240),
                      CGPoint(x: 240, y: 100), CGPoint(x: 240, y: 600), CGPoint(x: 97, y: 240)] {
            model.selectionRect = original
            let beforeText = model.annotations[0].startPoint
            check(model.canMoveSelection(from: point) && model.cursorStyle(at: point) == .move,
                  "border \(point) advertises crop movement")
            model.beginMoveSelection(at: point)
            model.updateMoveSelection(to: CGPoint(x: point.x + 30, y: point.y + 20), within: bounds)
            check(model.selectionRect.origin == CGPoint(x: original.minX + 30, y: original.minY + 20) &&
                  model.annotations[0].startPoint == CGPoint(x: beforeText.x + 30, y: beforeText.y + 20),
                  "border movement translates crop and annotations together")
            model.updateMoveSelection(to: CGPoint(x: point.x - 10000, y: point.y - 10000), within: bounds)
            check(model.selectionRect.origin == .zero, "border movement clamps to screen")
            model.endMoveSelection()
        }
        model.selectionRect = original
        for handle in SelectionHandle.allCases {
            let point = handle.position(in: original)
            check(!model.canMoveSelection(from: point), "resize handle \(handle) has priority over movement")
            check(model.handleSelectionResizeDrag(from: point, to: CGPoint(x: point.x + 15, y: point.y + 15), within: bounds),
                  "resize handle \(handle) still resizes")
            model.endResizeSelection()
            model.selectionRect = original
        }
        model.captureMode = .imageEditor
        check(!model.canMoveSelection(from: CGPoint(x: 100, y: 240)), "image editor never moves the document crop")
        model.captureMode = .normal
        model.state = .longCaptureReady
        check(model.canMoveSelection(from: CGPoint(x: 100, y: 240)), "long capture ready supports border movement")

        let expected: [ToolbarItem] = [.select, .pen, .rectangle, .ellipse, .arrow, .text, .number, .mosaic, .blur,
                                     .style, .longCapture, .ocr, .translate, .undo, .cancel, .complete, .pin, .save, .saveAs]
        check(ToolbarConfiguration().orderedItems == expected && Set(expected) == Set(ToolbarItem.allCases),
              "factory tool order matches Issue 24 screenshot and includes every tool")
        let saved = ToolbarItem.allCases.reversed().map(\.rawValue)
        defaults.set(saved, forKey: "toolbarItemOrder")
        check(SettingsService(defaults: defaults).toolbarConfiguration.orderedItems.map(\.rawValue) == saved &&
              !SettingsService(defaults: defaults).toolbarConfiguration.isVisible(.select),
              "upgrade preserves existing custom order and hidden Select")
        let reloaded = SettingsService(defaults: defaults)
        reloaded.restoreDefaultToolbar()
        check(SettingsService(defaults: defaults).toolbarConfiguration.visibleItems == expected,
              "reset uses new default order and restores visibility")

        // Exercise the actual NSTextInputClient composition path, without a Chinese IME dependency.
        var text = ""
        var measured = CGSize.zero
        let editor = InlineTextEditor(text: Binding(get: { text }, set: { text = $0 }),
                                      fontSize: 24, color: .red, cursorAtEnd: false,
                                      onSizeChange: { measured = $0 })
        let view = InlineTextEditor.makeTextView(fontSize: 24, isNumber: false, color: .red)
        let coordinator = editor.makeCoordinator()
        coordinator.attach(to: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 250),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        editor.reportSize(view)
        let initial = measured
        view.setMarkedText("zhongwenpinyinshurukuang", selectedRange: NSRange(location: 23, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.layoutManager!.ensureLayout(for: view.textContainer!)
        let width = ceil(view.layoutManager!.usedRect(for: view.textContainer!).maxX)
        check(view.hasMarkedText() && width > initial.width && measured.width >= width,
              "marked pinyin grows the reported editor width before confirmation (\(measured.width)/\(width))")
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        check(view.hasMarkedText() && measured.width < width && measured.width > initial.width,
              "composition backspace shrinks width without prematurely confirming text")
        view.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
        check(!view.hasMarkedText() && view.string == "中文" && text == "中文" &&
              measured.width == ceil(view.layoutManager!.usedRect(for: view.textContainer!).maxX),
              "confirming candidate synchronizes text and final dimensions")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.setMarkedText("\npinyin", selectedRange: NSRange(location: 7, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        check(view.hasMarkedText() && measured.height > initial.height, "multiline marked text also updates height")
        view.unmarkText()
        check(!view.hasMarkedText(), "unmarking preserves native composition completion")
        window.orderOut(nil)
        print("RESULT: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
