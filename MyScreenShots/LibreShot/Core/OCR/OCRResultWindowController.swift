import Cocoa
import SwiftUI

class OCRResultWindowController: NSWindowController {
    
    convenience init(text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
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
    
    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(minWidth: 300, minHeight: 200)
            
            Divider()
            
            HStack {
                Text(copied ? "已复制！" : "\(text.count) 字符")
                    .foregroundColor(copied ? .green : .secondary)
                    .font(.caption)
                
                Spacer()
                
                Button(action: {
                    copyToClipboard()
                }) {
                    Label("复制文本", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 300)
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
