import AppKit
import SwiftUI

@main struct EyedropperChecks {
    @MainActor static func main() {
        let suite = "LibreShot.Eyedropper.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 0, y: 0, width: 2, height: 1)

        model.selectTool(.rectangle)
        let rectangleRows = ToolPropertyBarView.rows(for: model, availableWidth: 640).flatMap { $0 }
        precondition(rectangleRows.contains(.eyedropper), "Color tools expose the eyedropper")
        model.selectTool(.mosaic)
        let mosaicRows = ToolPropertyBarView.rows(for: model, availableWidth: 640).flatMap { $0 }
        precondition(!mosaicRows.contains(.eyedropper), "Effect-only tools keep their existing color controls")

        let image = solidImage(red: CGPoint(x: 0, y: 0), blue: CGPoint(x: 1, y: 0))
        model.selectTool(.rectangle)
        model.updatePreviewImage(image, scale: 1)
        model.beginColorSampling(role: .fill)
        precondition(model.isSamplingColor)
        precondition(model.sampleColor(at: CGPoint(x: 0.5, y: 0.5)))
        precondition(AnnotationInk(model.currentToolStyle.color) == AnnotationInk(Color(red: 1, green: 0, blue: 0)),
                     "Eyedropper applies the sampled red")
        precondition(model.colorSamplingFeedback == "#FF0000", "A successful sample shows the picked color")
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
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
        precondition(model.performEditorShortcut(escape) && !model.isSamplingColor,
                     "Escape cancels color sampling")

        model.beginColorSampling(role: .fill)
        model.setColor(.green)
        precondition(!model.isSamplingColor, "Choosing a preset also disarms the eyedropper")

        model.selectTool(.number)
        model.beginColorSampling(role: .fill)
        precondition(model.sampleColor(at: CGPoint(x: 0.5, y: 0.5)))
        precondition(AnnotationInk(model.numberColor(for: .fill)) == AnnotationInk(Color(red: 1, green: 0, blue: 0)),
                     "Number fill uses the sampled color")

        model.state = .idle
        model.beginColorSampling(role: .fill)
        precondition(!model.isSamplingColor, "Eyedropper only arms while editing")

        // Drive a real hosting view so the native mouse observer, not just the
        // model API, receives the sampling click.
        _ = NSApplication.shared
        let live = OverlayViewModel(settings: settings)
        live.state = .editing
        live.selectionRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        live.selectTool(.rectangle)
        live.updatePreviewImage(splitImage(width: 800, height: 600), scale: 1)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: OverlayView(viewModel: live, showsToolbar: false))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        defer { window.close() }

        func click(at point: CGPoint) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 600 - point.y),
                                               modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               eventNumber: 0, clickCount: 1, pressure: 1)!
                NSApp.postEvent(event, atStart: false)
            }
            let deadline = Date().addingTimeInterval(0.2)
            while let queued = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        live.beginColorSampling(role: .fill)
        click(at: CGPoint(x: 100, y: 300))
        precondition(AnnotationInk(live.currentToolStyle.color) == AnnotationInk(Color(red: 1, green: 0, blue: 0)),
                     "Native canvas click feeds the eyedropper")
        precondition(live.colorSamplingFeedback == "#FF0000" && !live.isSamplingColor)
        live.beginColorSampling(role: .fill)
        click(at: CGPoint(x: 700, y: 300))
        precondition(AnnotationInk(live.currentToolStyle.color) == AnnotationInk(Color(red: 0, green: 0, blue: 1)),
                     "A second canvas click samples the other side")

        print("PASS: eyedropper rows, sRGB sampling, native canvas click, cancellation and number color roles")
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

    static func splitImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return context.makeImage()!
    }
}
