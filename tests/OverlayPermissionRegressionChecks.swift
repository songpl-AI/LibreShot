import AppKit

@main
struct OverlayPermissionRegressionChecks {
    @MainActor
    static func main() async {
        for mode in [CaptureMode.normal, .longScreenshot] {
            let controller = OverlayWindowController()
            controller.previewImageLoader = { _ in throw CaptureServiceError.permissionDenied }
            var reportedError: Error?
            controller.show(
                captureMode: mode,
                onCapture: { _, _, _, _ in preconditionFailure("Denied preview cannot capture") },
                onPreviewError: { reportedError = $0 },
                onCancel: {}
            )
            try? await Task.sleep(for: .milliseconds(100))
            defer { controller.close() }
            precondition(!controller.window!.isVisible,
                         "A denied preview must not display the screenSaver-level dimming overlay")
            precondition(reportedError is CaptureServiceError,
                         "The permission failure must reach the caller for recovery guidance")
        }
        let controller = OverlayWindowController()
        var previewAttempts = 0
        var resetError: Error?
        controller.previewImageLoader = { _ in
            previewAttempts += 1
            if previewAttempts == 1 { return NSImage(size: NSSize(width: 100, height: 100)) }
            throw CaptureServiceError.permissionDenied
        }
        controller.show(
            onCapture: { _, _, _, _ in preconditionFailure("Reset fixture cannot capture") },
            onPreviewError: { resetError = $0 },
            onCancel: {}
        )
        try? await Task.sleep(for: .milliseconds(100))
        precondition(controller.window!.isVisible, "A successful preview should display the overlay")
        controller.resetCapture()
        try? await Task.sleep(for: .milliseconds(100))
        precondition(!controller.window!.isVisible,
                     "A failed preview refresh must remove the existing overlay")
        precondition(resetError is CaptureServiceError)
        controller.close()

        let overlapping = OverlayWindowController()
        var firstPreview: CheckedContinuation<NSImage, Never>?
        var overlappingAttempts = 0
        overlapping.previewImageLoader = { _ in
            overlappingAttempts += 1
            if overlappingAttempts == 1 {
                return await withCheckedContinuation { firstPreview = $0 }
            }
            throw CaptureServiceError.permissionDenied
        }
        overlapping.show(
            onCapture: { _, _, _, _ in preconditionFailure("Overlapping fixture cannot capture") },
            onPreviewError: { _ in },
            onCancel: {}
        )
        for _ in 0..<20 where overlappingAttempts == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(overlappingAttempts == 1)
        overlapping.resetCapture()
        try? await Task.sleep(for: .milliseconds(50))
        precondition(!overlapping.window!.isVisible)
        firstPreview?.resume(returning: NSImage(size: NSSize(width: 100, height: 100)))
        try? await Task.sleep(for: .milliseconds(50))
        precondition(!overlapping.window!.isVisible,
                     "A stale successful preview must not resurrect an overlay after a permission failure")
        overlapping.close()
        print("PASS: denied previews leave no overlay and report the permission error")
    }
}
