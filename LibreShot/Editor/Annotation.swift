import SwiftUI
import AppKit

enum AnnotationType: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case arrow
    case ellipse
    case text
    case number
    case mosaic
    case blur

    var id: String { self.rawValue }

    var iconName: String {
        switch self {
        case .pen: return "pencil"
        case .rectangle: return "square"
        case .arrow: return "arrow.up.right"
        case .ellipse: return "oval"
        case .text: return "textformat"
        case .number: return "number.circle"
        case .mosaic: return "square.grid.3x3"
        case .blur: return "drop"
        }
    }
}

extension Annotation {
    /// 文字标注的输入字号
    static let textInputFontSize: CGFloat = 24
    /// 序号标注的字号
    static let numberFontSize: CGFloat = 16

    /// 文字标注的文本包围盒尺寸（按实际字体度量，适配中英文，替代原来的 0.6 估算）
    var textBoundingSize: CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
        return (text as NSString).size(withAttributes: attrs)
    }

    /// 文字标注的包围盒（左上角锚定 startPoint）
    var textBoundingRect: CGRect {
        CGRect(origin: startPoint, size: textBoundingSize)
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    var type: AnnotationType
    var color: Color
    var points: [CGPoint] = [] // For pen
    var startPoint: CGPoint = .zero // For shapes
    var endPoint: CGPoint = .zero // For shapes
    var lineWidth: CGFloat = 3.0
    var text: String = ""  // For text annotations
    var fontSize: CGFloat = 16.0
}
