import AppKit
import SwiftUI

/// An image document uses image points throughout; NSScrollView handles viewport transforms.
@MainActor
final class ImageEditorWindowController: NSWindowController, NSWindowDelegate {
    let model: OverlayViewModel
    private let image: NSImage
    private var actionInFlight = false
    var onClose: (() -> Void)?
    var onAction: ((NSImage, CaptureAction) async throws -> Void)?

    init(image: NSImage, settings: SettingsService = .shared) {
        self.image = image
        model = OverlayViewModel(settings: settings)
        model.captureMode = .imageEditor
        model.state = .editing
        model.selectionRect = CGRect(origin: .zero, size: image.size)
        model.selectedTool = .rectangle
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        model.updatePreviewImage(cg, scale: CGFloat(cg?.width ?? 1) / max(image.size.width, 1))
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = CGSize(width: min(1000, visible.width * 0.9), height: min(800, visible.height * 0.9))
        let window = OverlayWindow(contentRect: CGRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                   backing: .buffered, defer: false)
        window.title = "长截图标注"
        window.minSize = CGSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ImageEditorView(model: model, imageSize: image.size))
        window.bindEditingActions(to: model)
        window.onEscapeKey = { [weak self] in self?.close() }
        model.onCancel = { [weak self] in self?.close() }
        model.onCapture = { [weak self] _, _, action, _ in self?.perform(action) }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func renderedImage() -> NSImage {
        model.commitTextInput()
        return CaptureService.shared.composite(image: image, annotations: model.annotations)
    }

    private func perform(_ action: CaptureAction) {
        guard !actionInFlight, let onAction else { return }
        actionInFlight = true
        let output = renderedImage()
        Task { [weak self] in
            guard let self else { return }
            defer { self.actionInFlight = false }
            do {
                try await onAction(output, action)
                // Saving keeps the editable document open, including when the user cancels a panel.
                if case .copy = action { self.close() }
            } catch is CancellationError {
            } catch {
                guard let window = self.window, window.isVisible else { return }
                let alert = NSAlert(error: error)
                await alert.beginSheetModal(for: window)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        (window as? OverlayWindow)?.clearEditingActions()
        model.onCapture = nil
        window?.contentView = nil
        onClose?()
    }
}

struct ImageEditorView: View {
    @ObservedObject var model: OverlayViewModel
    let imageSize: CGSize
    @State private var zoom: CGFloat = 1
    @State private var fitRequest = 0

    var body: some View {
        GeometryReader { geometry in
            let layout = ToolbarLayout(items: model.visibleToolbarItems, availableWidth: geometry.size.width - 24)
            VStack(spacing: 10) {
                HStack {
                    Text("长截图标注").font(.headline)
                    Spacer()
                    Button { model.commitTextInput(); zoom = max(0.05, zoom / 1.25) } label: { Label("缩小", systemImage: "minus.magnifyingglass") }
                        .labelStyle(.iconOnly).help("缩小")
                    Text("\(Int(zoom * 100))%")
                        .monospacedDigit().frame(width: 48)
                    Button { model.commitTextInput(); zoom = min(4, zoom * 1.25) } label: { Label("放大", systemImage: "plus.magnifyingglass") }
                        .labelStyle(.iconOnly).help("放大")
                    Button("适合宽度") { model.commitTextInput(); fitRequest += 1 }
                    Button("100%") { model.commitTextInput(); zoom = 1 }
                }.padding(.horizontal, 12)
                EditorToolbarView(viewModel: model, layout: layout)
                    .zIndex(1)
                ImageEditorScrollView(model: model, imageSize: imageSize, zoom: $zoom, fitRequest: fitRequest, viewportWidth: geometry.size.width)
            }
            .padding(.top, 12)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ImageEditorScrollView: NSViewRepresentable {
    let model: OverlayViewModel
    let imageSize: CGSize
    @Binding var zoom: CGFloat
    let fitRequest: Int
    let viewportWidth: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ImageEditorNativeScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = .underPageBackgroundColor
        let host = NSHostingView(rootView: document(at: zoom))
        host.sizingOptions = []
        host.isFlipped = true
        host.frame = CGRect(origin: .zero, size: scaledSize(zoom))
        scroll.documentView = host
        return scroll
    }

    private func scaledSize(_ zoom: CGFloat) -> CGSize {
        CGSize(width: imageSize.width * zoom, height: imageSize.height * zoom)
    }

    private func document(at zoom: CGFloat) -> AnyView {
        // Keep scaling inside SwiftUI so gesture locations and inline text share its transform.
        // NSScrollView magnification alone does not transform SwiftUI DragGesture coordinates.
        AnyView(OverlayView(viewModel: model, showsToolbar: false)
            .frame(width: imageSize.width, height: imageSize.height)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: imageSize.width * zoom, height: imageSize.height * zoom, alignment: .topLeading))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll as? ImageEditorNativeScrollView)?.onMagnify = { delta in
            model.commitTextInput()
            zoom = min(4, max(0.05, zoom * (1 + delta)))
        }
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        let needsFit = context.coordinator.fitRequest != fitRequest && viewportWidth > 1
        let target = needsFit ? min(1, max(0.05, (viewportWidth - 16) / max(imageSize.width, 1))) : zoom
        let previous = context.coordinator.lastZoom
        let origin = scroll.contentView.bounds.origin
        let center = CGPoint(x: (origin.x + scroll.contentSize.width / 2) / previous,
                             y: (origin.y + scroll.contentSize.height / 2) / previous)
        if target != previous || needsFit {
            host.rootView = document(at: target)
            host.frame = CGRect(origin: .zero, size: scaledSize(target))
            scroll.layoutSubtreeIfNeeded()
            let next = needsFit ? CGPoint.zero : CGPoint(x: max(0, center.x * target - scroll.contentSize.width / 2),
                                                         y: max(0, center.y * target - scroll.contentSize.height / 2))
            scroll.contentView.scroll(to: next)
            scroll.reflectScrolledClipView(scroll.contentView)
            context.coordinator.lastZoom = target
        }
        if needsFit {
            context.coordinator.fitRequest = fitRequest
            DispatchQueue.main.async { zoom = target }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll as? ImageEditorNativeScrollView)?.onMagnify = nil
        scroll.documentView = nil
    }

    final class Coordinator {
        var fitRequest: Int?
        var lastZoom: CGFloat = 1
    }
}

private final class ImageEditorNativeScrollView: NSScrollView {
    var onMagnify: ((CGFloat) -> Void)?
    override func magnify(with event: NSEvent) { onMagnify?(event.magnification) }
}
