import SwiftUI

/// Standalone fixture for inspecting the real system download prompt without a capture.
@main
struct TranslationUITestApp: App {
    var body: some Scene {
        WindowGroup("LibreShot 翻译验收") {
            OCRResultView(text: "Hello world. This is a screenshot test.")
        }
    }
}
