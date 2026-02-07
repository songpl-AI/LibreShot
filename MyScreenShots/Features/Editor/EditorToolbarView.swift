import SwiftUI

struct EditorToolbarView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Tools
            ForEach(AnnotationType.allCases) { tool in
                Button(action: {
                    viewModel.selectedTool = (viewModel.selectedTool == tool) ? nil : tool
                }) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 16))
                        .padding(8)
                        .background(viewModel.selectedTool == tool ? Color.blue : Color.clear)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.5))
            
            // Undo
            Button(action: {
                viewModel.undoLastAnnotation()
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16))
                    .padding(8)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.annotations.isEmpty)
            .opacity(viewModel.annotations.isEmpty ? 0.5 : 1.0)
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.5))
            
            // Cancel
            Button(action: {
                viewModel.cancel()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .padding(8)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            
            // Confirm (Copy to Clipboard)
            Button(action: {
                viewModel.confirmCopy()
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16))
                    .padding(8)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
            .help("复制到剪贴板")

            // Save to File
            Button(action: {
                viewModel.confirmSave()
            }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16))
                    .padding(8)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help("保存到文件")
        }
        .padding(8)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(8)
        .shadow(radius: 4)
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
