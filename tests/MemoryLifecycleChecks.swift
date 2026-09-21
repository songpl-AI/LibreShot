import AppKit
import Darwin

@main
struct MemoryLifecycleChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let suite = "LibreShot.Memory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsService(defaults: defaults)
        let board = NSPasteboard(name: .init(suite))
        defer { board.releaseGlobally() }
        let service = CaptureService(settings: settings, pasteboard: board)
        report("isolated AppKit/service baseline")
        let image = NSImage(size: CGSize(width: 1200, height: 700))
        image.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1200, height: 700).fill()
        for row in 0..<15 {
            ("Memory fixture \(row) - screenshot editor lifecycle" as NSString).draw(at: CGPoint(x: 30, y: row * 40 + 20),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        report("fixture allocated")
        for iteration in 1...20 {
            autoreleasepool {
                let editor = ImageEditorWindowController(image: image, settings: settings)
                if ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_BASELINE"] == nil {
                    precondition(editor.model.previewBitmap == nil)
                }
                service.copyToClipboard(editor.renderedImage())
                editor.close()
                precondition(editor.window?.contentView == nil)
            }
            if iteration % 5 == 0 { report("copy/editor closed x\(iteration)") }
        }
        try await sampleIdle("copy/editor")
        for iteration in 1...5 {
            let text = try await OCRService.shared.recognizeText(from: image)
            precondition(!text.isEmpty)
            report("OCR x\(iteration)")
        }
        try await sampleIdle("OCR")
        precondition(board.data(forType: .png) != nil, "Clipboard must survive idle sampling")
        print("PASS: 20 editor/copy cycles and 5 OCR cycles; private clipboard retained throughout")
    }

    private static func report(_ label: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            print("MEMORY \(label): \(String(format: "%.1f", Double(info.phys_footprint) / 1048576)) MiB")
            fflush(stdout)
        }
    }

    private static func sampleIdle(_ label: String) async throws {
        var previous = 0
        for seconds in [1, 5, 15, 60] {
            try await Task.sleep(for: .seconds(seconds - previous))
            report("\(label) idle \(seconds)s")
            previous = seconds
        }
    }
}
