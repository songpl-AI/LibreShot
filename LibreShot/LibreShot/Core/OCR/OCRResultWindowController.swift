import Cocoa
import Combine
import CoreText
import SwiftUI
import Translation

class OCRResultWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var didClose = false
    
    convenience init(text: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OCR 识别结果"
        window.center()
        
        let contentView = OCRResultView(text: text)
        window.contentView = NSHostingView(rootView: contentView)
        
        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        guard !didClose else { return }
        didClose = true
        let close = onClose
        onClose = nil
        // Detach the SwiftUI tree and window even if another owner retains us.
        if let closingWindow = notification.object as? NSWindow {
            closingWindow.contentView = nil
            closingWindow.delegate = nil
        }
        window = nil
        close?()
        #if DEBUG
        MemoryTrace.markAfterRelease("ocr_result_window_closed")
        #endif
    }
}

struct OCRResultView: View {
    let text: String
    @State private var translatedText = ""
    @State private var translateError: String?

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(minHeight: 140)
            Divider()
            VStack(spacing: 10) {
                HStack {
                    Text("\(text.count) 字符").foregroundStyle(.secondary).font(.caption)
                    Spacer()
                    OCRCopyButton(text: text, title: "复制文本")
                        .keyboardShortcut("c", modifiers: .command)
                }
                if #available(macOS 26.0, *) {
                    HStack {
                        Text("翻译为").foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        OCRTranslationControls(text: text, translatedText: $translatedText, translateError: $translateError)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))

            if let error = translateError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 12)
            } else if !translatedText.isEmpty {
                Divider()
                HStack {
                    Text("译文").font(.headline)
                    Spacer()
                    OCRCopyButton(text: translatedText, title: "复制译文")
                }.padding(12)
                TextEditor(text: .constant(translatedText))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minHeight: 140)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

struct OCRCopyButton: View {
    let text: String
    let title: String
    @State private var copyID: UUID?

    var body: some View {
        Button {
            Self.copy(text, to: .general)
            copyID = UUID()
        } label: {
            Label(copyID == nil ? title : "已复制", systemImage: copyID == nil ? "doc.on.doc" : "checkmark")
                .frame(minWidth: 82)
                .fixedSize()
        }
        .disabled(text.isEmpty)
        .task(id: copyID) {
            guard copyID != nil else { return }
            do { try await Task.sleep(for: .seconds(2)); copyID = nil } catch { }
        }
        .onChange(of: text) { _ in copyID = nil }
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@available(macOS 26.0, *)
private struct OCRTranslationControls: View {
    let text: String
    @Binding var translatedText: String
    @Binding var translateError: String?
    @StateObject private var model = OCRTranslationModel()

    var body: some View {
        HStack {
            Picker("翻译为", selection: $model.targetLanguageID) {
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
                Text("日本語").tag("ja")
                Text("한국어").tag("ko")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
            .disabled(model.isTranslating)

            Button {
                model.start(text: text)
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        Image(systemName: "character.bubble").opacity(model.isTranslating ? 0 : 1)
                        if model.isTranslating { ProgressView().controlSize(.small) }
                    }.frame(width: 18, height: 18)
                    Text("翻译")
                }
                .frame(minWidth: 68)
                .fixedSize()
            }
            .disabled(model.isTranslating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("首次翻译可能需要联网下载免费语言包，系统会询问是否下载；安装后可离线翻译。")
        }
        .translationTask(model.configuration) { session in
            await model.run { text in
                try await TranslationService.translate(text, using: session)
            }
        }
        .onChange(of: model.translatedText) { _, value in translatedText = value }
        .onChange(of: model.errorMessage) { _, value in translateError = value }
        .onDisappear { model.cancel() }
    }
}

/// Stores only request/UI state, never a TranslationSession or language model.
@available(macOS 26.0, *)
@MainActor
final class OCRTranslationModel: ObservableObject {
    @Published var targetLanguageID = "zh-Hans"
    @Published private(set) var configuration: TranslationSession.Configuration?
    @Published private(set) var isTranslating = false
    @Published private(set) var translatedText = ""
    @Published private(set) var errorMessage: String?
    private var request: (id: UUID, text: String)?
    // A value only: changing its version makes same-language retries start a new task.
    private var lastConfiguration = TranslationSession.Configuration()

    func start(text: String) {
        guard !isTranslating, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        translatedText = ""
        let source = TranslationService.detectLanguage(of: text)
        let target = Locale.Language(identifier: targetLanguageID)
        if source == target {
            translatedText = text
            return
        }
        request = (UUID(), text)
        isTranslating = true
        #if DEBUG
        MemoryTrace.mark("ocr_text_translation_started")
        #endif
        lastConfiguration.source = source
        lastConfiguration.target = target
        lastConfiguration.invalidate()
        configuration = lastConfiguration
    }

    func run(translate: (String) async throws -> String) async {
        guard let current = request else { return }
        defer {
            if request?.id == current.id {
                request = nil
                configuration = nil
                isTranslating = false
                #if DEBUG
                MemoryTrace.mark("ocr_text_translation_finished")
                #endif
            }
        }
        do {
            try Task.checkCancellation()
            let result = try await translate(current.text)
            try Task.checkCancellation()
            guard request?.id == current.id else { return }
            translatedText = result
        } catch {
            guard request?.id == current.id else { return }
            if error is CancellationError || TranslationError.alreadyCancelled ~= error ||
                ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError) {
                errorMessage = "已取消翻译，可再次点击翻译重试。"
            } else {
                errorMessage = "翻译未完成：\(error.localizedDescription) 可再次点击翻译重试。"
            }
        }
    }

    func cancel() {
        request = nil
        configuration = nil
        isTranslating = false
        #if DEBUG
        MemoryTrace.mark("ocr_text_translation_cancelled")
        #endif
    }
}

// MARK: - In-place text layer

enum OCRTextLayerMode: String, CaseIterable, Identifiable {
    case layer, list
    var id: String { rawValue }
    var title: String { self == .layer ? "图层" : "列表" }
}

/// Owns the ordering, selection and copy state of one OCR result. The canvas
/// only paints; all mutations go through this model so tests do not need a window.
@MainActor
final class OCRTextLayerModel: ObservableObject {
    let image: NSImage
    let regions: [OCRTextRegion]
    let text: String
    @Published private(set) var selectedRanges: [Int: NSRange] = [:]
    @Published var mode: OCRTextLayerMode = .layer
    @Published private(set) var copyFeedback: String?
    var onClose: (() -> Void)?
    private var feedbackToken = UUID()

    init(image: NSImage, regions: [OCRTextRegion], text: String) {
        self.image = image
        self.regions = OCRTextRegion.readingOrder(from: regions)
        self.text = text.isEmpty ? self.regions.map(\.text).joined(separator: "\n") : text
    }

    var selectedIDs: Set<Int> { Set(selectedRanges.keys) }
    var selectedLineCount: Int { selectedRanges.count }
    var selectedCharacterCount: Int { selectedRanges.values.reduce(0) { $0 + $1.length } }
    var selectedCount: Int { selectedCharacterCount }
    var hasSelection: Bool { !selectedRanges.isEmpty }
    var isFullLineSelection: Bool {
        !selectedRanges.isEmpty && selectedRanges.allSatisfy { $0.value == fullRange(for: $0.key) }
    }
    var isAllSelected: Bool {
        !regions.isEmpty && selectedRanges.count == regions.count && isFullLineSelection
    }
    var selectionSummary: String {
        if selectedRanges.isEmpty { return "选择文字" }
        if isAllSelected { return "已全选 \(regions.count) 行" }
        return isFullLineSelection ? "已选 \(selectedRanges.count) 行" : "已选 \(selectedCharacterCount) 字"
    }
    var selectedText: String {
        regions.compactMap { region in
            guard let range = selectedRanges[region.id], range.length > 0 else { return nil }
            let value = region.text as NSString
            let start = min(max(0, range.location), value.length)
            let end = min(max(start, NSMaxRange(range)), value.length)
            guard end > start else { return nil }
            return value.substring(with: NSRange(location: start, length: end - start))
        }.joined(separator: "\n")
    }

    func applySelection(_ ids: Set<Int>, extending: Bool) {
        if extending {
            for id in ids { selectedRanges[id] = fullRange(for: id) }
        } else {
            selectedRanges = Dictionary(uniqueKeysWithValues: ids.map { ($0, fullRange(for: $0)) })
        }
    }

    func applyCharacterSelection(regionID: Int, range: NSRange, extending: Bool) {
        guard let region = regions.first(where: { $0.id == regionID }) else { return }
        let length = (region.text as NSString).length
        let start = min(max(0, range.location), length)
        let end = min(max(start, NSMaxRange(range)), length)
        guard end > start else {
            selectedRanges[regionID] = nil
            return
        }
        let next = NSRange(location: start, length: end - start)
        if extending, let old = selectedRanges[regionID] {
            let unionStart = min(old.location, next.location)
            let unionEnd = max(NSMaxRange(old), NSMaxRange(next))
            selectedRanges[regionID] = NSRange(location: unionStart, length: unionEnd - unionStart)
        } else {
            selectedRanges[regionID] = next
        }
    }

    func selectAll() {
        selectedRanges = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, fullRange(for: $0.id)) })
    }

    func clearSelection() {
        selectedRanges.removeAll()
    }

    func copyLine(_ id: Int) {
        selectedRanges = [id: fullRange(for: id)]
        copySelection()
    }

    func copySelection() {
        let copyingAll = selectedRanges.isEmpty
        let value = copyingAll ? regions.map(\.text).joined(separator: "\n") : selectedText
        guard !value.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        if copyingAll {
            showFeedback("已复制全部 \(regions.count) 行")
        } else if isFullLineSelection {
            showFeedback("已复制 \(selectedRanges.count) 行")
        } else {
            showFeedback("已复制 \(selectedCharacterCount) 字")
        }
    }

    func close() {
        onClose?()
    }

    private func fullRange(for id: Int) -> NSRange {
        guard let region = regions.first(where: { $0.id == id }) else { return NSRange(location: 0, length: 0) }
        return NSRange(location: 0, length: (region.text as NSString).length)
    }

    private func showFeedback(_ text: String) {
        copyFeedback = text
        let token = UUID()
        feedbackToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.feedbackToken == token else { return }
            self.copyFeedback = nil
        }
    }
}

@MainActor
final class OCRTextLayerWindowController: NSWindowController, NSWindowDelegate {
    let model: OCRTextLayerModel
    var onClose: (() -> Void)?

    init(image: NSImage, regions: [OCRTextRegion], text: String) {
        let model = OCRTextLayerModel(image: image, regions: regions, text: text)
        self.model = model
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let maxWidth = min(1000, visible.width * 0.9)
        let maxHeight = min(780, visible.height * 0.9)
        let widthScale = (maxWidth - 40) / max(image.size.width, 1)
        let heightScale = (maxHeight - 120) / max(image.size.height, 1)
        let imageScale = min(1, min(widthScale, heightScale))
        let contentWidth = max(680, image.size.width * imageScale + 40)
        let contentHeight = max(480, image.size.height * imageScale + 120)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "文字提取"
        window.minSize = CGSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        model.onClose = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: OCRTextLayerWorkspaceView(model: model))
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        model.onClose = nil
        window?.contentView = nil
        onClose?()
        onClose = nil
        #if DEBUG
        MemoryTrace.markAfterRelease("ocr_text_layer_window_closed")
        #endif
    }
}

private struct OCRTextLayerWorkspaceView: View {
    @ObservedObject var model: OCRTextLayerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("文字提取", systemImage: "doc.text.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                Text("识别到 \(model.regions.count) 行")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("显示方式", selection: $model.mode) {
                    ForEach(OCRTextLayerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 128)
                if model.mode == .list {
                    Button("完成") { model.close() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            if model.mode == .layer {
                OCRTextLayerView(model: model)
            } else {
                OCRResultView(text: model.text)
            }
        }
    }
}

private struct OCRTextLayerView: View {
    @ObservedObject var model: OCRTextLayerModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let imageRect = Self.fittedRect(for: model.image.size, in: geometry.size)
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    if imageRect.width > 0 {
                        Image(nsImage: model.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)
                    }
                    if model.regions.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 26))
                            Text("未识别到文字").font(.headline)
                            Text("可以切到“列表”查看原始结果").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        OCRTextLayerCanvas(model: model, imageRect: imageRect)
                    }
                }
            }
            bottomBar
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Image(systemName: model.hasSelection ? "checkmark.circle.fill" : "text.cursor")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.hasSelection ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectionSummary)
                    .font(.system(size: 12, weight: .semibold))
                Text(model.copyFeedback ?? (model.hasSelection
                    ? "⌘C 或 Return 复制选中 · 双击单行复制"
                    : "拖选文字 · 双击单行复制 · ⌘C 复制全部"))
                    .font(.system(size: 11))
                    .foregroundStyle(model.copyFeedback == nil ? Color.secondary : Color.green)
            }
            Spacer()
            Button("全选") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .buttonStyle(.borderless)
                .disabled(model.regions.isEmpty)
            Button("完成") { model.close() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderless)
            Button {
                model.copySelection()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc")
                    Text(model.hasSelection ? "复制" : "复制全部")
                    Text("⌘C").font(.system(size: 10, weight: .medium)).opacity(0.75)
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(model.regions.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private static func fittedRect(for imageSize: CGSize, in available: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let inset: CGFloat = 20
        let width = max(1, available.width - inset * 2)
        let height = max(1, available.height - inset * 2)
        let scale = min(width / imageSize.width, height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (available.width - size.width) / 2,
                      y: (available.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

private struct OCRTextLayerCanvas: NSViewRepresentable {
    @ObservedObject var model: OCRTextLayerModel
    let imageRect: CGRect

    func makeNSView(context: Context) -> OCRTextLayerCanvasView {
        let view = OCRTextLayerCanvasView()
        view.model = model
        view.imageRect = imageRect
        return view
    }

    func updateNSView(_ view: OCRTextLayerCanvasView, context: Context) {
        if view.model !== model { view.model = model }
        view.imageRect = imageRect
        view.needsDisplay = true
        view.window?.invalidateCursorRects(for: view)
    }
}

@MainActor
final class OCRTextLayerCanvasView: NSView {
    var model: OCRTextLayerModel? {
        didSet { observeModel() }
    }
    var imageRect: CGRect = .zero
    private var modelObservation: AnyCancellable?
    private var pressStart: CGPoint?
    private var didDrag = false
    private var marquee: CGRect?
    private var suppressMouseUp = false
    private var hoveredID: Int?
    private var characterRegionID: Int?
    private var characterAnchor: Int?
    private var trackingArea: NSTrackingArea?

    private func observeModel() {
        modelObservation = nil
        guard let model else { return }
        modelObservation = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let id = regionID(at: point)
        if id != hoveredID {
            hoveredID = id
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredID != nil {
            hoveredID = nil
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }
    }

    func regionRects() -> [(id: Int, rect: CGRect)] {
        guard let model, imageRect.width > 0, imageRect.height > 0 else { return [] }
        return model.regions.map { region in
            let b = region.bounds
            return (region.id, CGRect(x: imageRect.minX + b.minX * imageRect.width,
                                      y: imageRect.minY + b.minY * imageRect.height,
                                      width: b.width * imageRect.width,
                                      height: b.height * imageRect.height))
        }
    }

    func regionID(at point: CGPoint) -> Int? {
        regionRects().reversed().first {
            $0.rect.insetBy(dx: -3, dy: -3).contains(point)
        }?.id
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let model, imageRect.width > 0 else { return }
        NSGraphicsContext.current?.shouldAntialias = true
        for (id, rect) in regionRects() {
            if let selected = model.selectedRanges[id] {
                let length = (model.regions.first(where: { $0.id == id })?.text as NSString?)?.length ?? 0
                if selected == NSRange(location: 0, length: length) {
                    let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4)
                    NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                    path.fill()
                    NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
                    path.lineWidth = 1.5
                    path.stroke()
                } else if let highlight = characterRect(regionID: id, range: selected) {
                    let path = NSBezierPath(roundedRect: highlight, xRadius: 2, yRadius: 2)
                    NSColor.controlAccentColor.withAlphaComponent(0.24).setFill()
                    path.fill()
                    NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
                    path.lineWidth = 1
                    path.stroke()
                }
            } else if id == hoveredID {
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), xRadius: 4, yRadius: 4)
                NSColor.controlAccentColor.withAlphaComponent(0.07).setFill()
                path.fill()
                NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 1
                path.stroke()
            } else {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 1))
                path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
                path.setLineDash([2, 3], count: 2, phase: 0)
                NSColor.controlAccentColor.withAlphaComponent(0.28).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
        if let marquee {
            let path = NSBezierPath(roundedRect: marquee, xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func textLine(for region: OCRTextRegion, in rect: CGRect) -> (line: CTLine, width: CGFloat, scale: CGFloat) {
        let font = NSFont.systemFont(ofSize: max(9, rect.height * 0.78))
        let attributed = NSAttributedString(string: region.text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return (line, width, width > 0 ? rect.width / width : 1)
    }

    private func characterRect(regionID: Int, range: NSRange) -> CGRect? {
        guard let model, let region = model.regions.first(where: { $0.id == regionID }),
              let rect = regionRects().first(where: { $0.id == regionID })?.rect else { return nil }
        let length = (region.text as NSString).length
        let start = min(max(0, range.location), length)
        let end = min(max(start, NSMaxRange(range)), length)
        guard end > start else { return nil }
        let layout = textLine(for: region, in: rect)
        let x0 = CTLineGetOffsetForStringIndex(layout.line, start, nil) * layout.scale
        let x1 = CTLineGetOffsetForStringIndex(layout.line, end, nil) * layout.scale
        return CGRect(x: rect.minX + x0, y: rect.minY + 1,
                      width: max(1, x1 - x0), height: max(1, rect.height - 2))
    }

    func characterIndex(at point: CGPoint, regionID: Int) -> Int? {
        guard let model, let region = model.regions.first(where: { $0.id == regionID }),
              let rect = regionRects().first(where: { $0.id == regionID })?.rect else { return nil }
        let layout = textLine(for: region, in: rect)
        let x = min(max((point.x - rect.minX) / layout.scale, 0), layout.width)
        let index = CTLineGetStringIndexForPosition(layout.line, CGPoint(x: x, y: 0))
        return min(max(index, 0), (region.text as NSString).length)
    }

    override func resetCursorRects() {
        for (_, rect) in regionRects() {
            addCursorRect(rect, cursor: .iBeam)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        pressStart = point
        didDrag = false
        marquee = nil
        suppressMouseUp = false
        characterRegionID = regionID(at: point)
        characterAnchor = characterRegionID.flatMap { characterIndex(at: point, regionID: $0) }
        if event.clickCount == 2, let id = characterRegionID {
            model?.copyLine(id)
            suppressMouseUp = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let id = characterRegionID, let anchor = characterAnchor {
            let current = characterIndex(at: point, regionID: id) ?? anchor
            guard current != anchor || hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            didDrag = true
            model?.applyCharacterSelection(
                regionID: id,
                range: NSRange(location: min(anchor, current), length: abs(current - anchor)),
                extending: false
            )
            needsDisplay = true
            return
        }
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        didDrag = true
        marquee = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                         width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            pressStart = nil
            didDrag = false
            marquee = nil
            suppressMouseUp = false
            characterRegionID = nil
            characterAnchor = nil
            needsDisplay = true
        }
        if suppressMouseUp { return }
        guard pressStart != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let extending = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        if didDrag {
            if let id = characterRegionID, let anchor = characterAnchor {
                let current = characterIndex(at: point, regionID: id) ?? anchor
                model?.applyCharacterSelection(
                    regionID: id,
                    range: NSRange(location: min(anchor, current), length: abs(current - anchor)),
                    extending: false
                )
                return
            }
            guard let marquee else { return }
            let ids = Set(regionRects().filter { $0.rect.intersects(marquee) }.map(\.id))
            model?.applySelection(ids, extending: extending)
        } else if let id = characterRegionID {
            model?.applySelection([id], extending: extending)
        } else if !extending {
            model?.clearSelection()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a": model?.selectAll(); return
            case "c": model?.copySelection(); return
            default: break
            }
        }
        if event.keyCode == 53 { model?.close(); return }
        if event.keyCode == 36 || event.keyCode == 76 {
            model?.copySelection(); return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        model?.close()
    }
}
