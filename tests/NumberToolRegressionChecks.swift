import AppKit
import SwiftUI

@main
struct NumberToolRegressionChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite = "LibreShot.NumberTools.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        func model() -> OverlayViewModel {
            let m = OverlayViewModel(settings: settings)
            m.selectionRect = CGRect(x: 0, y: 0, width: 600, height: 500)
            m.state = .editing
            m.applyInitialTool()
            return m
        }
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                            windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                            isARepeat: false, keyCode: code)!
        }
        precondition(model().selectedTool == nil)
        settings.setDefaultEditorTool(.rectangle)
        precondition(SettingsService(defaults: defaults).defaultEditorTool == .rectangle)
        let crop = OverlayViewModel(settings: settings)
        crop.startSelection(at: CGPoint(x: 10, y: 10)); crop.updateSelection(to: CGPoint(x: 400, y: 400)); crop.endSelection()
        precondition(crop.selectedTool == .rectangle)
        let document = ImageEditorWindowController(image: NSImage(size: CGSize(width: 600, height: 500)), settings: settings)
        precondition(document.model.selectedTool == .rectangle)
        settings.setToolbarItem(.rectangle, visible: false)
        precondition(settings.defaultEditorTool == .select && model().selectedTool == nil)
        settings.setDefaultEditorTool(.save)
        precondition(settings.defaultEditorTool == .select)
        settings.setToolbarItem(.select, visible: false)
        settings.setDefaultEditorTool(.pen); settings.setDefaultEditorTool(.select)
        precondition(model().selectedTool == nil)
        defaults.set("translate", forKey: "defaultEditorTool")
        precondition(SettingsService(defaults: defaults).defaultEditorTool == .select)
        print("PASS: persisted default tool, capture/document consistency, hidden/action fallback")

        let m = model(); m.selectTool(.number)
        let p = CGPoint(x: 120, y: 120)
        m.placeNumber(at: p); m.placeNumber(at: CGPoint(x: 220, y: 120))
        precondition(m.annotations.map(\.text) == ["1", "2"])
        m.selectedAnnotationID = m.annotations.last!.id
        precondition(m.deleteSelectedAnnotation() && m.nextNumber == 2)
        m.undoLastAnnotation()
        precondition(m.annotations.map(\.text) == ["1", "2"] && m.nextNumber == 3)
        m.undoLastAnnotation()
        precondition(m.annotations.map(\.text) == ["1"] && m.nextNumber == 2)
        m.placeNumber(at: CGPoint(x: 220, y: 120)); m.placeNumber(at: CGPoint(x: 320, y: 120))
        m.selectedAnnotationID = m.annotations[0].id
        precondition(m.deleteSelectedAnnotation() && m.nextNumber == 4)
        precondition(m.annotations.map(\.text) == ["2", "3"])
        m.undoLastAnnotation()
        print("PASS: deletion, unchanged middle numbers and undo counter restoration")

        m.setColor(.blue); m.placeNumber(at: CGPoint(x: 420, y: 120))
        let blueID = m.annotations.last!.id
        m.startNumberEdit(annotationID: blueID)
        m.editingTextContent = "1"
        precondition(m.performEditorShortcut(key(36, "\r")))
        precondition(!m.isEditingText && m.nextNumber == 2 && m.annotations.last!.text == "1")
        m.placeNumber(at: CGPoint(x: 420, y: 220))
        precondition(m.annotations.last!.text == "2" && m.annotations.last!.color == .blue)
        m.undoLastAnnotation(); m.undoLastAnnotation()
        precondition(m.annotations.last!.text == "4" && m.nextNumber == 5)
        m.startNumberEdit(annotationID: blueID); m.editingTextContent = "123"
        m.commitTextInput()
        precondition(m.nextNumber == 124 && m.annotations.last!.text == "123")
        m.startNumberEdit(annotationID: blueID); m.editingTextContent = "0"; m.commitTextInput()
        precondition(m.isEditingText && m.nextNumber == 124 && m.annotations.last!.text == "123")
        precondition(m.performEditorShortcut(key(53, "\u{1b}")) && !m.isEditingText)
        m.startNumberEdit(annotationID: blueID); m.editingTextContent = "9999999999999999999999"; m.commitTextInput()
        precondition(m.isEditingText && m.annotations.last!.text == "123")
        m.cancelTextInput()
        print("PASS: independent color sequences, multi-digit editing, validation, Enter/Escape, undo")

        m.selectedAnnotationID = blueID
        let a = m.annotations.last!, handle = m.selectedTextResizeHandle!
        let target = CGPoint(x: a.startPoint.x + 2 * (handle.x - a.startPoint.x), y: a.startPoint.y + 2 * (handle.y - a.startPoint.y))
        precondition(m.handleTextResizeDrag(from: handle, to: target))
        m.endTextResize()
        precondition(abs(m.annotations.last!.fontSize - a.fontSize * 2) < 0.01)
        precondition(m.annotations.last!.startPoint == a.startPoint)
        precondition(m.annotations.last!.selectionBounds.width > a.selectionBounds.width)
        let scaled = m.annotations.last!
        m.selectedAnnotationID = nil; m.selectTool(.number); m.placeNumber(at: CGPoint(x: 420, y: 320))
        precondition(m.annotations.last!.fontSize == scaled.fontSize && m.annotations.last!.color == .blue && m.annotations.last!.text == "124")
        m.undoLastAnnotation(); m.undoLastAnnotation()
        precondition(m.annotations.last!.fontSize == a.fontSize && m.selectedNumberFontSize == a.fontSize && m.nextNumber == 124)
        precondition(a.numberRadius * 2 > a.textBoundingSize.width)
        precondition(a.containsSelectionPoint(CGPoint(x: a.startPoint.x + a.numberRadius - 1, y: a.startPoint.y)))
        print("PASS: center-anchored scaling, multi-digit bounds/hit, style inheritance and undo")

        // Exercise the same pointer routing as OverlayView, not only the direct edit API.
        let clicks = model(); clicks.selectTool(.number); clicks.placeNumber(at: p)
        let clickID = clicks.annotations[0].id
        for _ in 0..<2 {
            precondition(!clicks.handleSelectedShapeDrag(from: p, to: p, within: clicks.selectionRect))
            precondition(clicks.handleAnnotationPressChanged(from: p, to: p))
            precondition(clicks.handleAnnotationPressEnded(from: p, to: p))
            clicks.clearAnnotationPress()
        }
        precondition(clicks.isEditingNumber && clicks.editingTextAnnotationID == clickID && clicks.annotations.count == 1)
        precondition(settings.setEditorShortcut(EditorShortcut(keyCode: 18, modifiers: 0), for: .rectangle) == nil)
        clicks.editingTextContent = "123"
        precondition(!clicks.performEditorShortcut(key(18, "1"), textResponder: true))
        precondition(clicks.isEditingNumber && clicks.selectedTool == .number)
        var exported = false
        clicks.onCapture = { _, _, _, _ in exported = true }
        clicks.editingTextContent = "no"; clicks.confirmCopy()
        precondition(!exported && clicks.isEditingNumber)
        clicks.editingTextContent = "123"; clicks.confirmCopy()
        precondition(exported && clicks.annotations[0].text == "123")
        precondition(clicks.performEditorShortcut(key(18, "1")) && clicks.selectedTool == .rectangle)
        print("PASS: pointer double-click edits without duplicate; digits and invalid export stay in input")

        // Inspect actual exported pixels for a large multi-digit circle.
        var exportedNumber = clicks.annotations[0]
        exportedNumber.fontSize = 64
        let base = NSImage(size: CGSize(width: 600, height: 500))
        base.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 500).fill(); base.unlockFocus()
        let image = CaptureService.shared.composite(image: base, annotations: [exportedNumber])
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let sx = CGFloat(cg.width) / 600, sy = CGFloat(cg.height) / 500
        var colored = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.greenComponent < 0.8 {
                    colored = colored.union(CGRect(x: CGFloat(x)/sx, y: CGFloat(y)/sy, width: 1/sx, height: 1/sy))
                }
            }
        }
        let expected = exportedNumber.selectionBounds.insetBy(dx: -3, dy: -3)
        precondition(!colored.isNull && expected.contains(colored))
        precondition(colored.width > exportedNumber.selectionBounds.width - 5)
        print("PASS: exported multi-digit circle uses scaled selection geometry and contains the text")

        // Window event path: Esc cancels inline editing rather than the screenshot.
        let window = OverlayWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.bindEditingActions(to: m)
        var cancelled = false
        window.onEscapeKey = { cancelled = true }
        m.startNumberEdit(annotationID: blueID)
        window.sendEvent(key(53, "\u{1b}"))
        precondition(!cancelled && !m.isEditingText)
        window.sendEvent(key(53, "\u{1b}")); precondition(cancelled)
        m.reset(); precondition(m.nextNumber == 1 && m.selectedNumberFontSize == Annotation.numberFontSize)
        print("PASS: window Escape dispatch and new-session reset")
    }
}
