import AppKit
import CoreGraphics
import Foundation

private final class ProviderEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var releases = 0
    func release() { lock.withLock { releases += 1 } }
    var count: Int { lock.withLock { releases } }
}

private final class ProviderSentinel {
    let events: ProviderEvents
    init(_ events: ProviderEvents) { self.events = events }
    deinit { events.release() }
}

@available(macOS 26.0, *)
@MainActor
private final class References {
    weak var model: ImageTranslationModel?
    weak var original: NSImage?
    weak var output: NSImage?
    weak var provider: ProviderSentinel?
    let events = ProviderEvents()
}

@MainActor
private final class TranslationGate {
    var continuation: CheckedContinuation<[Int: String], Error>?
    func wait() async throws -> [Int: String] {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func resume(_ text: String) {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: [1: text])
    }
}

@MainActor
private final class RecognitionState {
    var calls = 0
    var cancellations = 0
}

@main
struct ImageTranslationReleaseChecks {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard #available(macOS 26.0, *) else {
            throw Failure(description: "Image translation release checks require macOS 26 or later")
        }
        print("SCOPE: synthetic 8-bit sRGB pixels; 0 real OCR calls; 0 real translation calls; 0 windows; no production settings changes")
        try await cancelRemainsRetryable()
        try await retainedCallbackCannotKeepDismissedPixels()
        try await suspendedTranslationCannotRestoreDismissedSession()
        try await recognitionCancellationReleasesItsInput()
        try await delayedRenderCannotRestoreDismissedSession()
        try await temporarySuspensionResumesTranslation()
        try await temporarySuspensionResumesRecognition()
        try await cancelledTasksCanResumeAfterLayoutChange()
        try await newAttachmentPrecedesOldDisappearance()
        try await overlappingTranslationInvocations()
        try await overlappingRenderInvocations()
        try await userCancelledServiceDoesNotAutoRestart()
        try await overlayOwnsSessionAndPreservesEditorPreview()
        print("PASS: all image translation release checks; provider release callbacks establish live backing release, independently of allocator footprint")
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure(description: message) }
    }

    @MainActor private static func eventually(_ message: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        throw Failure(description: message)
    }

    @available(macOS 26.0, *)
    @MainActor private static func fixture(_ references: References) -> CGImage {
        // A release callback observes the allocation itself, rather than merely
        // a wrapper's lifetime or a possibly unchanged malloc/VM footprint.
        let width = 800, height = 600, stride = width * 4 + 64
        let byteCount = stride * height
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        bytes.initializeMemory(as: UInt8.self, repeating: 255, count: byteCount)
        let sentinel = ProviderSentinel(references.events)
        references.provider = sentinel
        let info = Unmanaged.passRetained(sentinel).toOpaque()
        let provider = CGDataProvider(dataInfo: info, data: bytes, size: byteCount) { info, bytes, _ in
            UnsafeMutableRawPointer(mutating: bytes).deallocate()
            if let info { _ = Unmanaged<ProviderSentinel>.fromOpaque(info).takeRetainedValue() }
        }!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func regions() -> [OCRTextRegion] {
        [OCRTextRegion(id: 1, text: "This is a clear English sentence.",
                       bounds: CGRect(x: 0.1, y: 0.1, width: 0.75, height: 0.15), confidence: 0.99)]
    }

    @available(macOS 26.0, *)
    @MainActor private static func model(_ references: References,
                                        recognize: @escaping (NSImage) async throws -> [OCRTextRegion] = { _ in regions() }) -> ImageTranslationModel {
        autoreleasepool {
            let image = NSImage(cgImage: fixture(references), size: CGSize(width: 400, height: 300))
            references.original = image
            let model = ImageTranslationModel(image: image, recognizeImage: recognize)
            references.model = model
            return model
        }
    }

    @available(macOS 26.0, *)
    @MainActor private static func requireReleased(_ references: References, _ label: String) async throws {
        try await eventually("\(label): the original pixel provider remained alive") {
            references.provider == nil && references.original == nil && references.events.count == 1
        }
        try require(references.events.count == 1, "\(label): pixel allocation must be released exactly once")
    }

    @available(macOS 26.0, *)
    @MainActor private static func requireDismissed(_ model: ImageTranslationModel, _ label: String) throws {
        try require(model.isDismissed && model.original == nil && model.translatedImage == nil,
                    "\(label): final dismissal must clear both source and result images")
        try require(model.regions.isEmpty && model.configuration == nil && model.activeRequestID == nil,
                    "\(label): final dismissal must clear region text and translation requests")
        try require(!model.isBusy && !model.canExport && model.errorMessage == nil,
                    "\(label): final dismissal must leave no busy/export/error state")
    }

    @available(macOS 26.0, *)
    @MainActor private static func cancelRemainsRetryable() async throws {
        let references = References()
        let active = model(references)
        active.loadRegions(regions())
        active.startTranslation()
        let firstID = active.activeRequestID
        try require(firstID != nil, "An English-to-Chinese request must start")
        let gate = TranslationGate()
        let obsolete = Task { await active.run(requestID: firstID) { _ in try await gate.wait() } }
        try await eventually("The first mock translation did not suspend") { gate.continuation != nil }
        active.cancel()
        try require(!active.isDismissed && active.original != nil && active.regions.count == 1,
                    "Manual cancel must preserve source pixels and regions for retry")
        await active.activate()
        try require(active.configuration == nil && !active.isBusy,
                    "View activation must not silently retry a manually cancelled request")
        active.startTranslation()
        let retryID = active.activeRequestID
        try require(retryID != nil && retryID != firstID, "Retry must issue a fresh request identity")
        var obsoleteInvocations = 0
        await active.run(requestID: firstID) { _ in obsoleteInvocations += 1; return [1: "obsolete"] }
        try require(obsoleteInvocations == 0 && active.isTranslating,
                    "An obsolete session must not run or cancel the retry")
        await active.run(requestID: retryID) { _ in [1: "新的译文"] }
        await active.render()
        try require(active.canExport && active.translatedImage != nil, "A manual retry must still render an exportable result")
        gate.resume("迟到的旧译文")
        await obsolete.value
        try require(active.regions.first?.translation == "新的译文" && active.canExport,
                    "The old continuation must not overwrite a completed retry")
        try require(references.events.count == 0, "A retryable live session must still retain its source pixels")
        active.dismiss()
        try await requireReleased(references, "manual retry then dismiss")
        print("PASS: manual cancel preserves retry; activation does not retry it; obsolete results cannot overwrite a new successful export")
    }

    @available(macOS 26.0, *)
    @MainActor private static func retainedCallbackCannotKeepDismissedPixels() async throws {
        let references = References()
        var active: ImageTranslationModel? = model(references)
        await active!.recognize()
        await active!.run(requestID: active!.activeRequestID) { _ in [1: "新的译文"] }
        await active!.render()
        try require(active!.canExport, "The completed fixture must be exportable before dismissal")
        autoreleasepool { references.output = active!.translatedImage }
        // Simulate a system callback retaining the model after its view closes.
        var retainedCallback: (() -> ImageTranslationModel)? = { [retained = active!] in retained }
        active!.dismiss()
        active!.dismiss()
        active = nil
        try await requireReleased(references, "retained callback")
        try require(references.model != nil && retainedCallback!().isDismissed,
                    "This check must retain the dismissed model while releasing its pixels")
        try await eventually("A dismissed model retained its rendered NSImage") { references.output == nil }
        let retained = retainedCallback!()
        try requireDismissed(retained, "retained callback")
        retained.loadRegions(regions())
        retained.startTranslation()
        await retained.activate()
        retained.targetLanguageID = "ja"
        await retained.recognize()
        await retained.run(requestID: UUID()) { _ in throw Failure(description: "A dismissed session ran translation") }
        retained.updateTranslation("must be ignored", id: 1)
        retained.setIncluded(true, id: 1)
        await retained.render()
        try requireDismissed(retained, "late view actions")
        retainedCallback = nil
        print("PASS: a retained callback/model cannot retain dismissed source/result pixels, and late view actions cannot reopen the session")
    }

    @available(macOS 26.0, *)
    @MainActor private static func suspendedTranslationCannotRestoreDismissedSession() async throws {
        let references = References()
        var active: ImageTranslationModel? = model(references)
        active!.loadRegions(regions())
        active!.startTranslation()
        let requestID = active!.activeRequestID
        let gate = TranslationGate()
        var operation: Task<Void, Never>? = Task { [retained = active!] in
            await retained.run(requestID: requestID) { _ in try await gate.wait() }
        }
        try await eventually("The uncooperative text provider did not suspend") { gate.continuation != nil }
        active!.dismiss()
        active = nil
        try await requireReleased(references, "suspended text provider")
        try require(gate.continuation != nil && references.model != nil,
                    "Source pixels must release while the text provider still retains the model")
        try requireDismissed(references.model!, "suspended text provider")
        gate.resume("迟到的译文")
        await operation!.value
        operation = nil
        try await eventually("The completed text operation retained its dismissed model") { references.model == nil }
        print("PASS: dismissal releases source pixels even during uncooperative text translation; a late response cannot restore the session")
    }

    @available(macOS 26.0, *)
    @MainActor private static func recognitionCancellationReleasesItsInput() async throws {
        let references = References(), state = RecognitionState()
        let active = model(references, recognize: { image in
            state.calls += 1
            do { try await Task.sleep(for: .seconds(30)) }
            catch { state.cancellations += 1 }
            // Intentionally return a late result after acknowledging cancel.
            // An in-flight recognizer can own its input until it unwinds.
            try require(image.size.width == 400, "The mock recognizer must receive a valid input")
            return regions()
        })
        let operation = Task { await active.recognize() }
        try await eventually("Mock OCR did not start") { state.calls == 1 }
        active.dismiss()
        await operation.value
        try require(state.cancellations == 1, "Dismissal must forward cancellation to in-flight OCR")
        try requireDismissed(active, "cancelled OCR")
        try await requireReleased(references, "cancelled OCR has unwound")
        print("PASS: dismissal cancels OCR, releases its input after the recognizer unwinds, and rejects late recognition results")
    }

    @available(macOS 26.0, *)
    @MainActor private static func delayedRenderCannotRestoreDismissedSession() async throws {
        let references = References(), active = model(references)
        active.loadRegions(regions())
        active.updateTranslation("新的译文", id: 1)
        var enteredRender = false
        let operation = Task { enteredRender = true; await active.render() }
        try await eventually("The render task did not enter") { enteredRender }
        // The render method is now suspended in its debounce delay. No input
        // image has been handed to its detached pixel worker yet.
        active.dismiss()
        try await requireReleased(references, "dismissed delayed render")
        await operation.value
        try requireDismissed(active, "completed delayed render")
        print("PASS: dismissal during render debounce releases source pixels and prevents a delayed layout from restoring output")
    }

    @available(macOS 26.0, *)
    @MainActor private static func temporarySuspensionResumesTranslation() async throws {
        let references = References(), active = model(references)
        active.loadRegions(regions())
        active.startTranslation()
        let firstID = active.activeRequestID
        let gate = TranslationGate()
        let obsolete = Task { await active.run(requestID: firstID) { _ in try await gate.wait() } }
        try await eventually("Translation did not start before temporary suspension") { gate.continuation != nil }
        active.suspend()
        try require(!active.isDismissed && active.original != nil && !active.isBusy && references.events.count == 0,
                    "Temporary view suspension must preserve the source while stopping active work")
        await active.activate()
        let resumedID = active.activeRequestID
        try require(resumedID != nil && resumedID != firstID && active.isTranslating,
                    "View reactivation must resume a suspended translation with a new request identity")
        await active.run(requestID: resumedID) { _ in [1: "恢复后的译文"] }
        await active.render()
        gate.resume("过期译文")
        await obsolete.value
        try require(active.canExport && active.regions.first?.translation == "恢复后的译文",
                    "A suspended old provider must not replace the resumed result")
        active.suspend()
        await active.activate()
        try require(active.canExport && !active.isBusy,
                    "Layout-only view reconstruction must preserve an already completed translation")
        active.dismiss()
        try await requireReleased(references, "temporarily suspended translation")
        print("PASS: temporary view suspension resumes translation safely and preserves completed exports across view reconstruction")
    }

    @available(macOS 26.0, *)
    @MainActor private static func temporarySuspensionResumesRecognition() async throws {
        let references = References(), state = RecognitionState()
        let active = model(references, recognize: { _ in
            state.calls += 1
            if state.calls <= 2 {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { state.cancellations += 1; throw error }
            }
            return regions()
        })
        let first = Task { await active.recognize() }
        try await eventually("Recognition did not start before temporary suspension") { state.calls == 1 }
        active.cancel()
        await first.value
        await active.activate()
        try require(state.calls == 1 && !active.isBusy && active.original != nil,
                    "View reactivation must not restart manually cancelled OCR")
        let retry = Task { await active.recognize() }
        try await eventually("Manual OCR retry did not start") { state.calls == 2 }
        active.suspend()
        await retry.value
        try require(state.cancellations == 2 && active.original != nil && !active.isDismissed,
                    "Temporary suspension must cancel OCR without ending its image session")
        await active.activate()
        try await eventually("View reactivation did not resume OCR") { state.calls == 3 && active.isTranslating }
        active.dismiss()
        try await requireReleased(references, "temporarily suspended recognition")
        print("PASS: manual OCR cancellation needs explicit retry; temporary view suspension resumes recognition without losing its source or ending the session")
    }

    @available(macOS 26.0, *)
    @MainActor private static func cancelledTasksCanResumeAfterLayoutChange() async throws {
        let recognitionReferences = References(), state = RecognitionState()
        let recognizing = model(recognitionReferences, recognize: { _ in
            state.calls += 1
            if state.calls == 1 { try await Task.sleep(for: .seconds(30)) }
            return regions()
        })
        let recognition = Task { await recognizing.recognize() }
        try await eventually("The cancelled-layout mock OCR did not start") { state.calls == 1 }
        recognition.cancel()
        await recognition.value
        recognizing.suspend()
        await recognizing.activate()
        try require(state.calls == 2 && recognizing.isTranslating,
                    "OCR task cancellation before onDisappear must preserve the layout-restart intent")
        recognizing.dismiss()
        try await requireReleased(recognitionReferences, "cancel-before-suspend OCR")

        let translationReferences = References(), translating = model(translationReferences)
        translating.loadRegions(regions())
        translating.startTranslation()
        let requestID = translating.activeRequestID
        var startedTranslation = false
        let translation = Task {
            await translating.run(requestID: requestID) { _ in
                startedTranslation = true
                try await Task.sleep(for: .seconds(30))
                return [1: "discarded cancelled text"]
            }
        }
        try await eventually("The cancelled-layout mock translation did not start") { startedTranslation }
        translation.cancel()
        await translation.value
        translating.suspend()
        await translating.activate()
        try require(translating.isTranslating && translating.activeRequestID != requestID,
                    "Translation task cancellation before onDisappear must preserve the layout-restart intent")
        await translating.run(requestID: translating.activeRequestID) { _ in [1: "恢复后的译文"] }
        await translating.render()
        try require(translating.canExport, "The resumed translation must remain usable")
        translating.dismiss()
        try await requireReleased(translationReferences, "cancel-before-suspend translation")

        let renderReferences = References(), rendering = model(renderReferences)
        rendering.loadRegions(regions())
        rendering.updateTranslation("新的译文", id: 1)
        var enteredRender = false
        let render = Task { enteredRender = true; await rendering.render() }
        try await eventually("The cancelled-layout render did not enter") { enteredRender }
        render.cancel()
        await render.value
        rendering.suspend()
        await rendering.activate()
        try require(rendering.isRendering, "Render task cancellation before onDisappear must preserve the layout-restart intent")
        await rendering.render()
        try require(rendering.canExport, "The resumed render must produce a usable export")
        rendering.dismiss()
        try await requireReleased(renderReferences, "cancel-before-suspend render")
        print("PASS: OCR, translation and render recover when SwiftUI cancels their tasks before delivering disappearance")
    }

    @available(macOS 26.0, *)
    @MainActor private static func newAttachmentPrecedesOldDisappearance() async throws {
        let references = References(), active = model(references)
        let oldAttachment = UUID(), newAttachment = UUID()
        active.loadRegions(regions())
        await active.activate(attachmentID: oldAttachment)
        active.startTranslation()
        let oldRequest = active.activeRequestID
        let gate = TranslationGate()
        let oldTask = Task {
            await active.run(requestID: oldRequest, attachmentID: oldAttachment) { _ in try await gate.wait() }
        }
        try await eventually("The old attachment did not start translation") { gate.continuation != nil }
        // SwiftUI may mount B before delivering A's disappearance. A must not
        // stop the operation that now belongs to B.
        await active.activate(attachmentID: newAttachment)
        let newRequest = active.activeRequestID
        active.suspend(attachmentID: oldAttachment)
        try require(active.isTranslating && newRequest != nil && newRequest != oldRequest &&
                    active.activeRequestID == newRequest && active.original != nil,
                    "Old-view disappearance must not suspend the newly attached view's translation")
        gate.resume("obsolete attachment result")
        await oldTask.value
        try require(active.isTranslating && active.activeRequestID == newRequest,
                    "The old attachment's late continuation must not clear the new translation")
        var obsoleteCalls = 0
        await active.run(requestID: newRequest, attachmentID: oldAttachment) { _ in
            obsoleteCalls += 1
            return [1: "obsolete attachment"]
        }
        try require(obsoleteCalls == 0 && active.isTranslating,
                    "A retired attachment must not run even with the new request identity")
        let cancelledActivation = Task { await active.activate(attachmentID: UUID()) }
        cancelledActivation.cancel()
        await cancelledActivation.value
        await active.run(requestID: newRequest, attachmentID: newAttachment) { _ in [1: "新布局译文"] }
        try require(active.isRendering, "A cancelled activation must not take ownership from the live attachment")
        await active.render(attachmentID: oldAttachment)
        try require(active.isRendering && active.translatedImage == nil,
                    "A retired attachment must not consume the live view's pending render")
        await active.render(attachmentID: newAttachment)
        try require(active.canExport && active.regions.first?.translation == "新布局译文",
                    "The newly attached view must complete a usable export")
        active.dismiss()
        try await requireReleased(references, "new attachment before old disappearance")
        print("PASS: new-view activation before old-view disappearance preserves the live operation; retired/cancelled attachments cannot take ownership or render")
    }

    @available(macOS 26.0, *)
    @MainActor private static func overlappingTranslationInvocations() async throws {
        for ordering in 0..<3 {
            let references = References(), active = model(references)
            active.loadRegions(regions())
            active.startTranslation()
            let requestID = active.activeRequestID
            let oldGate = TranslationGate(), currentGate = TranslationGate()
            let old = Task { await active.run(requestID: requestID) { _ in try await oldGate.wait() } }
            try await eventually("The old same-request invocation did not suspend") { oldGate.continuation != nil }
            let current = Task { await active.run(requestID: requestID) { _ in try await currentGate.wait() } }
            try await eventually("The current same-request invocation did not suspend") { currentGate.continuation != nil }
            if ordering < 2 {
                if ordering == 1 { old.cancel() }
                oldGate.resume("obsolete same-request result")
                await old.value
                try require(active.isTranslating && active.configuration != nil && active.activeRequestID == requestID &&
                            active.regions.first?.translation == "" && !active.isRendering,
                            "An obsolete invocation's result/cancellation/defer must not modify the current invocation")
            }
            currentGate.resume("最新调用译文")
            await current.value
            await active.render()
            if ordering == 2 {
                oldGate.resume("late obsolete same-request result")
                await old.value
            }
            try require(active.canExport && active.regions.first?.translation == "最新调用译文",
                        "The current invocation's export must survive obsolete completion in either order")
            active.suspend()
            await active.activate()
            try require(active.canExport && !active.isBusy,
                        "An obsolete cancellation must not leave a false resume intent after the current invocation completes")
            active.dismiss()
            try await requireReleased(references, "overlapping translation \(ordering)")
        }
        print("PASS: overlapping translation calls with the same request reject obsolete success/cancellation/cleanup before and after the current result")
    }

    @available(macOS 26.0, *)
    @MainActor private static func overlappingRenderInvocations() async throws {
        let references = References(), active = model(references)
        active.loadRegions(regions())
        active.updateTranslation("新的译文", id: 1)
        var oldEntered = false, currentEntered = false
        let old = Task { oldEntered = true; await active.render() }
        try await eventually("The old same-revision render did not enter") { oldEntered }
        let current = Task { currentEntered = true; await active.render() }
        try await eventually("The current same-revision render did not enter") { currentEntered }
        old.cancel()
        await old.value
        try require(active.isRendering && !active.canExport && active.translatedImage == nil,
                    "An obsolete render's cancellation/defer must not clear the current render's busy state")
        await current.value
        try require(active.canExport && active.translatedImage != nil,
                    "The current same-revision render must produce a usable export")
        active.suspend()
        await active.activate()
        try require(active.canExport && !active.isBusy,
                    "An obsolete render must not leave a false resume intent after the current render completes")
        active.dismiss()
        try await requireReleased(references, "overlapping renders")
        print("PASS: an obsolete same-revision render cannot clear the current render or leave a false resume intent")
    }

    @available(macOS 26.0, *)
    @MainActor private static func userCancelledServiceDoesNotAutoRestart() async throws {
        let references = References(), active = model(references)
        active.loadRegions(regions())
        active.startTranslation()
        await active.run(requestID: active.activeRequestID) { _ in throw CancellationError() }
        try require(!Task.isCancelled && !active.isBusy && active.configuration == nil && active.errorMessage != nil,
                    "A user-cancelled system service must stop cleanly without cancelling the hosting task")
        active.suspend()
        await active.activate()
        try require(!active.isBusy && active.configuration == nil && active.original != nil,
                    "View reconstruction must not silently retry a user's cancelled download/service")
        active.startTranslation()
        await active.run(requestID: active.activeRequestID) { _ in [1: "用户主动重试译文"] }
        await active.render()
        try require(active.canExport, "The user must still be able to retry explicitly after cancelling the service")
        active.dismiss()
        try await requireReleased(references, "user-cancelled translation service")
        print("PASS: system-service user cancellation does not auto-restart on view reconstruction and remains explicitly retryable")
    }

    @available(macOS 26.0, *)
    @MainActor private static func overlayOwnsSessionAndPreservesEditorPreview() async throws {
        let suite = "LibreShot.ImageTranslationRelease.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let overlay = OverlayViewModel(settings: SettingsService(defaults: defaults))
        let references = References()
        autoreleasepool { overlay.previewImage = fixture(references) }
        overlay.previewScale = 1
        overlay.selectionRect = CGRect(x: 64, y: 64, width: 320, height: 160)
        overlay.state = .editing
        var retainedCallbacks: [() -> ImageTranslationModel] = []
        for index in 0..<10 {
            overlay.confirmImageTranslation()
            guard let active = overlay.imageTranslationModel else {
                throw Failure(description: "The overlay did not create its translation session")
            }
            let sessionID = overlay.translationSessionID
            overlay.translationCanExport = true
            try require(!overlay.canExportSelection,
                        "A stale view publication must not allow export before the owner's model has a rendered result")
            try require(active.original === overlay.translationSource,
                        "The overlay and its model must use the same source image")
            overlay.confirmImageTranslation()
            try require(overlay.imageTranslationModel === active && overlay.translationSessionID == sessionID,
                        "Toggling translation controls must reuse the owner's model")
            retainedCallbacks.append({ active })
            if index.isMultiple(of: 2) { overlay.clearImageTranslation() }
            else { overlay.selectionRect = overlay.selectionRect.offsetBy(dx: 1, dy: 1) }
            try requireDismissed(active, "overlay removal \(index)")
            try require(overlay.imageTranslationModel == nil && overlay.translationSource == nil &&
                        overlay.translatedSelection == nil && overlay.previewImage != nil && overlay.canExportSelection,
                        "Removing translation must keep the original editor preview available for ordinary capture/export")
            try require(references.events.count == 0,
                        "The still-open editor legitimately owns the original capture backing")
        }
        overlay.confirmImageTranslation()
        let final = overlay.imageTranslationModel!
        retainedCallbacks.append({ final })
        overlay.reset()
        try require(overlay.previewImage == nil && overlay.imageTranslationModel == nil && overlay.state == .idle,
                    "Reset must end both translation and the original editor preview")
        try await requireReleased(references, "overlay reset with retained old callbacks")
        for callback in retainedCallbacks { try requireDismissed(callback(), "retained overlay callback") }
        try require(retainedCallbacks.count == 11, "Repeated sessions must remain part of the release check")
        print("PASS: the overlay owns one model per session; removal/crop changes preserve normal editing; reset releases the original backing despite 11 retained old models")
    }
}
