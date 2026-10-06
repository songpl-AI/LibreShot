import AppKit
import SwiftUI

@main
struct Issue17And18Checks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL"): \(label)")
            if !value { failures += 1 }
        }
        let suite = "LibreShot.Issues17And18.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vm = OverlayViewModel(settings: SettingsService(defaults: defaults))
        vm.state = .editing
        vm.selectionRect = CGRect(x: 0, y: 0, width: 600, height: 500)
        vm.selectedTool = .text
        var text = Annotation(type: .text, color: .red)
        text.text = "再次选择文字"; text.startPoint = CGPoint(x: 80, y: 80)
        vm.annotations = [text]
        let start = CGPoint(x: 90, y: 90), end = CGPoint(x: 130, y: 110)
        // Follow the overlay routing: an unselected annotation press must promote to a drag.
        _ = vm.handleSelectedShapeDrag(from: start, to: start, within: vm.selectionRect)
        _ = vm.handleAnnotationPressChanged(from: start, to: start)
        if !vm.handleSelectedShapeDrag(from: start, to: end, within: vm.selectionRect) {
            _ = vm.handleAnnotationPressChanged(from: start, to: end)
        }
        if vm.isTransformingShape {
            _ = vm.handleSelectedShapeDrag(from: start, to: end, within: vm.selectionRect)
            vm.endSelectedShapeDrag()
        } else { _ = vm.handleAnnotationPressEnded(from: start, to: end) }
        vm.clearAnnotationPress()
        check(vm.annotations.count == 1 && vm.annotations[0].startPoint == CGPoint(x: 120, y: 100),
              "first drag on unselected text moves it without creating a text box")
        check(vm.selectedAnnotationID == text.id && !vm.isEditingText, "drag selects text without entering input")
        vm.undoLastAnnotation()
        check(vm.annotations == [text], "one undo restores the exact text position")
        vm.startTextInput(at: start)
        check(!vm.isEditingText && vm.selectedAnnotationID == text.id && vm.annotations.count == 1,
              "text creation fallback selects a hit object instead of opening a duplicate input")
        vm.selectTool(.text)
        vm.startTextInput(at: CGPoint(x: 400, y: 300))
        check(vm.isEditingText && vm.editingTextAnnotationID == nil, "blank-space text creation still works")
        vm.cancelTextInput()

        vm.selectTool(.number)
        vm.setNumberStyle(.filled); vm.setColor(.blue); vm.placeNumber(at: CGPoint(x: 320, y: 120))
        let number = vm.annotations.last!
        check(number.numberStyle == .filled && number.textColor == .white, "blue filled numbers use white digits")
        var lightNumber = number; lightNumber.color = .yellow
        check(lightNumber.textColor == .black, "light filled numbers keep readable dark digits")
        vm.startNumberEdit(annotationID: number.id)
        check(vm.editingTextColor == number.textColor && vm.editingNumberAnnotation?.numberStyle == .filled,
              "inline number editing preserves its fill and contrasting digits")
        vm.cancelTextInput(); vm.selectedAnnotationID = number.id
        vm.setNumberStyle(.outline)
        check(vm.annotations.last!.numberStyle == .outline, "style switching updates the selected number")
        vm.undoLastAnnotation()
        check(vm.annotations.last!.numberStyle == .filled && vm.selectedNumberStyle == .filled,
              "undo restores number style and the next-number preference")
        vm.setNumberStyle(.outline); vm.placeNumber(at: CGPoint(x: 420, y: 120))
        check(vm.annotations.last!.numberStyle == .outline && SettingsService(defaults: defaults).numberAnnotationStyle == .outline,
              "number style is inherited and remembered for the next capture")

        let base = NSImage(size: CGSize(width: 600, height: 400))
        base.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 400).fill(); base.unlockFocus()
        var arrow = Annotation(type: .arrow, color: .red)
        arrow.startPoint = CGPoint(x: 60, y: 220); arrow.endPoint = CGPoint(x: 220, y: 220)
        arrow.lineWidth = 4
        let headPoint = CGPoint(x: 210, y: 223)
        check(arrow.arrowGeometry.head.contains(headPoint) && arrow.containsSelectionPoint(headPoint),
              "filled arrow head is selectable through the shared geometry")
        var shortArrow = arrow; shortArrow.endPoint = CGPoint(x: 68, y: 220)
        check(shortArrow.arrowGeometry.head.boundingBoxOfPath.width <= 3.61, "short arrows cap their head size")
        let exported = CaptureService.shared.composite(image: base, annotations: [number, arrow])
        let bitmap = NSBitmapImageRep(cgImage: exported.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let scale = CGFloat(bitmap.pixelsWide) / 600
        func pixel(_ point: CGPoint) -> NSColor {
            bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.sRGB)!
        }
        check(pixel(headPoint).redComponent > 0.8 && pixel(headPoint).greenComponent < 0.4,
              "exported arrow head is solid, not an open V")
        let numberFill = pixel(CGPoint(x: number.startPoint.x, y: number.startPoint.y - number.numberRadius * 0.7))
        check(numberFill.blueComponent > 0.7 && numberFill.redComponent < 0.3,
              "exported filled number retains its colored background")
        if let path = ProcessInfo.processInfo.environment["LIBRESHOT_STYLE_SAMPLE"] {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }

        let finder = NSImage(contentsOfFile: "tests/fixtures/finder-numbered-rows.png")!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        func frame(_ offset: Int) -> LongCaptureFrame {
            .init(image: finder.cropping(to: CGRect(x: 20, y: offset, width: finder.width - 40, height: 600))!, timestamp: Double(offset))
        }
        let document = LongCaptureFrameAccumulator()
        for offset in [100, 180, 260, 340, 420] { _ = document.process(frame: frame(offset)) }
        let reverse = document.process(frame: frame(410))
        check(reverse?.warning == nil && reverse?.appendedPixelHeight == 920,
              "short reverse bounce preserves the accepted document without failure")
        do {
            let image = try document.renderFinalImage().cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let expected = finder.cropping(to: CGRect(x: 20, y: 100, width: finder.width - 40, height: 920))!
            check(samePixels(image, expected), "finishing after a reverse bounce exports every captured row exactly once")
        } catch { check(false, "finishing after reverse bounce must not report incomplete capture") }
        check(document.process(frame: frame(260))?.warning == nil, "upward revisit within captured content is tolerated")
        _ = document.process(frame: frame(420)); _ = document.process(frame: frame(500))
        check(try document.renderFinalImage().size.height == 1000, "resuming downward appends from the frontier, not the revisited frame")
        check(document.process(frame: frame(20))?.warning != nil, "uncaptured content above the initial frame still reports an incomplete capture")
        let gap = LongCaptureFrameAccumulator()
        _ = gap.process(frame: frame(100))
        check(gap.process(frame: frame(900))?.warning != nil, "a genuine forward overlap gap remains an error")
        do { _ = try gap.renderFinalImage(); check(false, "a genuine gap cannot export silently") }
        catch LongCaptureError.incompleteCapture { check(true, "a genuine gap cannot export silently") }
        if failures > 0 { exit(1) }
    }

    static func samePixels(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        func bytes(_ image: CGImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &result, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return result
        }
        return bytes(a) == bytes(b)
    }
}
