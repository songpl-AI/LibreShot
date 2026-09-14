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
    @State private var translatedText = ""
    @State private var translateError: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(minHeight: 140)
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Text("\(text.count) 字符").foregroundStyle(.secondary).font(.caption)
                    Spacer()
                    OCRCopyButton(text: text, title: "复制文本")
                        .keyboardShortcut("c", modifiers: .command)
                }
                if #available(macOS 26.0, *) {
                    HStack {
                        Text("翻译为").foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        OCRTranslationControls(text: text, translatedText: $translatedText, translateError: $translateError)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            if let error = translateError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 12)
            } else if !translatedText.isEmpty {
                Divider()
                HStack {
                    Text("译文").font(.headline)
                    Spacer()
                    OCRCopyButton(text: translatedText, title: "复制译文")
                }.padding(12)
                TextEditor(text: .constant(translatedText))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minHeight: 140)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

struct OCRCopyButton: View {
    let text: String
    let title: String
    @State private var copyID: UUID?

    var body: some View {
        Button {
            Self.copy(text, to: .general)
            copyID = UUID()
        } label: {
            Label(copyID == nil ? title : "已复制", systemImage: copyID == nil ? "doc.on.doc" : "checkmark")
                .frame(minWidth: 82)
                .fixedSize()
        }
        .disabled(text.isEmpty)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)); copyID = nil } catch { }
        }
        .onChange(of: text) { _ in copyID = nil }
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
                HStack(spacing: 6) {
                    ZStack {
                        Image(systemName: "character.bubble").opacity(model.isTranslating ? 0 : 1)
                        if model.isTranslating { ProgressView().controlSize(.small) }
                    }.frame(width: 18, height: 18)
                    Text("翻译")
                }
                .frame(minWidth: 68)
                .fixedSize()
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
