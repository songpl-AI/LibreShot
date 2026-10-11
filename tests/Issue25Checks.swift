import AppKit
import SwiftUI

@main struct Issue25Checks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "LibreShot.Issue25.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        precondition(settings.doubleClickCompletesCapture)
        settings.doubleClickCompletesCapture = false
        precondition(!SettingsService(defaults: defaults).doubleClickCompletesCapture)
        settings.doubleClickCompletesCapture = true
        let point = CGPoint(x: 200, y: 200)
        let editingModel = OverlayViewModel(settings: settings)
        editingModel.state = .editing
        editingModel.selectedTool = .arrow
        editingModel.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
        var text = Annotation(type: .text, color: .red)
        text.startPoint = point
        text.text = "Double-click to edit"
        editingModel.annotations = [text]
        var accidentalExports = 0
        editingModel.onCapture = { _, _, _, _ in accidentalExports += 1 }
        editingModel.beginConfirmationClick(at: point)
        precondition(!editingModel.confirmDoubleClick(at: point) && accidentalExports == 0,
                     "Issue #30: double-clicking existing text must edit, not export")
        _ = editingModel.handleAnnotationPressChanged(from: point, to: point)
        _ = editingModel.handleAnnotationPressEnded(from: point, to: point)
        editingModel.clearAnnotationPress()
        _ = editingModel.handleAnnotationPressChanged(from: point, to: point)
        _ = editingModel.handleAnnotationPressEnded(from: point, to: point)
        editingModel.clearAnnotationPress()
        precondition(editingModel.isEditingText && editingModel.editingTextAnnotationID == text.id)
        print("PASS: existing text double-click does not export")
        for tool in [nil] + AnnotationType.allCases.map(Optional.some) {
            let model = OverlayViewModel(settings: settings)
            model.state = .editing
            model.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
            model.selectedTool = tool
            var exports = 0
            model.onCapture = { _, annotations, action, _ in
                precondition(annotations.isEmpty, "Double-click must not add a number or stroke")
                if case .copy = action {} else { preconditionFailure("Must use the Complete action") }
                exports += 1
            }
            model.beginConfirmationClick(at: point)
            if tool == .number { model.placeNumber(at: point) }
            else if tool == .text { model.startTextInput(at: point) }
            else { model.startDrawing(at: point); model.updateDrawing(to: point); model.endDrawing() }
            model.endConfirmationClick(at: point)
            precondition(model.confirmDoubleClick(at: point) && exports == 1)
            precondition(!model.confirmDoubleClick(at: point) && exports == 1)
            if tool == .number { precondition(model.nextNumber == 1) }
            print("PASS: double-click completes with tool \(String(describing: tool)) and adds no annotation")
        }
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
        model.selectTool(.text)
        model.startTextInput(at: point)
        model.editingTextContent = "Keep this text"
        var output: [Annotation] = []
        model.onCapture = { _, annotations, _, _ in output = annotations }
        precondition(!model.beginConfirmationClick(at: point))
        precondition(!model.confirmDoubleClick(at: point) && output.isEmpty && model.isEditingText)
        precondition(model.editingTextContent == "Keep this text")
        model.confirmCopy()
        precondition(output.count == 1 && output[0].text == "Keep this text")
        model.cancelTextInput()
        precondition(!model.confirmDoubleClick(at: .zero))
        settings.doubleClickCompletesCapture = false
        precondition(!model.confirmDoubleClick(at: point))
        settings.doubleClickCompletesCapture = true
        for state in [OverlayState.idle, .selecting, .longCaptureReady, .longCapturing] {
            model.state = state
            precondition(!model.confirmDoubleClick(at: point))
        }
        print("PASS: text editing is protected and explicit Complete still commits text")

        let boundary = OverlayViewModel(settings: settings)
        boundary.state = .editing
        boundary.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
        boundary.selectedTool = .rectangle
        var shape = Annotation(type: .rectangle, color: .red)
        shape.startPoint = CGPoint(x: 350, y: 280)
        shape.endPoint = CGPoint(x: 500, y: 380)
        boundary.annotations = [shape]
        boundary.selectedAnnotationID = shape.id
        var boundaryExports = 0
        boundary.onCapture = { _, _, _, _ in boundaryExports += 1 }
        for target in [shape.startPoint, CGPoint(x: 352, y: 282), CGPoint(x: 400, y: 320),
                       CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 100)] {
            precondition(!boundary.beginConfirmationClick(at: target))
            precondition(!boundary.confirmDoubleClick(at: target) && boundaryExports == 0)
        }
        boundary.selectedAnnotationID = nil
        for type in AnnotationType.allCases {
            var annotation = Annotation(type: type, color: .red)
            annotation.startPoint = CGPoint(x: 350, y: 280)
            annotation.endPoint = CGPoint(x: 500, y: 380)
            annotation.points = [annotation.startPoint, annotation.endPoint]
            annotation.text = "Existing text"
            boundary.annotations = [annotation]
            let target = type == .ellipse ? CGPoint(x: 425, y: 280) : annotation.startPoint
            precondition(boundary.annotationID(at: target) == annotation.id, "Fixture must hit \(type)")
            precondition(!boundary.beginConfirmationClick(at: target))
            precondition(!boundary.confirmDoubleClick(at: target) && boundaryExports == 0)
        }
        boundary.annotations = []
        precondition(boundary.beginConfirmationClick(at: point))
        boundary.endConfirmationClick(at: CGPoint(x: 220, y: 200))
        boundary.endConfirmationClick(at: point)
        precondition(!boundary.confirmDoubleClick(at: point))
        precondition(boundary.beginConfirmationClick(at: point))
        boundary.selectionRect.origin.x += 1
        precondition(!boundary.confirmDoubleClick(at: point))
        precondition(boundary.beginConfirmationClick(at: point))
        boundary.selectedTool = .arrow
        precondition(!boundary.confirmDoubleClick(at: point))
        precondition(boundary.beginConfirmationClick(at: point))
        boundary.cancelConfirmationClick()
        precondition(!boundary.confirmDoubleClick(at: point))
        precondition(boundary.beginConfirmationClick(at: point))
        boundary.reset()
        boundary.state = .editing
        boundary.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
        precondition(!boundary.confirmDoubleClick(at: point) && boundaryExports == 0)
        print("PASS: all annotation types, handles, selected interiors, drags and stale clicks are protected")

        boundary.selectTool(.number)
        boundary.placeNumber(at: point)
        precondition(!boundary.beginConfirmationClick(at: point))
        for _ in 0..<2 {
            _ = boundary.handleAnnotationPressChanged(from: point, to: point)
            _ = boundary.handleAnnotationPressEnded(from: point, to: point)
            boundary.clearAnnotationPress()
        }
        precondition(boundary.isEditingNumber && boundaryExports == 0)
        precondition(!boundary.beginConfirmationClick(at: CGPoint(x: 600, y: 450)))
        precondition(!boundary.confirmDoubleClick(at: CGPoint(x: 600, y: 450)))
        print("PASS: existing number double-click enters editing with completion enabled")

        precondition(settings.playSound)
        settings.playSound = false
        precondition(!SettingsService(defaults: defaults).playSound)
        settings.playSound = true
        precondition(SettingsService(defaults: defaults).playSound)
        print("PASS: capture sound defaults on and preference persists in both directions")
        checkNativeMouseObserver(settings: settings)
    }

    @MainActor private static func checkNativeMouseObserver(settings: SettingsService) {
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 100, y: 100, width: 600, height: 400)
        model.selectedTool = .arrow
        var text = Annotation(type: .text, color: .blue)
        text.startPoint = CGPoint(x: 200, y: 200)
        text.text = "Native double-click"
        model.annotations = [text]
        var exports = 0
        model.onCapture = { _, _, _, _ in exports += 1 }
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: OverlayView(viewModel: model, showsToolbar: false))
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        defer { window.close() }

        func post(_ type: NSEvent.EventType, at point: CGPoint, count: Int) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 600 - point.y),
                                          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: count, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
        func doubleClick(at point: CGPoint) {
            // NSTextView tracks mouse-down synchronously until mouse-up, so queue
            // the entire gesture before dispatching any of its events.
            for count in 1...2 {
                post(.leftMouseDown, at: point, count: count)
                post(.leftMouseUp, at: point, count: count)
            }
            let deadline = Date().addingTimeInterval(0.1)
            while let queued = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        doubleClick(at: text.startPoint)
        precondition(exports == 0 && model.isEditingText && model.editingTextAnnotationID == text.id,
                     "Native observer must pass annotation double-clicks through to editing")
        doubleClick(at: text.startPoint)
        precondition(exports == 0 && model.isEditingText, "Native editor double-click must not export")
        model.cancelTextInput()
        model.selectedTool = .number
        doubleClick(at: CGPoint(x: 580, y: 400))
        precondition(exports == 1 && model.annotations == [text],
                     "Native blank double-click must complete once without a provisional number")
        print("PASS: native mouse observer preserves text editing and consumes only blank completion")
    }
}
