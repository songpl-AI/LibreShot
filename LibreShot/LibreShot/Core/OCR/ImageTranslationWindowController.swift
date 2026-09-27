import AppKit
import SwiftUI
import Translation
import Combine

@available(macOS 26.0, *)
@MainActor
final class ImageTranslationModel: ObservableObject {
    let original: NSImage
    @Published var targetLanguageID = "zh-Hans" {
        didSet {
            guard targetLanguageID != oldValue else { return }
            cancel()
            translatedImage = nil
            overflowIDs = []
            complexBackgroundIDs = []
            for index in regions.indices { regions[index].translation = "" }
            progress = ""
        }
    }
    @Published private(set) var regions: [TranslatedImageRegion] = []
    @Published private(set) var translatedImage: NSImage?
    @Published private(set) var configuration: TranslationSession.Configuration?
    @Published private(set) var isRecognizing = false
    @Published private(set) var isTranslating = false
    @Published private(set) var isRendering = false
    @Published private(set) var renderRevision = 0
    @Published private(set) var overflowIDs: Set<Int> = []
    @Published private(set) var complexBackgroundIDs: Set<Int> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var progress = ""
    private var requestID: UUID?
    private var recognitionID: UUID?
    private var recognitionTask: Task<[OCRTextRegion], Error>?
    private var lastConfiguration = TranslationSession.Configuration()
    private var loaded = false
    private let recognizeImage: (NSImage) async throws -> [OCRTextRegion]

    init(image: NSImage, recognizeImage: @escaping (NSImage) async throws -> [OCRTextRegion] = { try await OCRService.shared.recognizeRegions(from: $0) }) {
        original = image
        self.recognizeImage = recognizeImage
    }

    var isBusy: Bool { isRecognizing || isTranslating || isRendering }
    var canExport: Bool { translatedImage != nil && !isBusy && overflowIDs.isEmpty }
    var activeRequestID: UUID? { requestID }

    func recognize() async {
        guard !loaded else { return }
        #if DEBUG
        MemoryTrace.mark("image_translation_ocr_started")
        defer { MemoryTrace.mark("image_translation_ocr_finished") }
        #endif
        loaded = true
        let id = UUID()
        recognitionID = id
        isRecognizing = true
        errorMessage = nil
        progress = "正在识别文字…"
        let recognize = recognizeImage
        let image = original
        let worker = Task { try await recognize(image) }
        recognitionTask = worker
        do {
            let lines = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard recognitionID == id else { return }
            loadRegions(OCRTextRegion.readingOrder(from: lines))
            isRecognizing = false
            recognitionID = nil
            recognitionTask = nil
            progress = ""
            if regions.isEmpty { loaded = false; errorMessage = "未识别到文字，请选择更清晰的文字区域。"; progress = "" }
            else { startTranslation() }
        } catch {
            guard recognitionID == id else { return }
            isRecognizing = false
            recognitionID = nil
            recognitionTask = nil
            loaded = false
            progress = ""
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
    }

    func loadRegions(_ source: [OCRTextRegion]) {
        loaded = true
        regions = source.map { TranslatedImageRegion(source: $0, translation: "", isIncluded: $0.confidence >= 0.3) }
    }

    func startTranslation() {
        guard !isBusy else { return }
        let selected = regions.filter(\.isIncluded)
        guard !selected.isEmpty else { errorMessage = "请选择至少一个文字区域。"; return }
        errorMessage = nil
        translatedImage = nil
        overflowIDs = []
        complexBackgroundIDs = []
        let source = TranslationService.detectLanguage(of: selected.map { $0.source.text }.joined(separator: "\n"))
        let target = Locale.Language(identifier: targetLanguageID)
        if source == target {
            for index in regions.indices where regions[index].isIncluded { regions[index].translation = regions[index].source.text }
            requestRender()
            return
        }
        requestID = UUID()
        isTranslating = true
        progress = "正在翻译 \(selected.count) 个文字区域…"
        lastConfiguration.source = source
        lastConfiguration.target = target
        lastConfiguration.invalidate()
        configuration = lastConfiguration
    }

    func run(requestID expectedID: UUID?, translate: ([OCRTextRegion]) async throws -> [Int: String]) async {
        guard !Task.isCancelled, let id = expectedID, requestID == id else { return }
        #if DEBUG
        MemoryTrace.mark("image_translation_text_started")
        defer { MemoryTrace.mark("image_translation_text_finished") }
        #endif
        let source = regions.filter(\.isIncluded).map(\.source)
        defer {
            if requestID == id {
                requestID = nil
                configuration = nil
                isTranslating = false
            }
        }
        do {
            try Task.checkCancellation()
            let results = try await translate(source)
            try Task.checkCancellation()
            guard requestID == id else { return }
            guard source.allSatisfy({ !(results[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw NSError(domain: "LibreShot.ImageTranslation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "部分文字区域没有返回译文，请重试。"])
            }
            for index in regions.indices {
                if let result = results[regions[index].id] { regions[index].translation = result }
            }
            requestRender()
        } catch {
            guard requestID == id else { return }
            progress = ""
            if error is CancellationError || TranslationError.alreadyCancelled ~= error ||
                ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError) {
                errorMessage = "已取消翻译，可重试。"
            } else { errorMessage = "翻译未完成：\(error.localizedDescription)" }
        }
    }

    func updateTranslation(_ text: String, id: Int) {
        guard !isTranslating, let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].translation = text
        requestRender()
    }

    func setIncluded(_ included: Bool, id: Int) {
        guard !isTranslating, let index = regions.firstIndex(where: { $0.id == id }) else { return }
        regions[index].isIncluded = included
        requestRender()
    }

    private func requestRender() {
        renderRevision += 1
        isRendering = true
        progress = "正在排版…"
    }

    func render() async {
        guard isRendering else { return }
        #if DEBUG
        MemoryTrace.mark("image_translation_render_started")
        defer { MemoryTrace.mark("image_translation_render_finished") }
        #endif
        let revision = renderRevision
        let snapshot = regions
        defer { if revision == renderRevision { isRendering = false } }
        do {
            try await Task.sleep(for: .milliseconds(180))
            guard let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw OCRError.missingImage }
            let scale = CGFloat(cg.width) / max(original.size.width, 1)
            let worker = Task.detached(priority: .userInitiated) {
                try ImageTranslationRenderer.render(image: cg, regions: snapshot, scale: scale)
            }
            let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard revision == renderRevision else { return }
            translatedImage = NSImage(cgImage: result.image, size: original.size)
            overflowIDs = result.overflowIDs
            complexBackgroundIDs = result.complexBackgroundIDs
            errorMessage = nil
            progress = result.overflowIDs.isEmpty ? "排版完成" : "\(result.overflowIDs.count) 个区域译文过长或为空，请修改译文或取消勾选。"
        } catch is CancellationError {
        } catch {
            guard revision == renderRevision else { return }
            translatedImage = nil
            errorMessage = error.localizedDescription
            progress = ""
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionID = nil
        requestID = nil
        configuration = nil
        renderRevision += 1
        isRecognizing = false
        isTranslating = false
        isRendering = false
        translatedImage = nil
        progress = "已取消"
        if regions.isEmpty { loaded = false }
    }

    func translate(using session: TranslationSession, requestID: UUID?) async {
        await run(requestID: requestID) { regions in
            var translated: [Int: String] = [:]
            for start in stride(from: 0, to: regions.count, by: 32) {
                try Task.checkCancellation()
                let batch = regions[start..<min(start + 32, regions.count)].map {
                    TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id))
                }
                for response in try await session.translations(from: batch) {
                    if let identifier = response.clientIdentifier, let id = Int(identifier) {
                        translated[id] = response.targetText
                    }
                }
            }
            return translated
        }
    }
}

@available(macOS 26.0, *)
struct InlineImageTranslationView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @StateObject private var model: ImageTranslationModel
    @State private var showsCorrections = false
    private let sessionID: UUID

    init(viewModel: OverlayViewModel, image: NSImage) {
        self.viewModel = viewModel
        sessionID = viewModel.translationSessionID
        _model = StateObject(wrappedValue: ImageTranslationModel(image: image))
    }

    var body: some View {
        let requestID = model.activeRequestID
        VStack(spacing: 0) {
            if viewModel.showsTranslationControls {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Picker("目标语言", selection: $model.targetLanguageID) {
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                            Text("日本語").tag("ja")
                            Text("한국어").tag("ko")
                        }.labelsHidden().frame(width: 84).disabled(model.isBusy)
                        Picker("图像", selection: $viewModel.showsOriginalTranslation) {
                            Text("原文").tag(true)
                            Text("译文").tag(false)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
                        Spacer(minLength: 0)
                        Button {
                            if model.isBusy { model.cancel() }
                            else if model.regions.isEmpty { Task { await model.recognize() } }
                            else { model.startTranslation() }
                        } label: {
                            Image(systemName: model.isBusy ? "stop.circle" : "arrow.clockwise")
                                .frame(width: 24, height: 24)
                        }.help(model.isBusy ? "取消翻译" : "重新翻译")
                            .accessibilityLabel(model.isBusy ? "取消翻译" : "重新翻译")
                        Button { showsCorrections.toggle() } label: {
                            Image(systemName: "pencil.line").frame(width: 24, height: 24)
                        }.help("校正译文").accessibilityLabel("校正译文")
                            .popover(isPresented: $showsCorrections) {
                                ImageTranslationCorrections(model: model).frame(width: 310, height: 360)
                            }
                        Button { model.cancel(); viewModel.clearImageTranslation() } label: {
                            Image(systemName: "xmark").frame(width: 24, height: 24)
                        }.help("移除翻译，保留原图").accessibilityLabel("移除翻译")
                    }.buttonStyle(.plain)
                    HStack(spacing: 6) {
                        if model.isBusy { ProgressView().controlSize(.mini) }
                        Text(model.errorMessage ?? model.progress)
                            .font(.system(size: 11))
                            .foregroundStyle(model.errorMessage != nil || !model.overflowIDs.isEmpty ? Color.red : Color.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }.frame(height: 14)
                }
                .padding(10)
                .frame(height: 70)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .padding(.top, 8)
            }
        }
        .task { await model.recognize() }
        .task(id: model.renderRevision) { await model.render() }
        .translationTask(model.configuration) { session in
            await model.translate(using: session, requestID: requestID)
        }
        .onChange(of: model.translatedImage) { _, image in
            guard viewModel.translationSessionID == sessionID else { return }
            viewModel.translatedSelection = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        .onChange(of: model.canExport) { _, allowed in
            guard viewModel.translationSessionID == sessionID else { return }
            viewModel.translationCanExport = allowed
        }
        .onChange(of: model.targetLanguageID) { _, _ in model.startTranslation() }
        .onDisappear { model.cancel() }
    }
}

@available(macOS 26.0, *)
private struct ImageTranslationCorrections: View {
    @ObservedObject var model: ImageTranslationModel
    var body: some View {
        List {
            ForEach(model.regions) { region in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("区域 \(region.id + 1)", isOn: Binding(get: { region.isIncluded }, set: { model.setIncluded($0, id: region.id) }))
                        .font(.caption).disabled(model.isTranslating)
                    Text(region.source.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    TextEditor(text: Binding(get: { region.translation }, set: { model.updateTranslation($0, id: region.id) }))
                        .font(.system(size: 13)).frame(height: 60)
                        .disabled(model.isTranslating || !region.isIncluded)
                    if model.overflowIDs.contains(region.id) {
                        Label("译文过长或为空", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                    } else if model.complexBackgroundIDs.contains(region.id) {
                        Label("复杂背景，请核对覆盖效果", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.vertical, 6)
            }
        }
    }
}

@available(macOS 26.0, *)
@MainActor
final class ImageTranslationWindowController: NSWindowController, NSWindowDelegate {
    let model: ImageTranslationModel
    var onClose: (() -> Void)?
    var onAction: ((NSImage, CaptureAction) async throws -> Void)?
    var onEdit: ((NSImage) -> Void)?

    init(image: NSImage) {
        model = ImageTranslationModel(image: image)
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: min(1100, visible.width * 0.9), height: min(760, visible.height * 0.9)),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "原图翻译"
        window.minSize = CGSize(width: 740, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ImageTranslationView(model: model, onAction: { [weak self] image, action in
            try await self?.onAction?(image, action)
        }, onEdit: { [weak self] in self?.onEdit?($0) }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        window?.contentView = nil
        onAction = nil
        onEdit = nil
        onClose?()
        onClose = nil
        #if DEBUG
        MemoryTrace.markAfterRelease("image_translation_window_closed")
        #endif
    }
}

@available(macOS 26.0, *)
private struct ImageTranslationView: View {
    @ObservedObject var model: ImageTranslationModel
    let onAction: (NSImage, CaptureAction) async throws -> Void
    let onEdit: (NSImage) -> Void
    @State private var showOriginal = false
    @State private var zoom: CGFloat = 1
    @State private var actionMessage: String?
    @State private var exporting = false

    var body: some View {
        let translationRequestID = model.activeRequestID
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("目标语言", selection: $model.targetLanguageID) {
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                }.frame(width: 170).disabled(model.isBusy)
                Button {
                    actionMessage = nil
                    if model.regions.isEmpty { Task { await model.recognize() } }
                    else { model.startTranslation() }
                } label: { Label("翻译", systemImage: "character.bubble") }
                    .disabled(model.isBusy)
                if model.isBusy {
                    ProgressView().controlSize(.small)
                    Button("取消") { model.cancel() }
                }
                Spacer()
                Picker("图像", selection: $showOriginal) {
                    Text("原图").tag(true)
                    Text("译图").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 120)
            }.padding(12)
            Divider()
            HStack(spacing: 0) {
                GeometryReader { geometry in
                    let image = showOriginal ? model.original : (model.translatedImage ?? model.original)
                    let fit = min(1, max(0.05, (geometry.size.width - 24) / max(image.size.width, 1)))
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable()
                            .frame(width: image.size.width * fit * zoom, height: image.size.height * fit * zoom)
                            .padding(12)
                    }
                    .background(Color(NSColor.underPageBackgroundColor))
                }
                Divider()
                List {
                    ForEach(model.regions) { region in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("区域 \(region.id + 1)", isOn: Binding(get: { region.isIncluded }, set: { model.setIncluded($0, id: region.id) }))
                                .font(.caption).disabled(model.isTranslating)
                            Text(region.source.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            TextEditor(text: Binding(get: { region.translation }, set: { model.updateTranslation($0, id: region.id) }))
                                .font(.system(size: 13)).frame(height: 72)
                                .disabled(model.isTranslating || !region.isIncluded)
                            if model.overflowIDs.contains(region.id) {
                                Label("译文过长或为空", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                            } else if model.complexBackgroundIDs.contains(region.id) {
                                Label("复杂背景，请核对覆盖效果", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                            if region.source.confidence < 0.3 {
                                Text("识别置信度较低").font(.caption).foregroundStyle(.orange)
                            }
                        }.padding(.vertical, 6)
                    }
                }.frame(width: 260)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                if let actionMessage { Text(actionMessage).font(.caption).textSelection(.enabled) }
                HStack(spacing: 10) {
                    Button { zoom = max(0.25, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                    Button { zoom = min(4, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                    Text(model.progress).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    Button { if let image = model.translatedImage { onEdit(image) } } label: { Label("标注", systemImage: "pencil.tip") }
                        .disabled(!model.canExport || exporting)
                    Button { export(.copy) } label: { Label("复制图片", systemImage: "doc.on.doc") }.disabled(!model.canExport || exporting)
                    Button { export(.saveAs) } label: { Label("保存…", systemImage: "square.and.arrow.down") }.disabled(!model.canExport || exporting)
                }
            }.padding(12)
        }
        .task { await model.recognize() }
        .task(id: model.renderRevision) { await model.render() }
        .translationTask(model.configuration) { session in
            await model.translate(using: session, requestID: translationRequestID)
        }
        .onDisappear { model.cancel() }
    }

    private func export(_ action: CaptureAction) {
        guard model.canExport, let image = model.translatedImage, !exporting else { return }
        exporting = true
        actionMessage = nil
        Task { @MainActor in
            defer { exporting = false }
            do {
                try await onAction(image, action)
                actionMessage = action == .copy ? "已复制图片" : "已保存"
            } catch is CancellationError {
            } catch { actionMessage = error.localizedDescription }
        }
    }
}
