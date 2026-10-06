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
    var isNumber = false
    var selectsAllOnFocus = false
    var allowsAncestorScrolling = true
    /// 内容尺寸变化时回调，用于动态调整编辑器大小
    var onSizeChange: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func makeTextView(fontSize: CGFloat, isNumber: Bool, color: NSColor) -> NSTextView {
        let textView = InlineAnnotationTextView()
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
        textView.font = AnnotationTextLayout.font(size: fontSize, isNumber: isNumber)
        textView.textColor = color
        return textView
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = Self.makeTextView(fontSize: fontSize, isNumber: isNumber, color: color)
        (textView as? InlineAnnotationTextView)?.allowsAncestorScrolling = allowsAncestorScrolling
        textView.delegate = context.coordinator
        textView.string = text

        // 等视图挂到窗口后再抢焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
            if selectsAllOnFocus { textView.selectAll(nil) }
            else if cursorAtEnd { textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0)) }
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.parent = self

        let font = AnnotationTextLayout.font(size: fontSize, isNumber: isNumber)
        if textView.font != font { textView.font = font }
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
        let font = AnnotationTextLayout.font(size: fontSize, isNumber: isNumber)
        onSizeChange(CGSize(width: max(2, ceil(used.maxX)),
                            height: max(ceil(layoutManager.defaultLineHeight(for: font)), ceil(used.maxY))))
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

/// Inline annotations expand to fit their text. In an image document, AppKit must not
/// scroll the outer viewport using the unscaled NSTextView selection rectangle.
private final class InlineAnnotationTextView: NSTextView {
    var allowsAncestorScrolling = true
    override func scrollRangeToVisible(_ range: NSRange) {
        if allowsAncestorScrolling { super.scrollRangeToVisible(range) }
    }
}
