import Cocoa
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct PinnedImageDocument {
    let baseImage: NSImage
    var annotations: [Annotation]
    let roundedCorners: Bool

    init(baseImage: NSImage, annotations: [Annotation] = [], origin: CGPoint = .zero,
         roundedCorners: Bool = SettingsService.shared.useRoundedCorners) {
        self.baseImage = baseImage
        self.annotations = annotations.map { original in
            var a = original
            a.startPoint.x -= origin.x; a.startPoint.y -= origin.y
            a.endPoint.x -= origin.x; a.endPoint.y -= origin.y
            a.points = a.points.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
            return a
        }
        self.roundedCorners = roundedCorners
    }

    func rendered() -> NSImage {
        let result = CaptureService.shared.composite(image: baseImage, annotations: annotations)
        return CaptureService.shared.styledImage(result, useRoundedCorners: roundedCorners)
    }
}

final class PinnedImagePresentation: ObservableObject {
    @Published var image: NSImage
    @Published var opacity: Double = 1
    @Published var editor: OverlayViewModel?
    init(image: NSImage) { self.image = image }
    func setOpacity(_ value: Double) { opacity = min(1, max(0.1, value)) }
}

final class PinnedImageWindow: OverlayWindow {
    var editingEnabled = false
    override var canBecomeKey: Bool { editingEnabled }
    override var canBecomeMain: Bool { editingEnabled }
}

class PinnedImageWindowController: NSWindowController, NSWindowDelegate {
    enum DisplayMode {
        case pinned
        case longCapturePreview
    }
    
    private var image: NSImage { presentation.image }
    let presentation: PinnedImagePresentation
    private(set) var pinDocument: PinnedImageDocument
    private let settings: SettingsService
    private var editorPanel: OverlayWindow?
    // Keep the undo history with the pin, including while its tools are hidden.
    private var editingModel: OverlayViewModel?
    private var editorDragOrigin: CGPoint?
    private var editorDragPointerOrigin: CGPoint?
    private var editorDragScale: CGFloat = 1
    private(set) var lastSavedURL: URL?
    private(set) var isSavingPin = false
    var savePinnedImage: (NSImage) async throws -> URL = { image in
        try await CaptureService.shared.saveImageDirectly(image)
    }
    private var editorSubscriptions = Set<AnyCancellable>()
    private var opacityRemainder: CGFloat = 0
    private let displayMode: DisplayMode
    private var onCopyAction: (() -> Void)?
    private var onSaveAction: (() -> Void)?
    private var onSaveAsAction: (() -> Void)?
    private var exportService: CaptureService?
    private var didTearDown = false
    private var minimumZoomScale: CGFloat = 0.1
    var onClose: (() -> Void)?

    init(
        image: NSImage,
        displayMode: DisplayMode = .pinned,
        sourceRect: CGRect? = nil,
        document: PinnedImageDocument? = nil,
        settings: SettingsService = .shared,
        screen: NSScreen? = nil,
        onCopyAction: (() -> Void)? = nil,
        onSaveAction: (() -> Void)? = nil,
        onSaveAsAction: (() -> Void)? = nil,
        onEditAction: (() -> Void)? = nil,
        exportService: CaptureService? = nil
    ) {
        self.presentation = PinnedImagePresentation(image: image)
        self.pinDocument = document ?? PinnedImageDocument(baseImage: image, roundedCorners: false)
        self.settings = settings
        self.displayMode = displayMode
        self.onCopyAction = onCopyAction
        self.onSaveAction = onSaveAction
        self.onSaveAsAction = onSaveAsAction
        self.exportService = exportService
        
        let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let initialFrame = Self.initialWindowFrame(for: image.size, displayMode: displayMode,
                                                  sourceRect: sourceRect, visibleFrame: visibleFrame,
                                                  screenFrames: NSScreen.screens.map(\.frame))
        
        let window = PinnedImageWindow(
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
        window.isReleasedWhenClosed = false
        if displayMode == .pinned {
            minimumZoomScale = min(0.1, initialFrame.width / max(1, image.size.width))
            window.minSize = NSSize(width: max(1, image.size.width * minimumZoomScale),
                                    height: max(1, image.size.height * minimumZoomScale))
            window.maxSize = NSSize(width: max(initialFrame.width, image.size.width * 8),
                                    height: max(initialFrame.height, image.size.height * 8))
            window.contentAspectRatio = initialFrame.size
        }
        
        super.init(window: window)
        window.delegate = self
        
        let contentView = PinnedImageView(
            presentation: presentation,
            displayMode: displayMode,
            onClose: { [weak self] in
                self?.close()
            },
            onCopy: { [weak self] in
                self?.handleCopy()
            },
            onSave: { [weak self] in
                self?.handleSave()
            },
            onSaveAs: { [weak self] in
                self?.handleSaveAs()
            },
            onEdit: displayMode == .pinned ? { [weak self] in self?.beginEditing() }
                : onEditAction.map { action in { [weak self] in self?.close(); action() } },
            onResetSize: { [weak self] in self?.restoreOriginalSize() },
            onFinishEditing: { [weak self] in self?.finishEditing() },
            onEditorMove: { [weak self] translation, ended in
                self?.moveEditingPinFromPointer(translation: translation, imageCoordinates: true, ended: ended)
            }
        )
        let hosting = PinnedImageHostingView(rootView: contentView)
        if displayMode == .pinned {
            // SwiftUI's intrinsic minimum must not enlarge small area screenshots.
            hosting.sizingOptions = []
            hosting.onScroll = { [weak self] event in self?.handleScroll(event) ?? false }
            hosting.onMagnify = { [weak self] event in self?.handleMagnify(event) ?? false }
        }
        window.contentView = hosting
        window.setFrame(initialFrame, display: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func close() {
        tearDown()
        super.close()
    }

    private func tearDown() {
        guard !didTearDown else { return }
        didTearDown = true
        endEditing()
        editingModel?.reset()
        editingModel = nil
        window?.delegate = nil
        window?.contentView = nil
        presentation.image = NSImage()
        pinDocument = PinnedImageDocument(baseImage: NSImage(), roundedCorners: false)
        onCopyAction = nil
        onSaveAction = nil
        onSaveAsAction = nil
        exportService = nil
        savePinnedImage = { _ in throw CancellationError() }
        let completion = onClose
        onClose = nil
        completion?()
    }
    
    func handleCopy() {
        guard !didTearDown else { return }
        if let onCopyAction {
            onCopyAction()
            if displayMode == .longCapturePreview { close() }
            return
        }
        
        currentExportService().copyToClipboard(imageForAction())
    }

    /// The presentation and rendered edit already have their final outline.
    func pngDataForSave() -> Data? {
        guard !didTearDown else { return nil }
        return currentExportService().pngData(from: imageForAction())
    }

    private func currentExportService() -> CaptureService {
        if let exportService { return exportService }
        let service = PinnedImageExportService()
        exportService = service
        return service
    }
    
    func handleSave() {
        guard !didTearDown else { return }
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
        
        savePanel.begin { [weak self] response in
            if response == .OK, let url = savePanel.url, let png = self?.pngDataForSave() {
                try? png.write(to: url)
            }
        }
    }

    func handleSaveAs() {
        guard !didTearDown else { return }
        if let onSaveAsAction {
            if displayMode == .longCapturePreview {
                close()
                DispatchQueue.main.async {
                    onSaveAsAction()
                }
            } else {
                onSaveAsAction()
            }
            return
        }
        // 未提供回调时，退回到默认保存面板
        handleSave()
    }
    
    static func initialWindowFrame(for imageSize: NSSize, displayMode: DisplayMode,
                                   sourceRect: CGRect?, visibleFrame: CGRect, screenFrames: [CGRect]) -> NSRect {
        if displayMode == .pinned, let sourceRect,
           sourceRect.width > 0, sourceRect.height > 0,
           screenFrames.contains(where: { $0.intersects(sourceRect) }) {
            return sourceRect
        }
        let fittedSize = fittedWindowSize(for: imageSize, in: visibleFrame, displayMode: displayMode)
        let x = visibleFrame.midX - fittedSize.width / 2
        let y = visibleFrame.midY - fittedSize.height / 2
        return NSRect(origin: NSPoint(x: x, y: y), size: fittedSize)
    }
    
    private static func fittedWindowSize(for imageSize: NSSize, in visibleFrame: NSRect, displayMode: DisplayMode) -> NSSize {
        let maxWidth = max(visibleFrame.width * 0.8, 360)
        let maxHeight = max(visibleFrame.height * 0.8, 280)
        
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSSize(width: min(maxWidth, 900), height: min(maxHeight, 700))
        }
        
        let widthScale = maxWidth / imageSize.width
        let heightScale = maxHeight / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)

        if displayMode == .pinned {
            return NSSize(width: max(1, imageSize.width * scale), height: max(1, imageSize.height * scale))
        }
        
        return NSSize(
            width: max(min(imageSize.width * scale, maxWidth), 360),
            height: max(min(imageSize.height * scale, maxHeight), 280)
        )
    }

    @discardableResult
    func handleScroll(_ event: NSEvent) -> Bool {
        guard displayMode == .pinned, event.type == .scrollWheel else { return false }
        // Do not keep resizing after the user has lifted their fingers.
        guard event.momentumPhase.isEmpty else { return true }
        let modifiers = event.modifierFlags.intersection([.command, .control, .shift, .option])
        guard modifiers.isEmpty || modifiers == .command || modifiers == .control else { return true }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return false }
        if modifiers == .control {
            opacityRemainder += event.hasPreciseScrollingDeltas ? delta / 8 : delta
            let steps = opacityRemainder.rounded(.towardZero)
            opacityRemainder -= steps
            presentation.setOpacity(presentation.opacity + Double(steps) * 0.05)
            return true
        }
        opacityRemainder = 0
        let factor = event.hasPreciseScrollingDeltas
            ? exp(min(40, max(-40, delta)) * 0.005)
            : pow(1.1, min(3, max(-3, delta)))
        zoom(by: factor, at: event.locationInWindow)
        return true
    }

    @discardableResult
    func handleMagnify(_ event: NSEvent) -> Bool {
        guard displayMode == .pinned, event.type == .magnify else { return false }
        zoom(by: exp(min(0.25, max(-0.25, event.magnification))), at: event.locationInWindow)
        return true
    }

    /// Read the current frame so dragging an edge and then scrolling share a scale.
    func zoom(by factor: CGFloat, at anchor: CGPoint) {
        guard displayMode == .pinned, let window,
              image.size.width > 0, image.size.height > 0, factor.isFinite, factor > 0 else { return }
        let current = window.frame
        let scale = current.width / image.size.width
        let nextScale = min(8, max(minimumZoomScale, scale * factor))
        let pixelScale = (window.screen ?? NSScreen.main)?.backingScaleFactor ?? 1
        func snap(_ value: CGFloat) -> CGFloat { (value * pixelScale).rounded() / pixelScale }
        // Snap before AppKit integralizes the frame: floating point values such as
        // 220.00000000003 otherwise gain a pixel and can move the anchor as well.
        let size = CGSize(width: max(1, snap(image.size.width * nextScale)),
                          height: max(1, snap(image.size.height * nextScale)))
        let origin = CGPoint(x: snap(current.minX + anchor.x * (1 - size.width / current.width)),
                             y: snap(current.minY + anchor.y * (1 - size.height / current.height)))
        window.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        positionEditorPanel()
    }

    func beginEditing() {
        guard !didTearDown, displayMode == .pinned, presentation.editor == nil, let window else { return }
        let model: OverlayViewModel
        if let retained = editingModel {
            model = retained
        } else {
            model = OverlayViewModel(settings: settings, useRoundedCorners: pinDocument.roundedCorners)
            model.captureMode = .imageEditor
            model.allowsCaptureCompletion = false
            model.selectionRect = CGRect(origin: .zero, size: pinDocument.baseImage.size)
            let cg = pinDocument.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            model.updatePreviewImage(cg, scale: CGFloat(cg?.width ?? 1) / max(1, pinDocument.baseImage.size.width))
            model.loadAnnotationsForEditing(pinDocument.annotations)
            editingModel = model
        }
        model.state = .editing
        model.onCancel = { [weak self] in self?.finishEditing() }
        model.onBlankDoubleClick = { [weak self] in self?.saveEditingPin() }
        model.onCapture = { [weak self] _, _, action, _ in
            if action == .save || action == .saveAs { self?.handleSave() }
        }
        presentation.editor = model
        model.$annotations.sink { [weak self] annotations in
            self?.pinDocument.annotations = annotations
        }.store(in: &editorSubscriptions)
        (window as? PinnedImageWindow)?.editingEnabled = true
        window.isMovableByWindowBackground = false
        let panel = OverlayWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = PinnedEditorHostingView(rootView: PinnedEditorTools(model: model,
            finish: { [weak self] in self?.finishEditing() },
            move: { [weak self] translation, ended in
                self?.moveEditingPinFromPointer(translation: translation, imageCoordinates: false, ended: ended)
            }))
        host.sizingOptions = []
        panel.contentView = host
        editorPanel = panel
        for keyWindow in [window as? OverlayWindow, panel].compactMap({ $0 }) {
            keyWindow.bindEditingActions(to: model)
            keyWindow.onEscapeKey = { [weak self] in self?.finishEditing() }
        }
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.positionEditorPanel() }
        }.store(in: &editorSubscriptions)
        positionEditorPanel()
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Hide the tools; edits are already live. Escape is not a rollback action.
    func finishEditing() {
        guard let model = presentation.editor else { return }
        model.commitTextInput()
        guard !model.isEditingText else { return }
        pinDocument.annotations = model.annotations
        presentation.image = pinDocument.rendered()
        endEditing()
    }

    /// Translation is in immutable image coordinates, not in the zoomed window.
    /// Use screen pointer positions once movement starts: local SwiftUI translation
    /// changes as the window itself moves and otherwise makes a drag oscillate.
    func moveEditingPinFromPointer(translation: CGSize, imageCoordinates: Bool, ended: Bool,
                                   pointer: CGPoint = NSEvent.mouseLocation) {
        guard presentation.editor != nil, let window else { return }
        let scale = window.frame.width / max(1, pinDocument.baseImage.size.width)
        if editorDragPointerOrigin == nil {
            let inputScale = imageCoordinates ? scale : 1
            editorDragPointerOrigin = CGPoint(x: pointer.x - translation.width * inputScale,
                                              y: pointer.y + translation.height * inputScale)
        }
        let start = editorDragPointerOrigin!
        moveEditingPin(by: CGSize(width: (pointer.x - start.x) / scale,
                                  height: (start.y - pointer.y) / scale), ended: ended)
        if ended { editorDragPointerOrigin = nil }
    }

    func moveEditingPin(by translation: CGSize, ended: Bool) {
        guard presentation.editor != nil, let window else { return }
        if editorDragOrigin == nil {
            editorDragOrigin = window.frame.origin
            editorDragScale = window.frame.width / max(1, pinDocument.baseImage.size.width)
        }
        let origin = editorDragOrigin!
        window.setFrameOrigin(CGPoint(x: origin.x + translation.width * editorDragScale,
                                     y: origin.y - translation.height * editorDragScale))
        positionEditorPanel()
        if ended { editorDragOrigin = nil }
    }

    func saveEditingPin() {
        guard !isSavingPin, presentation.editor != nil else { return }
        let output = imageForAction()
        guard presentation.editor?.isEditingText != true else { return }
        isSavingPin = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSavingPin = false }
            do { self.lastSavedURL = try await self.savePinnedImage(output) }
            catch is CancellationError { }
            catch {
                let alert = NSAlert()
                alert.messageText = "贴图保存失败"
                alert.informativeText = error.localizedDescription
                if let window = self.window { await alert.beginSheetModal(for: window) }
            }
        }
    }

    private func endEditing() {
        editorDragOrigin = nil
        editorDragPointerOrigin = nil
        editorSubscriptions.removeAll()
        if let panel = editorPanel {
            window?.removeChildWindow(panel)
            panel.clearEditingActions(); panel.onEscapeKey = nil; panel.contentView = nil; panel.close()
            editorPanel = nil
        }
        if let window = window as? PinnedImageWindow {
            window.clearEditingActions(); window.onEscapeKey = nil
            window.editingEnabled = false
            window.isMovableByWindowBackground = true
        }
        let model = presentation.editor
        presentation.editor = nil
        model?.onCancel = nil; model?.onCapture = nil; model?.onBlankDoubleClick = nil
    }

    private func imageForAction() -> NSImage {
        guard let model = presentation.editor else { return image }
        model.commitTextInput()
        var draft = pinDocument; draft.annotations = model.annotations
        return draft.rendered()
    }

    func windowDidMove(_ notification: Notification) { positionEditorPanel() }
    func windowDidResize(_ notification: Notification) { positionEditorPanel() }
    func windowWillClose(_ notification: Notification) {
        tearDown()
    }

    private func positionEditorPanel() {
        guard let model = presentation.editor, let panel = editorPanel, let window else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let available = min(720, visible.width - 20)
        let tools = model.visibleToolbarItems.filter { $0.annotationType != nil || $0 == .select || $0 == .undo }
        let layout = ToolbarLayout(items: tools, availableWidth: available - 16 - PinnedEditorTools.accessoryWidth)
        let headerWidth = layout.size.width + PinnedEditorTools.accessoryWidth
        let properties = ToolPropertyBarView.size(for: model, availableWidth: available - 16)
        let rawWidth = max(headerWidth, properties.width) + 16
        // Keep the centered header inset integral. AppKit rounds window origins;
        // an odd difference otherwise shifts left/right alignment by half a point.
        let width = headerWidth + ceil((rawWidth - headerWidth) / 2) * 2
        let height = layout.size.height + (properties.height > 0 ? properties.height + 8 : 0) + 16
        let x = PinnedEditorTools.preferredPanelX(imageFrame: window.frame, toolWidth: layout.size.width,
                                                panelWidth: width, alignment: model.toolbarAlignment)
        let below = window.frame.minY - height - 8
        let y = below >= visible.minY ? below : window.frame.maxY + 8
        panel.setFrame(CGRect(x: min(max(x, visible.minX + 10), visible.maxX - width - 10),
                             y: min(max(y, visible.minY + 10), visible.maxY - height - 10),
                             width: width, height: height), display: true)
    }

    func restoreOriginalSize() {
        guard displayMode == .pinned, let window, image.size.width > 0 else { return }
        zoom(by: image.size.width / window.frame.width,
             at: CGPoint(x: window.frame.width / 2, y: window.frame.height / 2))
    }
}

/// Handle only this image window's events; no global listener or input permission.
final class PinnedImageHostingView: NSHostingView<PinnedImageView> {
    var onScroll: ((NSEvent) -> Bool)?
    var onMagnify: ((NSEvent) -> Bool)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        rootView.presentation.editor != nil || super.acceptsFirstMouse(for: event)
    }

    func isImagePoint(_ pointInWindow: CGPoint) -> Bool {
        var target = super.hitTest(convert(pointInWindow, from: nil))
        while let view = target, view !== self {
            if view is NSTextView || view is NSControl || view is NSScrollView { return false }
            target = view.superview
        }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        if !isImagePoint(event.locationInWindow) || onScroll?(event) != true { super.scrollWheel(with: event) }
    }

    override func magnify(with event: NSEvent) {
        if !isImagePoint(event.locationInWindow) || onMagnify?(event) != true { super.magnify(with: event) }
    }
}

/// Avoid styling an already rendered pin again during file-backed PNG/TIFF export.
private final class PinnedImageExportService: CaptureService {
    override func styledImage(_ image: NSImage, useRoundedCorners: Bool? = nil) -> NSImage { image }
}

struct PinnedImageView: View {
    @ObservedObject var presentation: PinnedImagePresentation
    var image: NSImage { presentation.image }
    let displayMode: PinnedImageWindowController.DisplayMode
    var onClose: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void
    var onSaveAs: () -> Void
    var onEdit: (() -> Void)? = nil
    var onResetSize: () -> Void = {}
    var onFinishEditing: () -> Void = {}
    var onEditorMove: (CGSize, Bool) -> Void = { _, _ in }
    
    private var opacity: Double { presentation.opacity }
    
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
                    .onTapGesture(count: 2, perform: onClose)
            } else {
                Color.black.opacity(0.001)
                
                if let model = presentation.editor {
                    GeometryReader { geometry in
                        OverlayView(viewModel: model, showsToolbar: false, imageOpacity: opacity,
                                    onBlankCanvasDrag: onEditorMove)
                            .frame(width: image.size.width, height: image.size.height)
                            .scaleEffect(geometry.size.width / image.size.width, anchor: .topLeading)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    }
                } else {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).opacity(opacity)
                        .onTapGesture(count: 2, perform: onClose)
                }
            }
            
            if displayMode == .longCapturePreview {
                HStack(spacing: 8) {
                    if let onEdit {
                        Button(action: onEdit) { Image(systemName: "pencil.tip.crop.circle") }
                            .help("标注长截图").accessibilityLabel("标注长截图")
                    }
                    Button(action: onCopy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: onSave) {
                        Label("保存", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)

                    Button(action: onSaveAs) {
                        Label("另存为", systemImage: "square.and.arrow.down.on.square")
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
            if displayMode == .pinned {
                Divider()
                if presentation.editor != nil {
                    Button("结束编辑", action: onFinishEditing)
                } else {
                    Button("编辑标注") { onEdit?() }
                }
                Button("恢复原始大小", action: onResetSize)
            }
            Divider()
            Button("透明度: 100%") { presentation.setOpacity(1.0) }
            Button("透明度: 80%") { presentation.setOpacity(0.8) }
            Button("透明度: 50%") { presentation.setOpacity(0.5) }
            Button("透明度: 30%") { presentation.setOpacity(0.3) }
        }

    }
}

/// The image and its tools alternate key-window ownership. A toolbar click must
/// activate its window and perform the action in the same gesture.
final class PinnedEditorHostingView: NSHostingView<PinnedEditorTools> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PinnedEditorTools: View {
    static let accessoryWidth: CGFloat = 54
    static let gripWidth: CGFloat = 18
    static let controlSpacing: CGFloat = 3

    static func preferredPanelX(imageFrame: CGRect, toolWidth: CGFloat, panelWidth: CGFloat,
                                alignment: ToolbarAlignment) -> CGFloat {
        let toolLeft: CGFloat
        switch alignment {
        case .left: toolLeft = imageFrame.minX
        case .center: toolLeft = imageFrame.midX - toolWidth / 2
        case .right: toolLeft = imageFrame.maxX - toolWidth
        }
        let toolOffset = (panelWidth - toolWidth - accessoryWidth) / 2 + gripWidth + controlSpacing
        return toolLeft - toolOffset
    }
    @ObservedObject var model: OverlayViewModel
    let finish: () -> Void
    let move: (CGSize, Bool) -> Void
    var body: some View {
        GeometryReader { geometry in
            let tools = model.visibleToolbarItems.filter { $0.annotationType != nil || $0 == .select || $0 == .undo }
            let layout = ToolbarLayout(items: tools, availableWidth: geometry.size.width - 16 - Self.accessoryWidth)
            VStack(spacing: 8) {
                HStack(spacing: Self.controlSpacing) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(width: Self.gripWidth, height: layout.size.height)
                        .contentShape(Rectangle())
                        .help("拖动把手移动贴图")
                        .accessibilityLabel("移动贴图把手")
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { move($0.translation, false) }
                            .onEnded { move($0.translation, true) })
                    EditorToolbarView(viewModel: model, layout: layout)
                    Button(action: finish) { Image(systemName: "chevron.down").frame(width: 30, height: 30) }
                        .buttonStyle(.plain)
                        .help("收起工具栏，保留编辑（Esc）")
                        .accessibilityLabel("收起工具栏")
                }
                if model.propertyTool != nil {
                    ToolPropertyBarView(viewModel: model, availableWidth: geometry.size.width - 16)
                }
            }.padding(8)
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
