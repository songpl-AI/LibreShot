import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @ObservedObject private var settings = SettingsService.shared
    let layout: ToolbarLayout
    var toolbarPosition: CGPoint? = nil
    var screenSize: CGSize? = nil
    @State private var hoveredItem: ToolbarItem?

    var body: some View {
        VStack(spacing: ToolbarLayout.spacing) {
            ForEach(layout.rows.indices, id: \.self) { row in
                HStack(spacing: ToolbarLayout.spacing) {
                    ForEach(layout.rows[row]) { item in
                        if item == .style {
                            toolbarButton(item)
                                .popover(isPresented: $viewModel.showsStylePopover, arrowEdge: .bottom) {
                                    StylePopoverView(viewModel: viewModel).padding(12)
                                }
                        } else {
                            toolbarButton(item)
                        }
                    }
                    if !layout.overflowItems.isEmpty {
                        Menu {
                            ForEach(layout.overflowItems) { item in
                                Button { perform(item) } label: {
                                    Label(help(for: item), systemImage: item.iconName)
                                }.disabled(isDisabled(item))
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: ToolbarLayout.buttonSize, height: ToolbarLayout.buttonSize)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("更多工具")
                        .accessibilityLabel("更多工具")
                    }
                }
            }
        }
        .padding(ToolbarLayout.padding)
        .frame(width: layout.size.width, height: layout.size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                let frame = layout.tooltipFrame(for: item, tooltipSize: tooltipSize, toolbarCenter: center, screenSize: screen)
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
                        ToolbarColorIcon(selectedColor: viewModel.selectedColor)
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
            .accessibilityLabel(item.title)
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
        case .save: label = settings.autoSaveEnabled ? "保存到预设目录" : "保存…"
        case .undo where isDisabled(item): label = "撤销（当前没有标注）"
        case .longCapture where isDisabled(item): label = "长截图（请先撤销标注并结束文字编辑）"
        case .translate where isDisabled(item): label = "原图翻译需要 macOS 26 或更新版本"
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

// 样式面板：颜色 + 字号
struct StylePopoverView: View {
    @ObservedObject var viewModel: OverlayViewModel

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
            get: { viewModel.selectedColor },
            set: { viewModel.setColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("颜色").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(Self.colorPresets, id: \.name) { preset in
                        Button(action: { viewModel.setColor(preset.color) }) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                                .overlay(
                                    Circle().stroke(Color.blue, lineWidth: 2)
                                        .opacity(viewModel.selectedColor == preset.color ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }
                ColorPicker("更多颜色…", selection: colorBinding, supportsOpacity: false)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("字号").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(Self.fontSizeOptions, id: \.self) { size in
                        Button(action: { viewModel.setFontSize(size) }) {
                            Text("\(Int(size))")
                                .font(.system(size: 12))
                                .frame(width: 28, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(viewModel.selectedFontSize == size ? Color.blue.opacity(0.18) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(viewModel.selectedFontSize == size ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(width: 264)
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
