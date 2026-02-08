import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AnnotationType.allCases) { tool in
                let isSelected = viewModel.selectedTool == tool
                Button(action: {
                    viewModel.selectedTool = isSelected ? nil : tool
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
            .help("保存到文件")
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
