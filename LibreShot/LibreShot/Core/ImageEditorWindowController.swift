import AppKit
import SwiftUI

/// An image document uses image points throughout; NSScrollView handles viewport transforms.
@MainActor
final class ImageEditorWindowController: NSWindowController, NSWindowDelegate {
    let model: OverlayViewModel
    private var image: NSImage?
    private var actionInFlight = false
    var onClose: (() -> Void)?
    var onAction: ((NSImage, CaptureAction) async throws -> Void)?

    init(image: NSImage, settings: SettingsService = .shared, screen: NSScreen? = nil) {
        self.image = image
        model = OverlayViewModel(settings: settings)
        model.captureMode = .imageEditor
        model.state = .editing
        model.selectionRect = CGRect(origin: .zero, size: image.size)
        model.applyInitialTool()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        model.updatePreviewImage(cg, scale: CGFloat(cg?.width ?? 1) / max(image.size.width, 1))
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = CGSize(width: min(max(560, image.size.width + 48), min(1100, visible.width * 0.9)),
                          height: min(max(480, image.size.height + 130), min(840, visible.height * 0.9)))
        let window = OverlayWindow(contentRect: CGRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                   backing: .buffered, defer: false)
        window.title = "截图标注"
        window.minSize = CGSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ImageEditorView(model: model, imageSize: image.size))
        window.bindEditingActions(to: model)
        window.onEscapeKey = { [weak self] in self?.close() }
        model.onCancel = { [weak self] in self?.close() }
        model.onCapture = { [weak self] _, _, action, base in self?.perform(action, base: base) }
        if screen != nil {
            window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2,
                                          y: visible.midY - window.frame.height / 2))
        } else {
            window.center()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func renderedImage(base: CGImage? = nil) -> NSImage {
        guard let image else { return NSImage() }
        model.commitTextInput()
        let background = (base ?? model.imageForExport()).map { NSImage(cgImage: $0, size: image.size) } ?? image
        return CaptureService.shared.composite(image: background, annotations: model.annotations)
    }

    private func perform(_ action: CaptureAction, base: CGImage?) {
        guard !actionInFlight, model.canExportSelection, let onAction else { return }
        actionInFlight = true
        let output = renderedImage(base: base)
        Task { [weak self] in
            guard let self else { return }
            defer { self.actionInFlight = false }
            do {
                try await onAction(output, action)
                // Saving keeps the editable document open, including when the user cancels a panel.
                if case .copy = action { self.close() }
                if case .saveAndCopy = action { self.close() }
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
        model.onCancel = nil
        model.reset()
        image = nil
        onAction = nil
        window?.contentView = nil
        let completion = onClose
        onClose = nil
        completion?()
    }
}

struct ImageEditorView: View {
    @ObservedObject var model: OverlayViewModel
    let imageSize: CGSize
    @State private var zoom: CGFloat = 1
    @State private var fitRequest = 0
    @State private var zoomMode: ImageEditorZoomMode = .fitWidth

    var body: some View {
        GeometryReader { geometry in
            let layout = ToolbarLayout(items: model.visibleToolbarItems, availableWidth: geometry.size.width - 24)
            VStack(spacing: 0) {
                GeometryReader { viewport in
                    ImageEditorScrollView(model: model, imageSize: imageSize, zoom: $zoom,
                                          zoomMode: $zoomMode, fitRequest: fitRequest, viewportSize: viewport.size)
                }
                VStack(spacing: 0) {
                EditorToolbarView(viewModel: model, layout: layout)
                    .zIndex(1)
                if model.propertyTool != nil {
                    ToolPropertyBarView(viewModel: model, availableWidth: geometry.size.width - 24)
                        .padding(.top, 8)
                }
                if #available(macOS 26.0, *), let source = model.translationSource {
                    InlineImageTranslationView(viewModel: model, image: source)
                        .id(model.translationSessionID).frame(width: min(430, geometry.size.width - 24))
                }
                HStack(spacing: 8) {
                    Text("\(Int(imageSize.width * model.previewScale)) × \(Int(imageSize.height * model.previewScale))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    Divider().frame(height: 14)
                    zoomButton("minus.magnifyingglass", title: "缩小") { setZoom(zoom / 1.25) }
                    Menu {
                        Button("适合宽度") { fit(.fitWidth) }
                        Button("显示全图") { fit(.fitImage) }
                        Button("100%") { setZoom(1) }
                    } label: {
                        Text("\(Int(zoom * 100))%").font(.system(size: 11)).monospacedDigit().frame(width: 46)
                    }.menuStyle(.borderlessButton).fixedSize().help("缩放比例")
                    zoomButton("plus.magnifyingglass", title: "放大") { setZoom(zoom * 1.25) }
                    Divider().frame(height: 14)
                    zoomButton("arrow.left.and.right", title: "适合宽度") { fit(.fitWidth) }
                    zoomButton("arrow.up.left.and.arrow.down.right", title: "显示全图") { fit(.fitImage) }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                .padding(.top, 8)
                }.padding(.top, 8).padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .onAppear { zoomMode = imageSize.height > imageSize.width * 1.6 ? .fitWidth : .fitImage }
    }

    private func zoomButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 22) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func setZoom(_ value: CGFloat) {
        model.commitTextInput()
        zoomMode = .custom
        zoom = min(4, max(0.05, value))
    }

    private func fit(_ mode: ImageEditorZoomMode) {
        model.commitTextInput()
        zoomMode = mode
        fitRequest += 1
    }
}

enum ImageEditorZoomMode { case fitWidth, fitImage, custom }

struct ImageEditorViewportLayout: Equatable {
    let zoom: CGFloat
    let documentSize: CGSize
    let imageOrigin: CGPoint

    init(imageSize: CGSize, viewport: CGSize, mode: ImageEditorZoomMode, zoom: CGFloat) {
        let width = max(1, viewport.width - 40), height = max(1, viewport.height - 40)
        let fitWidth = width / max(imageSize.width, 1)
        switch mode {
        case .fitWidth: self.zoom = min(1, fitWidth)
        case .fitImage: self.zoom = min(1, fitWidth, height / max(imageSize.height, 1))
        case .custom: self.zoom = min(4, max(0.05, zoom))
        }
        let scaled = CGSize(width: imageSize.width * self.zoom, height: imageSize.height * self.zoom)
        documentSize = CGSize(width: max(viewport.width, scaled.width + 40), height: max(viewport.height, scaled.height + 40))
        imageOrigin = CGPoint(x: (documentSize.width - scaled.width) / 2, y: (documentSize.height - scaled.height) / 2)
    }
}

struct ImageEditorScrollView: NSViewRepresentable {
    let model: OverlayViewModel
    let imageSize: CGSize
    @Binding var zoom: CGFloat
    @Binding var zoomMode: ImageEditorZoomMode
    let fitRequest: Int
    let viewportSize: CGSize
    @State private var measuredViewport: CGSize = .zero

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ImageEditorNativeScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.backgroundColor = .underPageBackgroundColor
        let layout = ImageEditorViewportLayout(imageSize: imageSize, viewport: viewportSize, mode: zoomMode, zoom: zoom)
        let host = NSHostingView(rootView: document(layout))
        host.sizingOptions = []
        host.isFlipped = true
        host.frame = CGRect(origin: .zero, size: layout.documentSize)
        scroll.documentView = host
        return scroll
    }

    private func document(_ layout: ImageEditorViewportLayout) -> AnyView {
        // Keep scaling inside SwiftUI so gesture locations and inline text share its transform.
        // NSScrollView magnification alone does not transform SwiftUI DragGesture coordinates.
        AnyView(ZStack(alignment: .topLeading) {
            OverlayView(viewModel: model, showsToolbar: false)
            .frame(width: imageSize.width, height: imageSize.height)
            .scaleEffect(layout.zoom, anchor: .topLeading)
            .frame(width: imageSize.width * layout.zoom, height: imageSize.height * layout.zoom, alignment: .topLeading)
            .offset(x: layout.imageOrigin.x, y: layout.imageOrigin.y)
        }.frame(width: layout.documentSize.width, height: layout.documentSize.height, alignment: .topLeading))
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.hasHorizontalScroller = zoomMode == .custom
        scroll.hasVerticalScroller = zoomMode != .fitImage
        (scroll as? ImageEditorNativeScrollView)?.onViewportChange = { size in
            guard size.width > 1, size.height > 1, size != measuredViewport else { return }
            DispatchQueue.main.async { measuredViewport = size }
        }
        (scroll as? ImageEditorNativeScrollView)?.onMagnify = { delta in
            model.commitTextInput()
            zoomMode = .custom
            zoom = min(4, max(0.05, zoom * (1 + delta)))
        }
        guard let host = scroll.documentView as? NSHostingView<AnyView> else { return }
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }
        let viewport = measuredViewport.width > 1 ? measuredViewport : viewportSize
        let layout = ImageEditorViewportLayout(imageSize: imageSize, viewport: viewport, mode: zoomMode, zoom: zoom)
        let needsFit = context.coordinator.fitRequest != fitRequest
        let previous = context.coordinator.layout ?? layout
        let origin = scroll.contentView.bounds.origin
        let center = CGPoint(x: (origin.x + scroll.contentSize.width / 2 - previous.imageOrigin.x) / previous.zoom,
                             y: (origin.y + scroll.contentSize.height / 2 - previous.imageOrigin.y) / previous.zoom)
        if layout != context.coordinator.layout || needsFit {
            host.rootView = document(layout)
            host.frame = CGRect(origin: .zero, size: layout.documentSize)
            scroll.layoutSubtreeIfNeeded()
            let next = needsFit ? CGPoint.zero : CGPoint(x: max(0, center.x * layout.zoom + layout.imageOrigin.x - scroll.contentSize.width / 2),
                                                         y: max(0, center.y * layout.zoom + layout.imageOrigin.y - scroll.contentSize.height / 2))
            scroll.contentView.scroll(to: next)
            scroll.reflectScrolledClipView(scroll.contentView)
            context.coordinator.layout = layout
        }
        context.coordinator.fitRequest = fitRequest
        if abs(zoom - layout.zoom) > 0.0001 { DispatchQueue.main.async { zoom = layout.zoom } }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll as? ImageEditorNativeScrollView)?.onMagnify = nil
        (scroll as? ImageEditorNativeScrollView)?.onViewportChange = nil
        scroll.documentView = nil
    }

    final class Coordinator {
        var fitRequest: Int?
        var layout: ImageEditorViewportLayout?
    }
}

private final class ImageEditorNativeScrollView: NSScrollView {
    var onMagnify: ((CGFloat) -> Void)?
    var onViewportChange: ((CGSize) -> Void)?
    private var lastViewport: CGSize = .zero
    override func magnify(with event: NSEvent) { onMagnify?(event.magnification) }
    override func layout() {
        super.layout()
        if contentSize != lastViewport {
            lastViewport = contentSize
            onViewportChange?(contentSize)
        }
    }
}
