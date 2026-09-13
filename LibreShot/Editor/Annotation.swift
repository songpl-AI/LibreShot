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
        case .number: return "1.circle"
        case .mosaic: return "square.grid.3x3.fill"
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

    /// Hit visible strokes rather than their empty bounding-box interiors.
    /// Called on pointer-down, never from a hover timer or a rendering loop.
    func containsSelectionPoint(_ point: CGPoint) -> Bool {
        let tolerance: CGFloat = 6
        let rect = CGRect(from: startPoint, to: endPoint)
        let path = CGMutablePath()
        switch type {
        case .text:
            return textBoundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .number:
            return hypot(point.x - startPoint.x, point.y - startPoint.y) <= fontSize / 2 + 4 + tolerance
        case .mosaic:
            let all = points + [startPoint, endPoint]
            let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
            let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .rectangle:
            path.addRect(rect)
        case .ellipse:
            path.addEllipse(in: rect)
        case .arrow:
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            for offset in [-CGFloat.pi / 6, CGFloat.pi / 6] {
                path.move(to: endPoint)
                path.addLine(to: CGPoint(x: endPoint.x - 15 * cos(angle + offset),
                                        y: endPoint.y - 15 * sin(angle + offset)))
            }
        case .pen, .blur:
            if let first = points.first {
                if points.allSatisfy({ $0 == first }) {
                    return hypot(point.x - first.x, point.y - first.y) <= lineWidth / 2 + tolerance
                }
                path.move(to: first)
                for next in points.dropFirst() { path.addLine(to: next) }
            } else if type == .blur {
                path.addRect(rect)
            } else {
                return false
            }
        }
        return path.copy(strokingWithWidth: lineWidth + tolerance * 2,
                         lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
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
