import Foundation
import CoreGraphics

/// Stable identifiers shared by the settings page and screenshot toolbar.
enum ToolbarItem: String, CaseIterable, Identifiable {
    case select, pen, rectangle, arrow, ellipse, text, number, mosaic, blur
    case style, undo, cancel, pin, ocr, longCapture, complete, save, saveAs
    case translate

    var id: String { rawValue }
    var isRequired: Bool { self == .complete || self == .cancel }

    var title: String {
        switch self {
        case .select: return "选择/移动"
        case .pen: return "画笔"
        case .rectangle: return "矩形"
        case .arrow: return "箭头"
        case .ellipse: return "椭圆"
        case .text: return "文字"
        case .number: return "序号"
        case .mosaic: return "马赛克"
        case .blur: return "模糊"
        case .style: return "颜色与字号"
        case .undo: return "撤销"
        case .cancel: return "取消截图"
        case .pin: return "贴图到屏幕"
        case .ocr: return "识别文字"
        case .longCapture: return "长截图"
        case .complete: return "完成"
        case .save: return "保存"
        case .saveAs: return "另存为…"
        case .translate: return "原图翻译"
        }
    }

    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return AnnotationType.pen.iconName
        case .rectangle: return AnnotationType.rectangle.iconName
        case .arrow: return AnnotationType.arrow.iconName
        case .ellipse: return AnnotationType.ellipse.iconName
        case .text: return AnnotationType.text.iconName
        case .number: return AnnotationType.number.iconName
        case .mosaic: return AnnotationType.mosaic.iconName
        case .blur: return AnnotationType.blur.iconName
        case .style: return "paintpalette"
        case .undo: return "arrow.uturn.backward"
        case .cancel: return "xmark"
        case .pin: return "pin"
        case .ocr: return "text.viewfinder"
        case .longCapture: return "arrow.up.and.down.square"
        case .complete: return "checkmark"
        case .save: return "square.and.arrow.down"
        case .saveAs: return "square.and.arrow.down.on.square"
        case .translate: return "character.bubble"
        }
    }

    var annotationType: AnnotationType? { AnnotationType(rawValue: rawValue) }
}

struct ToolbarConfiguration {
    // Store only hidden items so newly introduced tools remain discoverable.
    var hiddenItems: Set<String> = []
    private(set) var orderedItems: [ToolbarItem]

    init(hiddenItems: Set<String> = [], itemOrder: [String] = []) {
        self.hiddenItems = hiddenItems
        // Normalize once on load: discard unknown/duplicate IDs and append new tools.
        var seen = Set<ToolbarItem>()
        let savedItems = itemOrder.compactMap(ToolbarItem.init(rawValue:))
        orderedItems = (savedItems + ToolbarItem.allCases).filter { seen.insert($0).inserted }
    }

    func isVisible(_ item: ToolbarItem) -> Bool {
        item.isRequired || !hiddenItems.contains(item.rawValue)
    }

    var visibleItems: [ToolbarItem] { orderedItems.filter(isVisible) }

    mutating func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty, source.allSatisfy({ orderedItems.indices.contains($0) }),
              (0...orderedItems.count).contains(destination) else { return }
        let moving = source.map { orderedItems[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        for index in source.reversed() { orderedItems.remove(at: index) }
        orderedItems.insert(contentsOf: moving, at: insertion)
    }

    mutating func setVisible(_ visible: Bool, for item: ToolbarItem) {
        guard !item.isRequired else { return }
        if visible { hiddenItems.remove(item.rawValue) }
        else { hiddenItems.insert(item.rawValue) }
    }
}

/// Keep the primary strip on one line; secondary actions retain their configured order in More.
struct ToolbarLayout {
    static let buttonSize: CGFloat = 30
    static let spacing: CGFloat = 3
    static let padding: CGFloat = 6

    let rows: [[ToolbarItem]]
    let overflowItems: [ToolbarItem]
    let size: CGSize

    init(items: [ToolbarItem], availableWidth: CGFloat) {
        let columns = max(3, min(14, Int((availableWidth - Self.padding * 2 + Self.spacing)
            / (Self.buttonSize + Self.spacing))))
        let secondary: Set<ToolbarItem> = [.pin, .ocr, .longCapture, .saveAs, .blur]
        let needsOverflow = items.count > columns || items.contains(where: secondary.contains)
        let capacity = max(2, columns - (needsOverflow ? 1 : 0))
        let pinned = items.filter { $0.isRequired || $0 == .translate || $0 == .style }
        var visible = Set(items.filter(\.isRequired))
        for item in pinned where visible.count < capacity { visible.insert(item) }
        for item in items where !secondary.contains(item) && visible.count < capacity { visible.insert(item) }
        if !needsOverflow { visible = Set(items) }
        let primary = items.filter(visible.contains)
        overflowItems = items.filter { !visible.contains($0) }
        rows = [primary]
        let columnCount = primary.count + (overflowItems.isEmpty ? 0 : 1)
        size = CGSize(
            width: CGFloat(columnCount) * Self.buttonSize + CGFloat(max(0, columnCount - 1)) * Self.spacing + Self.padding * 2,
            height: Self.buttonSize + Self.padding * 2
        )
    }

    func position(selection: CGRect, screenSize: CGSize, accessorySize: CGSize = .zero) -> CGPoint {
        let size = CGSize(width: max(size.width, accessorySize.width),
                          height: size.height + accessorySize.height)
        let margin: CGFloat = 10
        let below = selection.maxY + margin + size.height / 2
        let above = selection.minY - margin - size.height / 2
        let preferredY = below + size.height / 2 <= screenSize.height - margin ? below : above
        return CGPoint(
            x: max(margin + size.width / 2, min(selection.midX, screenSize.width - margin - size.width / 2)),
            y: max(margin + size.height / 2, min(preferredY, screenSize.height - margin - size.height / 2))
        )
    }

    func tooltipFrame(for item: ToolbarItem, tooltipSize: CGSize, toolbarCenter: CGPoint, screenSize: CGSize) -> CGRect {
        let margin: CGFloat = 10
        let width = min(tooltipSize.width, max(0, screenSize.width - margin * 2))
        var anchorX = toolbarCenter.x
        if let row = rows.first(where: { $0.contains(item) }), let column = row.firstIndex(of: item) {
            let count = row.count + (overflowItems.isEmpty ? 0 : 1)
            let rowWidth = CGFloat(count) * Self.buttonSize + CGFloat(count - 1) * Self.spacing
            anchorX = toolbarCenter.x - rowWidth / 2 + CGFloat(column) * (Self.buttonSize + Self.spacing) + Self.buttonSize / 2
        }
        let below = toolbarCenter.y + size.height / 2 + 6
        let above = toolbarCenter.y - size.height / 2 - 6 - tooltipSize.height
        let preferredY = below + tooltipSize.height <= screenSize.height - margin ? below : above
        return CGRect(
            x: max(margin, min(anchorX - width / 2, screenSize.width - margin - width)),
            y: max(margin, min(preferredY, screenSize.height - margin - tooltipSize.height)),
            width: width, height: tooltipSize.height
        )
    }
}
