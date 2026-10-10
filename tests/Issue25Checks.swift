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
        precondition(model.confirmDoubleClick(at: point))
        precondition(output.count == 1 && output[0].text == "Keep this text")
        precondition(!model.confirmDoubleClick(at: .zero))
        settings.doubleClickCompletesCapture = false
        precondition(!model.confirmDoubleClick(at: point))
        settings.doubleClickCompletesCapture = true
        for state in [OverlayState.idle, .selecting, .longCaptureReady, .longCapturing] {
            model.state = state
            precondition(!model.confirmDoubleClick(at: point))
        }
        print("PASS: text is committed, preferences persist, and non-editor interactions do not export")
    }
}
