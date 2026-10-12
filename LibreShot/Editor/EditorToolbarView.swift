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
        case .pin: label = "贴图到屏幕：在截图位置显示，可滚轮缩放"
        case .mosaic: label = "马赛克"
        case .blur: label = "模糊"
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

/// Compact rows share their measured layout with overlay positioning and hit exclusion.
struct ToolPropertyBarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    let availableWidth: CGFloat
    @State private var numberColorRole: NumberColorRole = .fill

    static let inset: CGFloat = 4
    static let spacing: CGFloat = 4

    enum Control: Hashable {
        case color, width, corner, font, numberStyle, effectMode, brush, block, blur, details, actions, collapse
        var width: CGFloat {
            switch self {
            case .color: return 102
            case .numberStyle: return 88
            case .effectMode: return 110
            case .details, .actions, .collapse: return 24
            default: return 140
            }
        }
    }

    static func rows(for model: OverlayViewModel, availableWidth: CGFloat) -> [[Control]] {
        guard let tool = model.propertyTool else { return [] }
        var controls: [Control]
        switch tool {
        case .rectangle: controls = [.color, .width, .corner]
        case .pen, .ellipse, .arrow: controls = [.color, .width]
        case .text: controls = [.color, .font]
        case .number: controls = [.numberStyle, .color, .font, .details]
        case .mosaic, .blur:
            controls = [.effectMode]
            if model.effectDrawingMode(for: tool) == .brush { controls.append(.brush) }
            controls.append(tool == .mosaic ? .block : .blur)
        }
        controls.append(contentsOf: [.actions, .collapse])
        let usable = max(0, availableWidth - inset * 2)
        var rows: [[Control]] = [[]]
        var used: CGFloat = 0
        for control in controls {
            let width = min(control.width, usable)
            if !rows[rows.count - 1].isEmpty && used + spacing + width > usable {
                rows.append([]); used = 0
            }
            if !rows[rows.count - 1].isEmpty { used += spacing }
            rows[rows.count - 1].append(control); used += width
        }
        return rows
    }

    static func size(for model: OverlayViewModel, availableWidth: CGFloat) -> CGSize {
        guard model.propertyTool != nil else { return .zero }
        let rows = rows(for: model, availableWidth: availableWidth)
        let rowWidth = rows.map { row in row.reduce(CGFloat(0)) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * spacing }.max() ?? 0
        if model.toolPropertiesCollapsed { return CGSize(width: min(availableWidth, 120), height: 28) }
        let detailHeight: CGFloat = model.propertyTool == .number && model.toolPropertyDetailsExpanded ? spacing + 64 : 0
        return CGSize(width: min(availableWidth, rowWidth + inset * 2), height: inset * 2 + CGFloat(rows.count) * 24 + CGFloat(max(0, rows.count - 1)) * spacing + detailHeight)
    }

    private struct ColorPreset {
        let color: Color
        let name: String
    }
    private static let colorPresets = [
        ColorPreset(color: .red, name: "红色"), ColorPreset(color: .green, name: "绿色"),
        ColorPreset(color: .blue, name: "蓝色")
    ]

    var body: some View {
        let size = Self.size(for: viewModel, availableWidth: availableWidth)
        VStack(alignment: .leading, spacing: Self.spacing) {
            if viewModel.toolPropertiesCollapsed {
                Button { viewModel.toolPropertiesCollapsed = false } label: {
                    Label("展开属性", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11)).frame(maxWidth: .infinity, minHeight: 20)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("展开工具属性")
            } else {
                let rows = Self.rows(for: viewModel, availableWidth: availableWidth)
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: Self.spacing) {
                        ForEach(rows[index], id: \.self) { item in
                            control(item).frame(width: min(item.width, max(0, size.width - Self.inset * 2)), height: 24)
                        }
                    }
                }
                if viewModel.propertyTool == .number && viewModel.toolPropertyDetailsExpanded {
                    numberDetails
                }
            }
        }
        .padding(Self.inset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .contentShape(Rectangle())
        .accessibilityIdentifier("tool-property-bar")
        .onDisappear { viewModel.endToolPropertyAdjustment() }
    }

    @ViewBuilder private func control(_ item: Control) -> some View {
        switch item {
        case .color: colorControls(role: quickColorRole)
        case .width: numericControl("粗细", range: 1...20, value: viewModel.currentToolStyle.lineWidth, ticks: [1, 3, 5, 8, 12, 20], action: viewModel.setLineWidth)
        case .corner: numericControl("圆角", range: 0...128, value: viewModel.currentToolStyle.rectangleCornerRadius ?? 0, ticks: [0, 4, 8, 16, 32, 64, 128], action: viewModel.setRectangleCornerRadius)
        case .font: numericControl("字号", range: 8...128, value: viewModel.currentToolStyle.fontSize, ticks: [8, 16, 24, 32, 48, 64, 128], action: viewModel.setFontSize)
        case .brush: numericControl("笔刷", range: 12...120, value: viewModel.effectValue("width"), ticks: [12, 20, 36, 60, 90, 120]) { viewModel.setEffectValue($0, parameter: "width") }
        case .block: numericControl("颗粒", range: 4...64, value: viewModel.effectValue("block"), ticks: [4, 8, 16, 24, 32, 64]) { viewModel.setEffectValue($0, parameter: "block") }
        case .blur: numericControl("强度", range: 2...32, value: viewModel.effectValue("radius"), ticks: [2, 4, 8, 12, 20, 32]) { viewModel.setEffectValue($0, parameter: "radius") }
        case .numberStyle:
            Picker("序号样式", selection: Binding(get: { viewModel.currentToolStyle.numberStyle }, set: { viewModel.setNumberStyle($0) })) {
                ForEach(NumberAnnotationStyle.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("序号样式")
        case .effectMode:
            if let tool = viewModel.propertyTool {
                Picker("应用方式", selection: Binding(get: { viewModel.effectDrawingMode(for: tool) }, set: { viewModel.setEffectDrawingMode($0, for: tool) })) {
                    ForEach(EffectDrawingMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("应用方式")
            }
        case .details:
            iconButton("slider.horizontal.3", label: viewModel.toolPropertyDetailsExpanded ? "收起详细颜色" : "更多颜色设置") {
                viewModel.toolPropertyDetailsExpanded.toggle()
            }
        case .collapse:
            iconButton("chevron.up", label: "收起工具属性") {
                viewModel.endToolPropertyAdjustment()
                viewModel.toolPropertiesCollapsed = true
            }.disabled(viewModel.isToolPropertyInputActive)
        case .actions:
            iconButton("arrow.counterclockwise", label: "恢复本工具默认值") { viewModel.restoreCurrentToolDefaults() }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private func numericControl(_ title: String, range: ClosedRange<CGFloat>, value: CGFloat, ticks: [CGFloat], action: @escaping (CGFloat) -> Void) -> some View {
        // Losing focus or switching an object must never apply a stale draft to another object.
        let tool = viewModel.propertyTool
        let annotationID = viewModel.selectedAnnotationID
        return CompactPropertySlider(title: title, range: range, value: value, ticks: ticks, viewModel: viewModel) { value in
            guard viewModel.propertyTool == tool, viewModel.selectedAnnotationID == annotationID else { return }
            action(value)
        }.id("\(String(describing: tool))-\(String(describing: annotationID))-\(title)")
    }

    private var quickColorRole: NumberColorRole {
        viewModel.currentToolStyle.numberStyle == .filled ? .fill : .border
    }
    private var activeNumberColorRole: NumberColorRole {
        numberColorRole == .fill && viewModel.currentToolStyle.numberStyle == .outline ? .border : numberColorRole
    }
    private func color(for role: NumberColorRole) -> Color {
        viewModel.propertyTool == .number ? viewModel.numberColor(for: role) : viewModel.currentToolStyle.color
    }
    private func setColor(_ color: Color, role: NumberColorRole) {
        if viewModel.propertyTool == .number { viewModel.setNumberColor(color, role: role) }
        else { viewModel.setColor(color) }
    }
    private func colorControls(role: NumberColorRole) -> some View {
        HStack(spacing: 2) {
            ForEach(Self.colorPresets, id: \.name) { preset in
                Button { setColor(preset.color, role: role) } label: {
                    RoundedRectangle(cornerRadius: 3).fill(preset.color).frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .overlay {
                            if AnnotationInk(color(for: role)) == AnnotationInk(preset.color) && !(viewModel.propertyTool == .number && role == .border && viewModel.currentToolStyle.numberStyle == .filled && viewModel.currentToolStyle.numberBorderInk == nil) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white)
                            }
                        }
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(viewModel.propertyTool == .number ? role.title : "颜色")\(preset.name)")
            }
            CompactPropertyColorWell(selection: Binding(get: { color(for: role) }, set: { setColor($0, role: role) }),
                label: "\(viewModel.propertyTool == .number ? role.title : "")自定义颜色")
                .frame(width: 24, height: 24)
        }
    }

    private var numberDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("颜色对象", selection: Binding(get: { activeNumberColorRole }, set: { numberColorRole = $0 })) {
                ForEach(NumberColorRole.allCases.filter { $0 != .fill || viewModel.currentToolStyle.numberStyle == .filled }) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("颜色对象").frame(height: 28)
            HStack(spacing: 8) {
                colorControls(role: activeNumberColorRole).frame(width: Control.color.width)
                if activeNumberColorRole == .digit {
                    Button("自动") { viewModel.setNumberColor(nil, role: .digit) }.buttonStyle(.plain).frame(width: 28).font(.caption)
                        .foregroundStyle(viewModel.currentToolStyle.numberDigitInk == nil ? Color.accentColor : Color.secondary)
                        .help("根据填充或边框自动选择数字颜色")
                } else if activeNumberColorRole == .border && viewModel.currentToolStyle.numberStyle == .filled {
                    Button("无") { viewModel.setNumberColor(nil, role: .border) }.buttonStyle(.plain).frame(width: 28).font(.caption)
                        .foregroundStyle(viewModel.currentToolStyle.numberBorderInk == nil ? Color.accentColor : Color.secondary)
                        .help("无序号边框").accessibilityLabel("无序号边框")
                }
            }.frame(height: 28)
        }
    }
}

/// A short slider for visual adjustment and a draft field for exact values.
struct CompactPropertySlider: View {
    let title: String
    let range: ClosedRange<CGFloat>
    let value: CGFloat
    let ticks: [CGFloat]
    @ObservedObject var viewModel: OverlayViewModel
    let action: (CGFloat) -> Void
    @State private var draft = ""
    @State private var originalDraft = ""
    @State private var inputID = UUID()
    @FocusState private var focused: Bool
    @State private var hovered = false

    static func formatted(_ value: CGFloat) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", Double(value))
    }

    static func parsed(_ text: String, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return nil }
        return min(max(CGFloat(value), range.lowerBound), range.upperBound)
    }

    private func commit() {
        // Merely focusing a rounded display value must not change a fractional saved value.
        if draft != originalDraft, let number = Self.parsed(draft, range: range) {
            draft = Self.formatted(number)
            originalDraft = draft
            if number != value { action(number) }
        } else {
            draft = Self.formatted(value)
            originalDraft = draft
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize()
            Slider(value: Binding(get: { value }, set: { action($0.rounded()) }), in: range) { editing in
                if editing { viewModel.beginToolPropertyAdjustment() }
                else { viewModel.endToolPropertyAdjustment() }
            }
            .accessibilityLabel(title).accessibilityValue("\(Self.formatted(value))")
            .overlay(PropertyWheelOverlay(value: value, range: range,
                enabled: !viewModel.isToolPropertyInputActive,
                target: "\(viewModel.propertyTool?.rawValue ?? ""):\(viewModel.selectedAnnotationID?.uuidString ?? "")",
                begin: { viewModel.beginToolPropertyAdjustment(owner: inputID) },
                end: { viewModel.endToolPropertyAdjustment(owner: inputID) },
                change: action))
            .onHover { hovered = $0 }
            .overlay(alignment: .top) {
                if hovered {
                    ToolbarTooltipView(text: "\(title)：\(Self.formatted(value)) · 滚轮调整")
                        .fixedSize().offset(y: -30).allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor.opacity(hovered ? 0.5 : 0), lineWidth: 1).allowsHitTesting(false))
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    Path { path in
                        for tick in ticks {
                            let x = 7 + (geometry.size.width - 14) * (tick - range.lowerBound) / (range.upperBound - range.lowerBound)
                            path.move(to: CGPoint(x: x, y: geometry.size.height - 3))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                    }.stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            TextField(title, text: $draft)
                .textFieldStyle(.roundedBorder).font(.system(size: 11).monospacedDigit())
                .multilineTextAlignment(.center).frame(width: 40)
                .focused($focused).accessibilityLabel("\(title)精确数值")
                .onSubmit { commit(); focused = false }
                .help("输入 \(Self.formatted(range.lowerBound))–\(Self.formatted(range.upperBound))；回车确认，Esc 取消")
        }
        .onAppear { draft = Self.formatted(value); originalDraft = draft }
        .onChange(of: value) { if !focused { draft = Self.formatted($0); originalDraft = draft } }
        .onChange(of: focused) { editing in
            if editing { originalDraft = draft; viewModel.beginToolPropertyValueEditing(inputID) }
            else { commit(); viewModel.endToolPropertyValueEditing(inputID) }
        }
        .onChange(of: viewModel.toolPropertyInputCancellation) { _ in
            if focused { draft = Self.formatted(value); originalDraft = draft; focused = false }
        }
        .onDisappear { viewModel.endToolPropertyValueEditing(inputID) }
    }
}

/// The overlay is hit only by wheel events, leaving native slider clicking/dragging intact.
struct PropertyWheelOverlay: NSViewRepresentable {
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let enabled: Bool
    let target: String
    let begin: () -> Void
    let end: () -> Void
    let change: (CGFloat) -> Void
    func makeNSView(context: Context) -> PropertyWheelView { PropertyWheelView() }
    func updateNSView(_ view: PropertyWheelView, context: Context) {
        if view.target != target || (!enabled && view.enabled) { view.finish() }
        view.target = target
        view.value = value; view.range = range; view.enabled = enabled
        view.begin = begin; view.end = end; view.change = change
    }
    static func dismantleNSView(_ view: PropertyWheelView, coordinator: ()) { view.finish() }
}

final class PropertyWheelView: NSView {
    var value: CGFloat = 0
    var range: ClosedRange<CGFloat> = 0...1
    var enabled = true
    var target = ""
    var begin: () -> Void = {}
    var end: () -> Void = {}
    var change: (CGFloat) -> Void = { _ in }
    private var remainder: CGFloat = 0
    private var adjusting = false
    private var finishTask: DispatchWorkItem?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
        return super.hitTest(point)
    }
    override func scrollWheel(with event: NSEvent) {
        // Consume the wheel here even when blocked, so it cannot scale the image.
        guard enabled, !(NSApp.keyWindow is NSColorPanel), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              event.momentumPhase.isEmpty else { return }
        remainder += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 8 : event.scrollingDeltaY
        let steps = remainder.rounded(.towardZero)
        remainder -= steps
        guard steps != 0 else { return }
        let next = min(range.upperBound, max(range.lowerBound, value + steps))
        guard next != value else { return }
        if !adjusting { begin(); adjusting = true }
        value = next; change(next)
        finishTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.finish() }
        finishTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }
    func finish() {
        finishTask?.cancel(); finishTask = nil; remainder = 0
        if adjusting { adjusting = false; end() }
    }
}

/// SwiftUI's color picker has a large intrinsic width on newer macOS versions.
/// The minimal native well keeps the same system color selection in a fixed square.
struct CompactPropertyColorWell: NSViewRepresentable {
    @Binding var selection: Color
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell(frame: .zero)
        well.colorWellStyle = .minimal
        if #available(macOS 14.0, *) { well.supportsAlpha = false }
        well.target = context.coordinator
        well.action = #selector(Coordinator.changeColor(_:))
        well.setContentHuggingPriority(.required, for: .horizontal)
        well.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateNSView(well, context: context)
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        context.coordinator.selection = $selection
        well.color = NSColor(selection)
        well.setAccessibilityLabel(label)
        well.toolTip = label
    }

    static func dismantleNSView(_ well: NSColorWell, coordinator: Coordinator) { well.deactivate() }

    class Coordinator: NSObject {
        var selection: Binding<Color>
        init(selection: Binding<Color>) { self.selection = selection }
        @objc func changeColor(_ well: NSColorWell) {
            selection.wrappedValue = Color(nsColor: well.color.withAlphaComponent(1))
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
