import SwiftUI

/// Reuses the production overlay with synthetic content, without screen recording.
@main
struct AnnotationSelectionUITestApp: App {
    var body: some Scene {
        WindowGroup("LibreShot 标注选择验收") {
            AnnotationSelectionFixture()
        }
    }
}

private struct AnnotationSelectionFixture: View {
    @StateObject private var model: OverlayViewModel = {
        let settings = SettingsService(defaults: UserDefaults(suiteName: "LibreShot.AnnotationSelectionQA")!)
        let model = OverlayViewModel(settings: settings)
        model.state = .editing
        model.selectionRect = CGRect(x: 40, y: 50, width: 680, height: 400)
        model.selectedTool = .arrow
        var rectangle = Annotation(type: .rectangle, color: .red)
        rectangle.startPoint = CGPoint(x: 150, y: 140)
        rectangle.endPoint = CGPoint(x: 450, y: 300)
        var text = Annotation(type: .text, color: .blue)
        text.startPoint = CGPoint(x: 190, y: 190)
        text.text = "Hello LibreShot"
        text.fontSize = 24
        model.annotations = [rectangle, text]
        model.onCancel = { NSApp.terminate(nil) }
        return model
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            OverlayView(viewModel: model)
            Text("工具：\(model.selectedTool?.rawValue ?? "选择")；标注：\(model.annotations.count)；选中：\(selectedType)；文字编辑：\(model.isEditingText)")
                .font(.system(size: 13))
                .foregroundStyle(.black)
                .padding(8)
                .allowsHitTesting(false)
        }
        .frame(width: 800, height: 580)
    }

    private var selectedType: String {
        model.annotations.first { $0.id == model.selectedAnnotationID }?.type.rawValue ?? "无"
    }
}
