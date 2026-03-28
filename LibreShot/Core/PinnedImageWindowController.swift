import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class PinnedImageWindowController: NSWindowController {
    enum DisplayMode {
        case pinned
        case longCapturePreview
    }
    
    private let image: NSImage
    private let displayMode: DisplayMode
    private let onCopyAction: (() -> Void)?
    private let onSaveAction: (() -> Void)?
    var onClose: (() -> Void)?
    
    init(
        image: NSImage,
        displayMode: DisplayMode = .pinned,
        onCopyAction: (() -> Void)? = nil,
        onSaveAction: (() -> Void)? = nil
    ) {
        self.image = image
        self.displayMode = displayMode
        self.onCopyAction = onCopyAction
        self.onSaveAction = onSaveAction
        
        let initialFrame = Self.initialWindowFrame(for: image.size)
        
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        
        super.init(window: window)
        
        let contentView = PinnedImageView(
            image: image,
            displayMode: displayMode,
            onClose: { [weak self] in
                self?.close()
            },
            onCopy: { [weak self] in
                self?.handleCopy()
            },
            onSave: { [weak self] in
                self?.handleSave()
            }
        )
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func close() {
        super.close()
        onClose?()
    }
    
    private func handleCopy() {
        if let onCopyAction {
            onCopyAction()
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
    
    private func handleSave() {
        if let onSaveAction {
            if displayMode == .longCapturePreview {
                close()
                DispatchQueue.main.async {
                    onSaveAction()
                }
            } else {
                onSaveAction()
            }
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "PinnedImage.png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiff = self.image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
            }
        }
    }
    
    private static func initialWindowFrame(for imageSize: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let fittedSize = fittedWindowSize(for: imageSize, in: visibleFrame)
        let x = visibleFrame.midX - fittedSize.width / 2
        let y = visibleFrame.midY - fittedSize.height / 2
        return NSRect(origin: NSPoint(x: x, y: y), size: fittedSize)
    }
    
    private static func fittedWindowSize(for imageSize: NSSize, in visibleFrame: NSRect) -> NSSize {
        let maxWidth = max(visibleFrame.width * 0.8, 360)
        let maxHeight = max(visibleFrame.height * 0.8, 280)
        
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: min(maxWidth, 900), height: min(maxHeight, 700))
        }
        
        let widthScale = maxWidth / imageSize.width
        let heightScale = maxHeight / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)
        
        return NSSize(
            width: max(min(imageSize.width * scale, maxWidth), 360),
            height: max(min(imageSize.height * scale, maxHeight), 280)
        )
    }
}

struct PinnedImageView: View {
    let image: NSImage
    let displayMode: PinnedImageWindowController.DisplayMode
    var onClose: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if displayMode == .longCapturePreview {
                Color.clear
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
                    .padding(8)
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(opacity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(16)
            } else {
                Color.black.opacity(0.001)
                
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(opacity)
            }
            
            if displayMode == .longCapturePreview {
                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: onSave) {
                        Label("保存", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                .padding(20)
            }
        }
        .contextMenu {
            Button("关闭") {
                onClose()
            }
            Button("复制") {
                onCopy()
            }
            Divider()
            Button("保存...") {
                onSave()
            }
            Divider()
            Button("透明度: 100%") { opacity = 1.0 }
            Button("透明度: 80%") { opacity = 0.8 }
            Button("透明度: 50%") { opacity = 0.5 }
            Button("透明度: 30%") { opacity = 0.3 }
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                onClose()
            }
        )
    }
}
