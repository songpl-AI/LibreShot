import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class PinnedImageWindowController: NSWindowController {
    
    private let image: NSImage
    var onClose: (() -> Void)?
    
    init(image: NSImage) {
        self.image = image
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: image.size),
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
        
        // Center logic or default position (e.g. center of screen)
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - image.size.width / 2
            let y = screenRect.midY - image.size.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        super.init(window: window)
        
        let contentView = PinnedImageView(image: image, onClose: { [weak self] in
            self?.close()
            self?.onClose?()
        })
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PinnedImageView: View {
    let image: NSImage
    var onClose: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .opacity(opacity)
            .contextMenu {
                Button("关闭") {
                    onClose()
                }
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                Divider()
                Button("保存...") {
                    saveImage()
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
    
    func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "PinnedImage.png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
            }
        }
    }
}
