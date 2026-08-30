import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var showStylePopover = false

    var body: some View {
        HStack(spacing: 8) {
            // 选择/移动模式（无工具）
            let selectMode = viewModel.selectedTool == nil
            Button(action: {
                viewModel.selectTool(nil)
            }) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(selectMode ? .blue : .black.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(selectMode ? 0.22 : 0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("选择/移动")

            Divider()
                .frame(height: 20)
                .background(Color.black.opacity(0.12))

            ForEach(AnnotationType.allCases) { tool in
                let isSelected = viewModel.selectedTool == tool
                Button(action: {
                    viewModel.selectTool(isSelected ? nil : tool)
                }) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .padding(7)
                        .foregroundColor(isSelected ? .blue : .black.opacity(0.9))
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(isSelected ? 0.22 : 0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.black.opacity(0.12))

            // 样式按钮（颜色 + 字号）
            Button(action: {
                showStylePopover.toggle()
            }) {
                Circle()
                    .fill(viewModel.selectedColor)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("颜色与字号")
            .popover(isPresented: $showStylePopover, arrowEdge: .bottom) {
                StylePopoverView(viewModel: viewModel)
                    .padding(12)
            }

            Divider()
                .frame(height: 20)
                .background(Color.black.opacity(0.12))

            Button(action: {
                viewModel.undoLastAnnotation()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.black.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.annotations.isEmpty)
            .opacity(viewModel.annotations.isEmpty ? 0.5 : 1.0)
            
            Divider()
                .frame(height: 20)
                .background(Color.black.opacity(0.12))
            
            Button(action: {
                viewModel.cancel()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.black.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            // Pin Button (New)
            Button(action: {
                viewModel.confirmPin()
            }) {
                Image(systemName: "pin")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.orange)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("贴图到屏幕")

            Button(action: {
                viewModel.confirmOCR()
            }) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.blue)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("识别文字")
            
            if viewModel.captureMode == .normal {
                Button(action: {
                    viewModel.startLongCaptureFromToolbar()
                }) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .padding(7)
                        .foregroundColor(.purple)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.annotations.isEmpty || viewModel.isEditingText)
                .opacity((!viewModel.annotations.isEmpty || viewModel.isEditingText) ? 0.5 : 1.0)
                .help("开始长截图")
            }
            
            Button(action: {
                viewModel.confirmCopy()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.black.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板")

            Button(action: {
                viewModel.confirmSave()
            }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.black.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("保存")

            Button(action: {
                viewModel.confirmSaveAs()
            }) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 16, weight: .medium))
                    .padding(7)
                    .foregroundColor(.black.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("另存为...")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.98))
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
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
