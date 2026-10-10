import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var settings = SettingsService.shared
    let layout: ToolbarLayout
    var toolbarPosition: CGPoint? = nil
    var screenSize: CGSize? = nil
    var tooltipAbove = false
    @State private var hoveredItem: ToolbarItem?

    var body: some View {
        VStack(spacing: ToolbarLayout.spacing) {
            ForEach(layout.rows.indices, id: \.self) { row in
                HStack(spacing: ToolbarLayout.spacing) {
                    ForEach(layout.rows[row]) { item in
                        toolbarButton(item)
                    }
                }
            }
        }
        .padding(ToolbarLayout.padding)
        .frame(width: layout.size.width, height: layout.size.height)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .overlay(alignment: .topLeading) {
            if let item = hoveredItem {
                let text = help(for: item)
                let textSize = (text as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium)
                ])
                let tooltipSize = CGSize(width: ceil(textSize.width) + 16, height: ceil(textSize.height) + 10)
                let screen = screenSize ?? CGSize(width: max(layout.size.width, tooltipSize.width) + 20, height: layout.size.height + 100)
                let center = toolbarPosition ?? CGPoint(x: screen.width / 2, y: layout.size.height / 2 + 10)
                let frame = layout.tooltipFrame(for: item, tooltipSize: tooltipSize, toolbarCenter: center, screenSize: screen, preferAbove: tooltipAbove)
                ToolbarTooltipView(text: text)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX - (center.x - layout.size.width / 2),
                              y: frame.midY - (center.y - layout.size.height / 2))
                    .allowsHitTesting(false)
            }
        }
        .onDisappear { hoveredItem = nil }
    }

    private func toolbarButton(_ item: ToolbarItem) -> some View {
        ZStack {
            Button(action: { perform(item) }) {
                Group {
                    if item == .style {
                        Image(systemName: "gearshape").font(.system(size: 16))
                    } else if item == .mosaic || item == .blur {
                        EffectToolIcon(tool: item)
                    } else {
                        Image(systemName: item.iconName)
                            .font(.system(size: 16, weight: .regular))
                    }
                }
                .foregroundColor(tint(for: item))
                .frame(width: ToolbarLayout.buttonSize, height: ToolbarLayout.buttonSize)
                .background(RoundedRectangle(cornerRadius: 6).fill(buttonBackground(item)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled(item))
            .opacity(isDisabled(item) ? 0.5 : 1)
            .accessibilityLabel(item == .style ? "工具属性" : item.title)
            .accessibilityHint(help(for: item))
            .accessibilityValue(isSelected(item) ? "已选中" : "")
        }
        // Track the outer container so disabled buttons also explain their purpose.
        .onHover { isInside in
            if isInside { hoveredItem = item }
            else if hoveredItem == item { hoveredItem = nil }
        }
    }

    private func isSelected(_ item: ToolbarItem) -> Bool {
        if item == .translate { return viewModel.translationSource != nil }
        if item == .select { return viewModel.selectedTool == nil }
        guard let tool = item.annotationType else { return false }
        return viewModel.selectedTool == tool
    }

    private func isDisabled(_ item: ToolbarItem) -> Bool {
        !viewModel.isToolbarItemEnabled(item)
    }

    private func buttonBackground(_ item: ToolbarItem) -> Color {
        if isSelected(item) { return Color.accentColor.opacity(0.15) }
        return hoveredItem == item ? Color.primary.opacity(0.08) : .clear
    }

    private func tint(for item: ToolbarItem) -> Color {
        if isSelected(item) { return .accentColor }
        switch item {
        case .cancel: return .red
        default: return .primary
        }
    }

    private func help(for item: ToolbarItem) -> String {
        let label: String
        switch item {
        case .complete:
            label = settings.autoSaveEnabled ? "完成：复制并自动保存" : "完成：复制到剪贴板"
        case .save: label = "保存到预设目录"
        case .mosaic: label = "马赛克：支持涂抹和框选，拖动时预览；在属性栏切换"
        case .blur: label = "模糊：支持涂抹和框选，拖动时预览；在属性栏切换"
        case .style: label = viewModel.propertyTitle
        case .undo where isDisabled(item): label = "撤销（当前没有标注）"
        case .longCapture where isDisabled(item): label = "长截图（请先撤销标注并结束文字编辑）"
        case .translate where isDisabled(item): label = "原图翻译需要 macOS 26 或更新版本"
        case .translate where viewModel.translationSource != nil: label = "点击选区切换原文/译文；点击此按钮显示或隐藏翻译设置"
        default: label = item.title
        }
        return viewModel.shortcutTitle(for: item).map { "\(label)（\($0)）" } ?? label
    }

    private func perform(_ item: ToolbarItem) {
        viewModel.performToolbarItem(item)
    }
}

/// A stable palette symbol; only the thin indicator follows the annotation color.
struct ToolbarColorIcon: View {
    var selectedColor: Color? = nil

    private static let swatches: [[Color]] = [
        [Color(red: 0.94, green: 0.28, blue: 0.27), Color(red: 0.98, green: 0.76, blue: 0.20)],
        [Color(red: 0.22, green: 0.53, blue: 0.94), Color(red: 0.22, green: 0.71, blue: 0.40)]
    ]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<2) { row in
                HStack(spacing: 2) {
                    ForEach(0..<2) { column in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Self.swatches[row][column])
                            .frame(width: 8, height: 8)
                    }
                }
            }
            if let selectedColor {
                RoundedRectangle(cornerRadius: 1)
                    .fill(selectedColor)
                    .frame(width: 18, height: 2)
                    .overlay(RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Render in the screenshot window: a system help window sits below its screen-saver level.
struct ToolbarTooltipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.92)))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .accessibilityIdentifier("toolbar-tooltip")
    }
}

// Always visible while a tool or an existing annotation is selected.
struct ToolPropertyBarView: View {
    @ObservedObject var viewModel: OverlayViewModel

    let availableWidth: CGFloat
    @State private var numberColorRole: NumberColorRole = .fill

    static func size(for model: OverlayViewModel, availableWidth: CGFloat) -> CGSize {
        guard let tool = model.propertyTool else { return .zero }
        let extraRow = tool == .rectangle || ((tool == .mosaic || tool == .blur) && model.effectDrawingMode(for: tool) == .brush)
        return CGSize(width: min(400, max(0, availableWidth)), height: tool == .number ? 180 : (tool == .rectangle ? 144 : (extraRow ? 140 : 108)))
    }

    private struct ColorPreset {
        let color: Color
        let name: String
    }

    private static let colorPresets: [ColorPreset] = [
        ColorPreset(color: .red, name: "红色"),
        ColorPreset(color: .orange, name: "橙色"),
        ColorPreset(color: .yellow, name: "黄色"),
        ColorPreset(color: .green, name: "绿色"),
        ColorPreset(color: .blue, name: "蓝色"),
        ColorPreset(color: .purple, name: "紫色"),
        ColorPreset(color: .black, name: "黑色"),
        ColorPreset(color: .white, name: "白色"),
    ]

    private static let fontSizeOptions: [CGFloat] = [14, 16, 20, 24, 32, 40, 48, 64]

    private var colorBinding: Binding<Color> {
        Binding(
            get: { activeColor },
            set: { setActiveColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.propertyTitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("恢复默认") { viewModel.restoreCurrentToolDefaults() }
                    .buttonStyle(.plain).font(.caption)
                    .accessibilityLabel("恢复本工具默认值")
            }.frame(height: 20)
            if let tool = viewModel.propertyTool {
                if tool == .mosaic || tool == .blur {
                    Picker("应用方式", selection: Binding(
                        get: { viewModel.effectDrawingMode(for: tool) },
                        set: { viewModel.setEffectDrawingMode($0, for: tool) }
                    )) {
                        ForEach(EffectDrawingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if viewModel.effectDrawingMode(for: tool) == .brush {
                        effectPresets("笔刷大小", parameter: "width", values: [20, 36, 60, 90, 120])
                    }
                    if tool == .mosaic {
                        effectPresets("颗粒大小", parameter: "block", values: [8, 12, 16, 24, 32])
                    } else {
                        effectPresets("模糊强度", parameter: "radius", values: [4, 8, 12, 20, 32])
                    }
                } else {
                    if tool == .number {
                        Picker("颜色对象", selection: Binding(get: { activeNumberColorRole }, set: { numberColorRole = $0 })) {
                            ForEach(NumberColorRole.allCases.filter { $0 != .fill || viewModel.currentToolStyle.numberStyle == .filled }) { role in
                                Text(role.title).tag(role)
                            }
                        }.pickerStyle(.segmented).frame(height: 28)
                    }
                    colorControls
                    if [.pen, .rectangle, .ellipse, .arrow].contains(tool) {
                        valuePresets("粗细", values: [1, 2, 3, 5, 8, 12],
                                     selected: viewModel.currentToolStyle.lineWidth, action: viewModel.setLineWidth)
                    }
                    if tool == .rectangle {
                        valuePresets("圆角", values: [0, 4, 8, 16, 24, 32],
                                     selected: viewModel.currentToolStyle.rectangleCornerRadius ?? 0,
                                     action: viewModel.setRectangleCornerRadius)
                    }
                    if tool == .text || tool == .number {
                        valuePresets("字号", values: Self.fontSizeOptions,
                                     selected: viewModel.currentToolStyle.fontSize, action: viewModel.setFontSize)
                    }
                    if tool == .number {
                        Picker("序号样式", selection: Binding(
                            get: { viewModel.currentToolStyle.numberStyle },
                            set: { viewModel.setNumberStyle($0) }
                        )) {
                            ForEach(NumberAnnotationStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

            } else {
                Text("先选择一个标注工具或已有标注").foregroundStyle(.secondary)
            }
        }
        .onChange(of: viewModel.currentToolStyle.numberStyle) { style in
            if style == .outline && numberColorRole == .fill { numberColorRole = .border }
        }
        .padding(8)
        .frame(width: Self.size(for: viewModel, availableWidth: availableWidth).width,
               height: Self.size(for: viewModel, availableWidth: availableWidth).height)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .contentShape(Rectangle())
        .accessibilityIdentifier("tool-property-bar")
    }

    private var activeNumberColorRole: NumberColorRole {
        numberColorRole == .fill && viewModel.currentToolStyle.numberStyle == .outline ? .border : numberColorRole
    }
    private var activeColor: Color {
        viewModel.propertyTool == .number ? viewModel.numberColor(for: activeNumberColorRole) : viewModel.currentToolStyle.color
    }
    private func setActiveColor(_ color: Color) {
        if viewModel.propertyTool == .number { viewModel.setNumberColor(color, role: activeNumberColorRole) }
        else { viewModel.setColor(color) }
    }
    private func isSelectedColor(_ color: Color) -> Bool {
        if viewModel.propertyTool == .number && activeNumberColorRole == .border &&
            viewModel.currentToolStyle.numberStyle == .filled && viewModel.currentToolStyle.numberBorderInk == nil { return false }
        let a = AnnotationInk(activeColor), b = AnnotationInk(color)
        return abs(a.red - b.red) < 0.00001 && abs(a.green - b.green) < 0.00001 && abs(a.blue - b.blue) < 0.00001
    }
    private var colorControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if viewModel.propertyTool == .number && activeNumberColorRole == .digit {
                    Button("自动") { viewModel.setNumberColor(nil, role: .digit) }
                        .buttonStyle(.plain).font(.caption).accessibilityLabel("数字自动配色")
                        .foregroundStyle(viewModel.currentToolStyle.numberDigitInk == nil ? Color.accentColor : Color.secondary)
                        .help("根据填充或边框自动选择数字颜色")
                } else if viewModel.propertyTool == .number && activeNumberColorRole == .border && viewModel.currentToolStyle.numberStyle == .filled {
                    Button("无") { viewModel.setNumberColor(nil, role: .border) }
                        .buttonStyle(.plain).font(.caption).accessibilityLabel("无序号边框")
                        .foregroundStyle(viewModel.currentToolStyle.numberBorderInk == nil ? Color.accentColor : Color.secondary)
                        .help("移除实心序号的边框")
                } else {
                    Text(viewModel.propertyTool == .number ? activeNumberColorRole.title : "颜色").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Self.colorPresets, id: \.name) { preset in
                    Button(action: { setActiveColor(preset.color) }) {
                        RoundedRectangle(cornerRadius: 3).fill(preset.color).frame(width: 22, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            .overlay {
                                if isSelectedColor(preset.color) {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(preset.name == "白色" || preset.name == "黄色" ? Color.black : Color.white)
                                }
                            }
                    }
                    .buttonStyle(.plain).accessibilityLabel(viewModel.propertyTool == .number ? "\(activeNumberColorRole.title)\(preset.name)" : preset.name).help(preset.name)
                }
                ColorPicker("更多颜色…", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden().accessibilityLabel("更多颜色")
            }.frame(height: 28)
        }.frame(height: 28)
    }

    private func valuePresets(_ title: String, values: [CGFloat], selected: CGFloat,
                              action: @escaping (CGFloat) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("\(title) \(Int(selected))").font(.caption).foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .leading)
                ForEach(values, id: \.self) { value in
                    Button("\(Int(value))") { action(value) }
                        .buttonStyle(.plain)
                        .frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(selected == value ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
                        .accessibilityLabel("\(title) \(Int(value))")
                }
            }
        }.frame(height: 28)
    }

    private func effectPresets(_ title: String, parameter: String, values: [CGFloat]) -> some View {
        valuePresets(title, values: values, selected: viewModel.effectValue(parameter)) {
            viewModel.setEffectValue($0, parameter: parameter)
        }
    }

}

// Helper for blur background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }
    
    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

/// Pixel blocks versus a soft edge; both remain readable at toolbar size.
struct EffectToolIcon: View {
    let tool: ToolbarItem
    var body: some View {
        Group {
            if tool == .mosaic {
                Canvas { context, _ in
                    let shades: [Double] = [0.35, 0.85, 0.55, 0.95, 0.5, 0.75, 0.6, 0.9, 0.4]
                    for i in 0..<9 {
                        context.fill(Path(CGRect(x: (i % 3) * 6, y: (i / 3) * 6, width: 5, height: 5)),
                                     with: .color(.primary.opacity(shades[i])))
                    }
                }
                .frame(width: 17, height: 17)
            } else {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.2)).frame(width: 18, height: 18)
                    Circle().fill(Color.primary.opacity(0.35)).frame(width: 14, height: 14).blur(radius: 1)
                    Circle().fill(Color.primary.opacity(0.75)).frame(width: 8, height: 8).blur(radius: 1.5)
                }
                .frame(width: 18, height: 18)
            }
        }
        .accessibilityHidden(true)
    }
}
