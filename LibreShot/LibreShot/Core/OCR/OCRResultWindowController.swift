import Cocoa
import SwiftUI

class OCRResultWindowController: NSWindowController {
    
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
    }
}

struct OCRResultView: View {
    let text: String
    @State private var copied = false
    @State private var targetLanguageID = "zh-Hans"
    @State private var translatedText: String = ""
    @State private var isTranslating = false
    @State private var translateError: String?

    private struct TargetLanguage: Identifiable {
        let id: String
        let name: String
    }

    private let targetLanguages: [TargetLanguage] = [
        TargetLanguage(id: "zh-Hans", name: "简体中文"),
        TargetLanguage(id: "en", name: "English"),
        TargetLanguage(id: "ja", name: "日本語"),
        TargetLanguage(id: "ko", name: "한국어"),
    ]

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
                    Picker("", selection: $targetLanguageID) {
                        ForEach(targetLanguages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)

                    Button(action: translate) {
                        if isTranslating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("翻译", systemImage: "character.bubble")
                        }
                    }
                    .disabled(isTranslating || text.isEmpty)
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

    @available(macOS 26.0, *)
    private func translate() {
        guard !text.isEmpty else { return }
        isTranslating = true
        translateError = nil
        translatedText = ""

        Task {
            do {
                let target = Locale.Language(identifier: targetLanguageID)
                let result = try await TranslationService.translate(text, target: target)
                await MainActor.run {
                    translatedText = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    translateError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
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
