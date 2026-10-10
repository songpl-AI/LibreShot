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
        case .blur: return "camera.filters"
        }
    }
}

enum EffectDrawingMode: String, Codable, CaseIterable, Identifiable {
    case brush
    case rectangle
    var id: String { rawValue }
    var title: String { self == .brush ? "涂抹" : "框选" }
}

enum NumberAnnotationStyle: String, Codable, CaseIterable, Identifiable {
    case outline, filled
    var id: String { rawValue }
    var title: String { self == .filled ? "实心" : "描边" }
}

/// Persisted defaults for one tool; each annotation keeps its own snapshot.
struct AnnotationToolStyle: Codable, Equatable {
    var red: Double = 1
    var green: Double = 0
    var blue: Double = 0
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 24
    var numberStyle: NumberAnnotationStyle = .filled
    var blockSize: CGFloat = 16
    var blurRadius: CGFloat = 12
    var brushWidth: CGFloat = 20
    var effectMode: EffectDrawingMode = .rectangle

    var color: Color {
        get {
            for preset: Color in [.red, .orange, .yellow, .green, .blue, .purple, .black, .white] {
                if let rgb = NSColor(preset).usingColorSpace(.sRGB),
                   abs(rgb.redComponent - red) < 0.000001,
                   abs(rgb.greenComponent - green) < 0.000001,
                   abs(rgb.blueComponent - blue) < 0.000001 { return preset }
            }
            return Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        }
        set {
            guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
            red = rgb.redComponent; green = rgb.greenComponent; blue = rgb.blueComponent
        }
    }

    static func factory(for tool: AnnotationType) -> Self {
        var style = Self()
        style.color = .red
        if tool == .number { style.fontSize = Annotation.numberFontSize }
        if tool == .blur { style.effectMode = .brush }
        return style
    }

    var validated: Self {
        var style = self
        func bounded(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat, _ fallback: CGFloat) -> CGFloat {
            value.isFinite ? min(max(value, lower), upper) : fallback
        }
        style.red = Double(bounded(CGFloat(red), 0, 1, 1))
        style.green = Double(bounded(CGFloat(green), 0, 1, 0))
        style.blue = Double(bounded(CGFloat(blue), 0, 1, 0))
        style.lineWidth = bounded(lineWidth, 1, 20, 3)
        style.fontSize = bounded(fontSize, 8, 128, 24)
        style.blockSize = bounded(blockSize, 4, 64, 16)
        style.blurRadius = bounded(blurRadius, 2, 32, 12)
        style.brushWidth = bounded(brushWidth, 12, 120, 20)
        return style
    }
}

/// Shared arrow geometry for display, export and pointer hit testing.
struct AnnotationArrowGeometry {
    let shaft: CGPath
    let head: CGPath
    init(start: CGPoint, end: CGPoint, lineWidth: CGFloat) {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = min(max(10, lineWidth * 4.5), length * 0.45)
        let base = CGPoint(x: end.x - headLength * cos(angle), y: end.y - headLength * sin(angle))
        let halfWidth = headLength * 0.45
        let shaft = CGMutablePath()
        shaft.move(to: start); shaft.addLine(to: base)
        let head = CGMutablePath()
        head.move(to: end)
        head.addLine(to: CGPoint(x: base.x - halfWidth * sin(angle), y: base.y + halfWidth * cos(angle)))
        head.addLine(to: CGPoint(x: base.x + halfWidth * sin(angle), y: base.y - halfWidth * cos(angle)))
        head.closeSubpath()
        self.shaft = shaft; self.head = head
    }
}

extension Annotation {
    // Points encode brush geometry; empty points retain rectangular effects.
    var isEffectBrush: Bool { (type == .mosaic || type == .blur) && !points.isEmpty }

    /// Bounds of the whole annotation, including intermediate freehand points.
    var selectionBounds: CGRect {
        if type == .text { return textBoundingRect }
        if type == .arrow {
            return arrowGeometry.shaft.boundingBoxOfPath.union(arrowGeometry.head.boundingBoxOfPath)
                .insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        }
        if type == .number {
            let radius = numberRadius
            return CGRect(x: startPoint.x - radius, y: startPoint.y - radius, width: radius * 2, height: radius * 2)
        }
        if (type == .pen || isEffectBrush), !points.isEmpty {
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                .insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        }
        return CGRect(from: startPoint, to: endPoint)
    }
    /// Shared geometry for live drawing, selection and exported multi-digit numbers.
    var numberRadius: CGFloat {
        let size = textBoundingSize
        return max(fontSize, max(size.width, size.height)) / 2 + fontSize / 4
    }

    /// 文字标注的输入字号
    static let textInputFontSize: CGFloat = 24
    /// 序号标注的字号
    static let numberFontSize: CGFloat = 16

    /// 文字标注的文本包围盒尺寸（按实际字体度量，适配中英文，替代原来的 0.6 估算）
    var textBoundingSize: CGSize {
        AnnotationTextLayout(text: text, fontSize: fontSize, isNumber: type == .number).size
    }

    /// 文字标注的包围盒（左上角锚定 startPoint）
    var textBoundingRect: CGRect {
        CGRect(origin: startPoint, size: textBoundingSize)
    }

    var arrowGeometry: AnnotationArrowGeometry {
        AnnotationArrowGeometry(start: startPoint, end: endPoint, lineWidth: lineWidth)
    }

    var textColor: NSColor {
        guard type == .number, numberStyle == .filled,
              let rgb = NSColor(color).usingColorSpace(.sRGB) else { return NSColor(color) }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return luminance > 0.45 ? .black : .white
    }

    /// Hit visible strokes rather than their empty bounding-box interiors.
    /// Shared by pointer selection and hover feedback.
    func containsSelectionPoint(_ point: CGPoint) -> Bool {
        let tolerance: CGFloat = 6
        let rect = CGRect(from: startPoint, to: endPoint)
        let path = CGMutablePath()
        switch type {
        case .text:
            return textBoundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .number:
            return hypot(point.x - startPoint.x, point.y - startPoint.y) <= numberRadius + tolerance
        case .rectangle:
            path.addRect(rect)
        case .ellipse:
            path.addEllipse(in: rect)
        case .arrow:
            let arrow = arrowGeometry
            if arrow.head.contains(point) { return true }
            path.addPath(arrow.shaft); path.addPath(arrow.head)
        case .pen, .mosaic, .blur:
            if type != .pen && !isEffectBrush { return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
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

struct Annotation: Identifiable, Equatable {
    let id = UUID()
    var type: AnnotationType
    var color: Color
    var points: [CGPoint] = [] // For pen
    var startPoint: CGPoint = .zero // For shapes
    var endPoint: CGPoint = .zero // For shapes
    var mosaicBlockSize: CGFloat = 16
    var blurRadius: CGFloat = 12
    var lineWidth: CGFloat = 3.0
    var text: String = ""  // For text annotations
    var fontSize: CGFloat = 16.0
    var numberStyle: NumberAnnotationStyle = .outline
}

/// One TextKit layout for display, editing, hit bounds and export.
/// Keeping glyph origins at (0, 0) avoids switching baseline conventions on edit.
final class AnnotationTextLayout {
    let storage: NSTextStorage
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 100000, height: 100000))
    let size: CGSize

    static func font(size: CGFloat, isNumber: Bool) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: isNumber ? .semibold : .medium)
    }

    init(text: String, fontSize: CGFloat, isNumber: Bool, color: NSColor = .labelColor) {
        let font = Self.font(size: fontSize, isNumber: isNumber)
        storage = NSTextStorage(string: text, attributes: [.font: font, .foregroundColor: color])
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        // NSTextView fixes fallback fonts when assigning its string (notably CJK).
        storage.fixAttributes(in: NSRange(location: 0, length: storage.length))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        size = CGSize(width: max(2, ceil(used.maxX)),
                      height: max(ceil(manager.defaultLineHeight(for: font)), ceil(used.maxY)))
    }

    func image() -> NSImage {
        NSImage(size: size, flipped: true) { [self] _ in
            manager.drawGlyphs(forGlyphRange: manager.glyphRange(for: container), at: .zero)
            return true
        }
    }
}
