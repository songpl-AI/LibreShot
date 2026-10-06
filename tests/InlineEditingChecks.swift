import AppKit
import SwiftUI

@main
struct InlineEditingChecks {
    @MainActor static func main() {
        let suite = "LibreShot.InlineEditing.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverlayViewModel(settings: SettingsService(defaults: defaults))
        model.state = .editing; model.selectionRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        var number = Annotation(type: .number, color: .blue)
        number.text = "12"; number.fontSize = 32; number.startPoint = CGPoint(x: 230, y: 170)
        model.annotations = [number]; model.startNumberEdit(annotationID: number.id)
        precondition(abs(model.editingTextEditorFrame.midX - number.startPoint.x) < 0.01 &&
                     abs(model.editingTextEditorFrame.midY - number.startPoint.y) < 0.01,
                     "number editor must retain the original circle center")
        precondition(model.editingNumberCircleRect == number.selectionBounds)
        precondition(model.selectedColor == number.color)
        model.editingTextContent = "9999"
        model.updateEditingTextSize(AnnotationTextLayout(text: "9999", fontSize: 32, isNumber: true).size)
        precondition(model.editingNumberCircleRect!.midX == number.startPoint.x &&
                     model.editingTextContentFrame.midX == number.startPoint.x)
        precondition(model.editingNumberCircleRect!.width >= number.selectionBounds.width)
        model.cancelTextInput(); precondition(model.annotations[0] == number)
        model.startNumberEdit(annotationID: number.id); model.editingTextContent = "34"; model.commitTextInput()
        precondition(model.annotations[0].text == "34" && model.annotations[0].startPoint == number.startPoint)
        model.undoLastAnnotation(); precondition(model.annotations[0] == number)
        print("PASS: centered number circle, multi-digit growth, color, commit/cancel and undo")

        let output = URL(fileURLWithPath: "/tmp/libreshot-inline-qa")
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func bounds(_ rep: NSBitmapImageRep) -> CGRect {
            var xs: [Int] = [], ys: [Int] = []
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if c.alphaComponent > 0.05 && c.redComponent > c.greenComponent + 0.2 && c.redComponent > c.blueComponent + 0.2 {
                        xs.append(x); ys.append(y)
                    }
                }
            }
            guard let x = xs.min(), let y = ys.min() else { return .zero }
            return CGRect(x: x, y: y, width: xs.max()! - x + 1, height: ys.max()! - y + 1)
        }
        func bitmap(_ image: NSImage) -> NSBitmapImageRep {
            NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        }
        var samples = 0
        for isNumber in [false, true] {
            for text in (isNumber ? ["1", "12", "9999"] : ["English Wgy", "中文测试", "第一行\n第二行 ABC", "Ag\n中文\n"]) {
                for size: CGFloat in [12, 24, 48] {
                    let layout = AnnotationTextLayout(text: text, fontSize: size, isNumber: isNumber, color: .red)
                    let view = InlineTextEditor.makeTextView(fontSize: size, isNumber: isNumber, color: .red)
                    view.string = text; view.frame = CGRect(origin: .zero, size: layout.size)
                    let manager = view.layoutManager!, container = view.textContainer!
                    manager.ensureLayout(for: container)
                    let used = manager.usedRect(for: container)
                    precondition(max(2, ceil(used.maxX)) == layout.size.width &&
                                 max(ceil(manager.defaultLineHeight(for: AnnotationTextLayout.font(size: size, isNumber: isNumber))), ceil(used.maxY)) == layout.size.height,
                                 "display/editor TextKit metrics must match: \(text) \(size): used \(used) layout \(layout.size)")
                    let editor = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: editor)
                    let display = bitmap(layout.image())
                    let a = bounds(editor), b = bounds(display)
                    precondition(a != .zero && a == b, "display/editor glyph positions must match: \(text) \(size): \(a) != \(b)")
                    samples += 1
                    if size == 24 && (text == "第一行\n第二行 ABC" || text == "9999") {
                        let name = isNumber ? "number" : "text"
                        try! editor.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + "-editor.png"))
                        try! display.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + "-display.png"))
                    }
                    if !isNumber {
                        var annotation = Annotation(type: .text, color: .red)
                        annotation.text = text; annotation.fontSize = size; annotation.startPoint = CGPoint(x: 20, y: 30)
                        model.annotations = [annotation]; model.selectedFontSize = 16; model.selectedColor = .blue
                        model.startTextEdit(annotationID: annotation.id)
                        precondition(model.editingTextContentFrame == annotation.textBoundingRect &&
                                     model.inputFontSize == size && model.selectedColor == .red,
                                     "text edit must start at existing size, origin and style")
                        model.cancelTextInput(); precondition(model.annotations[0] == annotation)
                        let base = NSImage(size: CGSize(width: 600, height: 500), flipped: false) { r in
                            NSColor.white.setFill(); r.fill(); return true
                        }
                        let exported = bitmap(CaptureService.shared.composite(image: base, annotations: [annotation]))
                        let scale = CGFloat(exported.pixelsWide) / 600
                        let glyphScale = CGFloat(display.pixelsWide) / layout.size.width
                        let expected = CGRect(x: (b.minX / glyphScale + 20) * scale,
                                              y: (b.minY / glyphScale + 30) * scale,
                                              width: b.width / glyphScale * scale, height: b.height / glyphScale * scale)
                        let actual = bounds(exported)
                        precondition(abs(actual.minX - expected.minX) <= 1 && abs(actual.minY - expected.minY) <= 1 &&
                                     abs(actual.maxX - expected.maxX) <= 1 && abs(actual.maxY - expected.maxY) <= 1,
                                     "export must retain glyph origin/baseline within one physical antialias pixel: \(text) \(size): \(actual) != \(expected)")
                    }
                }
            }
        }
        print("PASS: \(samples) native NSTextView/display glyph positions and export baselines across Chinese, English, multiline and fonts")
        model.annotations = []; model.selectTool(.text); model.startTextInput(at: CGPoint(x: 40, y: 40))
        precondition(model.editingTextSize == AnnotationTextLayout(text: "", fontSize: model.inputFontSize, isNumber: false).size)
        model.editingTextContent = "新文字"; model.commitTextInput()
        precondition(model.annotations[0].startPoint == CGPoint(x: 40, y: 40))
        print("PASS: new text editor resets stale size and preserves placement")

    }
}
