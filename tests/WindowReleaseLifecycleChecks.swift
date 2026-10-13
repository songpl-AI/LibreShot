import AppKit
import SwiftUI

@main
struct WindowReleaseLifecycleChecks {
    final class Token { var calls = 0; func touch() { calls += 1 } }
    final class State {
        var errors = 0
        var captures = 0
        var cancels = 0
        var displayPreserved = false
        var previewRequirementPreserved = false
        var expectedDisplayID: CGDirectDisplayID?
        var image: CGImage?
    }
    final class Probe {
        let controller: OverlayWindowController
        let window: NSWindow
        let model: OverlayViewModel
        let state: State
        weak var host: NSViewController?
        weak var token: Token?

        init(_ controller: OverlayWindowController, state: State, token: Token) {
            self.controller = controller
            window = controller.window!
            model = (window.contentViewController as! NSHostingController<OverlayView>).rootView.viewModel
            self.state = state
            host = window.contentViewController
            self.token = token
        }
    }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        // Every loader throws or remains suspended. No successful preview can
        // activate the app, display an overlay, or request screen permission.
        let denied = makeDeniedProbe(mode: .normal)
        let longDenied = makeDeniedProbe(mode: .longScreenshot)
        let cancelled = makeCancelProbe()
        let captured = makeCaptureProbe()
        try await Task.sleep(for: .milliseconds(150))
        for probe in [denied, longDenied, cancelled, captured] { checkReleased(probe) }
        precondition(denied.state.errors == 1 && longDenied.state.errors == 1,
                     "Terminal cleanup must preserve permission-error delivery")
        precondition(cancelled.state.cancels == 1 && cancelled.state.errors == 0,
                     "Cancelled previews must not emit a later error")
        precondition(captured.state.captures == 1 && captured.state.errors == 0)
        precondition(captured.state.displayPreserved,
                     "The capture callback must still receive the original display identity")
        precondition(captured.state.previewRequirementPreserved,
                     "Cleanup must preserve the frozen-preview requirement for the synchronous capture callback")
        precondition(captured.state.image?.width == 128 && captured.state.image?.height == 96,
                     "Cleanup must not invalidate the image already submitted to the caller")
        try await checkResetAndStalePreview()
        try await checkReusableController()
        try await checkLongCaptureResetIsIgnored()
        checkDirectClose()
        checkOCRClose()
        print("PASS: hidden overlay/OCR windows release hosts and callbacks while external owners retain controller/window; errors, submitted images, reset and stale previews remain correct")
    }

    @MainActor static func makeDeniedProbe(mode: CaptureMode) -> Probe {
        let controller = OverlayWindowController(), token = Token(), state = State()
        let probe = Probe(controller, state: state, token: token)
        controller.previewImageLoader = { _ in token.touch(); throw CaptureServiceError.permissionDenied }
        controller.show(captureMode: mode,
                        onCapture: { _, _, _, _ in token.touch(); state.captures += 1 },
                        onPreviewError: { _ in token.touch(); state.errors += 1 },
                        onCancel: { token.touch(); state.cancels += 1 })
        return probe
    }

    @MainActor static func makeCancelProbe() -> Probe {
        let controller = OverlayWindowController(), token = Token(), state = State()
        let probe = Probe(controller, state: state, token: token)
        controller.previewImageLoader = { _ in token.touch(); throw CaptureServiceError.permissionDenied }
        controller.show(onCapture: { _, _, _, _ in token.touch(); state.captures += 1 },
                        onPreviewError: { _ in token.touch(); state.errors += 1 },
                        onCancel: { token.touch(); state.cancels += 1 })
        (probe.window as! OverlayWindow).onEscapeKey?()
        return probe
    }

    @MainActor static func makeCaptureProbe() -> Probe {
        let controller = OverlayWindowController(), token = Token(), state = State()
        let probe = Probe(controller, state: state, token: token)
        controller.previewImageLoader = { _ in token.touch(); throw CaptureServiceError.permissionDenied }
        controller.show(onCapture: { [weak controller] _, _, action, image in
            token.touch(); state.captures += 1
            if case .ocr = action { state.image = image } else { preconditionFailure("Unexpected action") }
            state.displayPreserved = controller?.getCurrentDisplayID() == state.expectedDisplayID
            state.previewRequirementPreserved = controller?.captureRequiresExistingPreview() == true
        }, onPreviewError: { _ in token.touch(); state.errors += 1 }, onCancel: { token.touch(); state.cancels += 1 })
        state.expectedDisplayID = controller.getCurrentDisplayID()
        precondition(state.expectedDisplayID != nil)
        let context = CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
        probe.model.updatePreviewImage(context.makeImage(), scale: 1)
        probe.model.selectionRect = CGRect(x: 0, y: 0, width: 128, height: 96)
        probe.model.state = .editing
        probe.model.annotations = [Annotation(type: .mosaic, color: .red, startPoint: .zero, endPoint: CGPoint(x: 40, y: 40))]
        probe.model.confirmOCR()
        return probe
    }

    @MainActor static func checkReleased(_ probe: Probe) {
        precondition(!probe.window.isVisible)
        precondition(probe.window.contentViewController == nil && probe.window.contentView == nil,
                     "An ended session must detach its SwiftUI tree even while the window is retained")
        precondition(probe.host == nil, "The detached hosting controller must be released")
        precondition(probe.token == nil, "Ended sessions must release loader and business-callback captures")
        precondition(probe.model.previewImage == nil && probe.model.translationSource == nil)
        precondition(probe.model.onCapture == nil && probe.model.onCancel == nil && probe.model.onLongCaptureStart == nil)
        let window = probe.window as! OverlayWindow
        precondition(window.onEscapeKey == nil && window.onEditorShortcut == nil)
        precondition(probe.controller.previewImageLoader == nil && probe.controller.getCurrentDisplayID() == nil)
        probe.controller.close()
    }

    @MainActor static func checkResetAndStalePreview() async throws {
        let controller = OverlayWindowController()
        let retainedWindow = controller.window!
        weak var host = retainedWindow.contentViewController
        var attempts = 0, errors = 0
        var firstPreview: CheckedContinuation<NSImage, Never>?
        controller.previewImageLoader = { _ in
            attempts += 1
            if attempts == 1 { return await withCheckedContinuation { firstPreview = $0 } }
            throw CaptureServiceError.permissionDenied
        }
        controller.show(onCapture: { _, _, _, _ in preconditionFailure("No capture expected") },
                        onPreviewError: { _ in errors += 1 }, onCancel: {})
        for _ in 0..<50 where attempts == 0 { try await Task.sleep(for: .milliseconds(5)) }
        precondition(attempts == 1)
        controller.resetCapture()
        precondition(retainedWindow.contentViewController === host,
                     "An active reset must retain the current hosting tree")
        try await Task.sleep(for: .milliseconds(50))
        precondition(errors == 1 && !retainedWindow.isVisible)
        firstPreview?.resume(returning: NSImage(size: NSSize(width: 128, height: 96)))
        firstPreview = nil
        try await Task.sleep(for: .milliseconds(50))
        precondition(!retainedWindow.isVisible && retainedWindow.contentViewController == nil && host == nil,
                     "A stale preview must not resurrect a completed session")
        controller.close()
    }

    @MainActor static func checkReusableController() async throws {
        let controller = OverlayWindowController(), window = controller.window!
        for _ in 0..<2 {
            var errors = 0
            controller.previewImageLoader = { _ in throw CaptureServiceError.permissionDenied }
            controller.show(onCapture: { _, _, _, _ in preconditionFailure("No capture expected") },
                            onPreviewError: { _ in errors += 1 }, onCancel: {})
            precondition(window.contentViewController != nil)
            try await Task.sleep(for: .milliseconds(50))
            precondition(errors == 1 && window.contentViewController == nil && !window.isVisible)
        }
        controller.close()
    }

    @MainActor static func checkLongCaptureResetIsIgnored() async throws {
        let controller = OverlayWindowController()
        let window = controller.window!
        let model = (window.contentViewController as! NSHostingController<OverlayView>).rootView.viewModel
        let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
                                bytesPerRow: 640 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 640, height: 480))
        controller.previewImageLoader = { _ in image }
        controller.show(captureMode: .longScreenshot,
                        onCapture: { _, _, _, _ in preconditionFailure("No normal capture expected") },
                        onLongCaptureError: { _ in },
                        onCancel: {})
        for _ in 0..<100 where model.previewImage == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        precondition(model.previewImage != nil, "Long capture fixture preview did not load")
        model.selectionRect = CGRect(x: 20, y: 20, width: 120, height: 120)
        model.state = .editing
        model.confirmLongCaptureRegion()
        precondition(model.state == .longCapturing)

        // This is the old failure path: resetCapture() used to clear the
        // session and leave a blank screenSaver-level window behind.
        controller.resetCapture()
        precondition(model.state == .longCapturing,
                     "Reset must be ignored while long capture owns the controller")

        await controller.cancelAndWait()
        controller.close()
    }

    @MainActor static func checkDirectClose() {
        let controller = OverlayWindowController(), window = controller.window!
        controller.close()
        precondition(window.contentViewController == nil && window.contentView == nil)
    }

    @MainActor static func checkOCRClose() {
        @MainActor final class Owner {
            var controller: OCRResultWindowController?
            var closed = 0
            func open() {
                let controller = OCRResultWindowController(text: "Public OCR lifecycle fixture.")
                controller.onClose = { [weak self, weak controller] in
                    guard let self, self.controller === controller else { return }
                    self.controller = nil
                    self.closed += 1
                }
                self.controller = controller
            }
        }
        let owner = Owner()
        owner.open()
        let retainedController = owner.controller!, retainedWindow = retainedController.window!
        retainedController.close()
        precondition(owner.controller == nil && owner.closed == 1)
        precondition(retainedController.window == nil && retainedController.onClose == nil)
        precondition(retainedWindow.contentView == nil && retainedWindow.delegate == nil)
        retainedController.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: retainedWindow))
        precondition(owner.closed == 1, "OCR close completion must run only once")
        owner.open()
        owner.controller?.close()
        precondition(owner.closed == 2 && owner.controller == nil)
    }
}
