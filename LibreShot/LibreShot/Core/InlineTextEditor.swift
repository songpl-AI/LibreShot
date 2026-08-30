import SwiftUI
import AppKit

/// 内联多行文字编辑器：所见即所得、随内容自动调整大小、支持光标定位到末尾。
/// 用 NSTextView 实现，因为 SwiftUI 的 TextField/TextEditor 无法控制光标位置、
/// 宽度也不能随内容增长。
struct InlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var color: NSColor
    /// 首次加载时是否把光标定位到文本末尾（用于重新编辑已有文字）
    var cursorAtEnd: Bool
    /// 内容尺寸变化时回调，用于动态调整编辑器大小
    var onSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        // 关键：给容器一个足够大的尺寸，文字才能按自然宽度排版、不被裁剪
        textView.textContainer?.containerSize = NSSize(width: 100000, height: 100000)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.maxSize = NSSize(width: 100000, height: 100000)
        textView.minSize = .zero
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = color
        textView.string = text

        // 等视图挂到窗口后再抢焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self

        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        textView.textColor = color

        if textView.string != text {
            textView.string = text
            if cursorAtEnd && !context.coordinator.appliedCursorAtEnd {
                let end = (text as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                context.coordinator.appliedCursorAtEnd = true
            }
        }
        reportSize(textView)
    }

    func reportSize(_ textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        onSizeChange(CGSize(width: ceil(used.width), height: ceil(used.height)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        var appliedCursorAtEnd = false

        init(_ parent: InlineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.reportSize(textView)
        }
    }
}
