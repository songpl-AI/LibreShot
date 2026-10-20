import AppKit
import SwiftUI

@main struct PropertyBarSlimChecks {
    @MainActor static func main() {
        let suite = "LibreShot.PropertySlim.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 20, y: 20, width: 500, height: 400)

        model.selectTool(.rectangle)
        let compactRows = CompactToolPropertyBarView.rows(for: model, availableWidth: 600).flatMap { $0 }
        precondition(compactRows.contains(.color) && compactRows.contains(.width) && compactRows.contains(.corner),
                     "Compact rectangle row keeps color, width, corner")
        precondition(compactRows.contains(.more), "Compact bar exposes the full property disclosure")
        let compactSize = ToolPropertyAccessoriesView.size(for: model, availableWidth: 600)
        precondition(compactSize.height == CompactToolPropertyBarView.inset * 2 + CompactToolPropertyBarView.rowHeight,
                     "One compact row is 34 points high")
        precondition(!model.toolPropertyAdvancedExpanded, "New sessions start with the lean bar")

        model.toolPropertyAdvancedExpanded = true
        let expandedSize = ToolPropertyAccessoriesView.size(for: model, availableWidth: 600)
        let fullSize = ToolPropertyBarView.size(for: model, availableWidth: ToolPropertyAccessoriesView.expandedBarWidth(600))
        let outer = 4 + ToolPropertyBarView.rowHeight + 4 + ToolPropertyBarView.rowHeight
        precondition(expandedSize.height == fullSize.height,
                     "The disclosure replaces the compact row with the existing full bar")
        precondition(expandedSize.width == min(600, fullSize.width + outer),
                     "The full bar keeps separate eyedropper and collapse controls")
        model.selectTool(.text)
        precondition(!model.toolPropertyAdvancedExpanded, "Changing tools collapses the full bar")

        model.selectTool(.text)
        let textRows = CompactToolPropertyBarView.rows(for: model, availableWidth: 600).flatMap { $0 }
        precondition(textRows.contains(.font) && !textRows.contains(.numberStyle),
                     "Text keeps color and size only")
        model.selectTool(.number)
        let numberRows = CompactToolPropertyBarView.rows(for: model, availableWidth: 600).flatMap { $0 }
        precondition(numberRows.contains(.numberStyle) && numberRows.contains(.font),
                     "Number keeps style, color and size in the compact row")
        model.selectTool(.mosaic)
        let mosaicRows = CompactToolPropertyBarView.rows(for: model, availableWidth: 600).flatMap { $0 }
        precondition(mosaicRows.contains(.effectMode) && mosaicRows.contains(.more),
                     "Mosaic keeps its application mode in the compact row")

        model.reset()
        precondition(ToolPropertyAccessoriesView.size(for: model, availableWidth: 600) == .zero,
                     "No property bar without a selected tool or annotation")

        // Eyedropper samples the frozen screenshot and applies sRGB values.
        let image = solidImage(red: CGPoint(x: 0, y: 0), blue: CGPoint(x: 1, y: 0))
        model.state = .editing
        model.selectionRect = CGRect(x: 0, y: 0, width: 2, height: 1)
        model.selectTool(.rectangle)
        model.updatePreviewImage(image, scale: 1)
        model.beginColorSampling(role: .fill)
        precondition(model.isSamplingColor)
        precondition(model.sampleColor(at: CGPoint(x: 0.5, y: 0.5)))
        precondition(AnnotationInk(model.currentToolStyle.color) == AnnotationInk(Color(red: 1, green: 0, blue: 0)),
                     "Eyedropper applies the sampled red")
        precondition(!model.isSamplingColor, "A successful sample disarms the eyedropper")
        model.beginColorSampling(role: .fill)
        precondition(model.sampleColor(at: CGPoint(x: 1.5, y: 0.5)))
        precondition(AnnotationInk(model.currentToolStyle.color) == AnnotationInk(Color(red: 0, green: 0, blue: 1)),
                     "Eyedropper applies the sampled blue")

        model.beginColorSampling(role: .fill)
        model.beginColorSampling(role: .fill)
        precondition(!model.isSamplingColor, "Clicking the armed eyedropper again cancels it")
        model.beginColorSampling(role: .fill)
        precondition(!model.canConfirmDoubleClick(at: CGPoint(x: 1, y: 0)),
                     "Sampling suppresses blank double-click completion")
        model.cancelColorSampling()
        precondition(!model.isSamplingColor, "Escape/cancel clears the eyedropper")
        model.beginColorSampling(role: .fill)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
        precondition(model.performEditorShortcut(escape) && !model.isSamplingColor,
                     "Escape cancels color sampling")
        model.toolPropertyAdvancedExpanded = true
        precondition(model.performEditorShortcut(escape) && !model.toolPropertyAdvancedExpanded,
                     "Escape collapses the full property bar before the capture")

        model.selectTool(.number)
        model.beginColorSampling(role: .fill)
        precondition(model.sampleColor(at: CGPoint(x: 0.5, y: 0.5)))
        precondition(AnnotationInk(model.numberColor(for: .fill)) == AnnotationInk(Color(red: 1, green: 0, blue: 0)),
                     "Number fill uses the sampled color")

        model.state = .idle
        model.beginColorSampling(role: .fill)
        precondition(!model.isSamplingColor, "Eyedropper only arms while editing")

        print("PASS: compact property rows, full-bar disclosure and eyedropper sampling")
    }

    static func solidImage(red: CGPoint, blue: CGPoint) -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: red.x, y: red.y, width: 1, height: 1))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: blue.x, y: blue.y, width: 1, height: 1))
        return context.makeImage()!
    }
}
