import Cocoa
import Combine
import SwiftUI
import Translation

class OCRResultWindowController: NSWindowController, NSWindowDelegate {
    
    convenience init(text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OCR 识别结果"
        window.center()
        
        let contentView = OCRResultView(text: text)
        window.contentView = NSHostingView(rootView: contentView)
        
        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // Tear down the hosting view so SwiftUI cancels its translation task,
        // even while AppDelegate still retains this window controller.
        window?.contentView = nil
    }
}

struct OCRResultView: View {
    let text: String
    @State private var copied = false
    @State private var translatedText: String = ""
    @State private var translateError: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(minHeight: 140)

            Divider()

            HStack {
                Text(copied ? "已复制！" : "\(text.count) 字符")
                    .foregroundColor(copied ? .green : .secondary)
                    .font(.caption)

                Spacer()

                if #available(macOS 26.0, *) {
                    OCRTranslationControls(text: text,
                                           translatedText: $translatedText,
                                           translateError: $translateError)
                }

                Button(action: {
                    copyToClipboard()
                }) {
                    Label("复制文本", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            if let error = translateError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else if !translatedText.isEmpty {
                Divider()
                TextEditor(text: .constant(translatedText))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minHeight: 140)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        withAnimation {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}


@available(macOS 26.0, *)
private struct OCRTranslationControls: View {
    let text: String
    @Binding var translatedText: String
    @Binding var translateError: String?
    @StateObject private var model = OCRTranslationModel()

    var body: some View {
        HStack {
            Picker("翻译为", selection: $model.targetLanguageID) {
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
                Text("日本語").tag("ja")
                Text("한국어").tag("ko")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
            .disabled(model.isTranslating)

            Button {
                model.start(text: text)
            } label: {
                if model.isTranslating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("翻译", systemImage: "character.bubble")
                }
            }
            .disabled(model.isTranslating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("首次翻译可能需要联网下载免费语言包，系统会询问是否下载；安装后可离线翻译。")
        }
        .translationTask(model.configuration) { session in
            await model.run { text in
                try await TranslationService.translate(text, using: session)
            }
        }
        .onChange(of: model.translatedText) { _, value in translatedText = value }
        .onChange(of: model.errorMessage) { _, value in translateError = value }
        .onDisappear { model.cancel() }
    }
}

/// Stores only request/UI state, never a TranslationSession or language model.
@available(macOS 26.0, *)
@MainActor
final class OCRTranslationModel: ObservableObject {
    @Published var targetLanguageID = "zh-Hans"
    @Published private(set) var configuration: TranslationSession.Configuration?
    @Published private(set) var isTranslating = false
    @Published private(set) var translatedText = ""
    @Published private(set) var errorMessage: String?
    private var request: (id: UUID, text: String)?
    // A value only: changing its version makes same-language retries start a new task.
    private var lastConfiguration = TranslationSession.Configuration()

    func start(text: String) {
        guard !isTranslating, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        translatedText = ""
        let source = TranslationService.detectLanguage(of: text)
        let target = Locale.Language(identifier: targetLanguageID)
        if source == target {
            translatedText = text
            return
        }
        request = (UUID(), text)
        isTranslating = true
        lastConfiguration.source = source
        lastConfiguration.target = target
        lastConfiguration.invalidate()
        configuration = lastConfiguration
    }

    func run(translate: (String) async throws -> String) async {
        guard let current = request else { return }
        defer {
            if request?.id == current.id {
                request = nil
                configuration = nil
                isTranslating = false
            }
        }
        do {
            try Task.checkCancellation()
            let result = try await translate(current.text)
            try Task.checkCancellation()
            guard request?.id == current.id else { return }
            translatedText = result
        } catch {
            guard request?.id == current.id else { return }
            if error is CancellationError || TranslationError.alreadyCancelled ~= error ||
                ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError) {
                errorMessage = "已取消翻译，可再次点击翻译重试。"
            } else {
                errorMessage = "翻译未完成：\(error.localizedDescription) 可再次点击翻译重试。"
            }
        }
    }

    func cancel() {
        request = nil
        configuration = nil
        isTranslating = false
    }
}
