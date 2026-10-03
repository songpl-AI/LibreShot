import AppKit
import Darwin

@main struct OCRWorkerChecks {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--parent-crash" {
            let requestID = UUID()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot-OCR-\(requestID.uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let context = CGContext(data: nil, width: 4000, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            try OCRWire.write(image: context.makeImage()!, requestID: requestID, directory: directory)
            let child = Process()
            child.executableURL = Bundle.main.url(forAuxiliaryExecutable: "LibreShotOCRWorker")!
            child.arguments = [directory.path, requestID.uuidString]
            child.standardOutput = FileHandle.nullDevice
            try child.run()
            try "\(child.processIdentifier)\n\(directory.path)".write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            // Simulate a crash without Swift defers or application termination callbacks.
            _exit(0)
        }
        _ = NSApplication.shared
        let image = NSImage(size: NSSize(width: 1000, height: 600))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 600).fill()
        for (index, text) in ["LibreShot accurate OCR", "中文识别与原图翻译", "Column one       Column two"].enumerated() {
            (text as NSString).draw(at: NSPoint(x: 30, y: 420 - index * 100), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let original = try await OCRRecognitionOperation().run(image: cg)
        let worker = try await OCRService.shared.recognizeRegions(from: image)
        precondition(!original.isEmpty && original.contains { $0.text.contains("中文") })
        precondition(original.count == worker.count && zip(original, worker).allSatisfy { a, b in
            a.id == b.id && a.text == b.text && a.confidence == b.confidence && a.bounds == b.bounds && a.lineCount == b.lineCount
        }, "Raw transport changed text/confidence/bounds")
        print("PASS: English, Chinese and columns preserve text, confidence and exact original-image coordinates")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot-Wire-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let context = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: name)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.3, alpha: 0.5))
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
            let source = context.makeImage()!, requestID = UUID()
            try OCRWire.write(image: source, requestID: requestID, directory: temporary)
            let restored = try OCRWire.read(directory: temporary, requestID: requestID)
            precondition(source.dataProvider!.data! as Data == restored.dataProvider!.data! as Data)
            precondition(source.colorSpace!.copyICCData()! as Data == restored.colorSpace!.copyICCData()! as Data)
            precondition(source.bitmapInfo == restored.bitmapInfo && source.width == restored.width && source.height == restored.height)
        }
        print("PASS: transparent sRGB/P3 raster, color profile and physical dimensions round-trip losslessly")
        let fakeDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        for mode in ["missing", "crash", "json", "version", "oversize", "timeout"] {
            do {
                _ = try await OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent(mode), timeout: 0.2).run(image: cg)
                preconditionFailure("\(mode) must fail")
            } catch is OCRError { }
        }
        print("PASS: missing helper, abnormal exit, malformed/versioned/oversized response and timeout fail safely")
        let cancelled = Task { try await OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent("timeout"), timeout: 10).run(image: cg) }
        try await Task.sleep(for: .milliseconds(150))
        let waiting = Task { try await OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent("success")).run(image: cg) }
        try await Task.sleep(for: .milliseconds(30))
        let cancelStart = ContinuousClock.now
        waiting.cancel()
        do { _ = try await waiting.value; preconditionFailure("Cancelled queued task returned") } catch is CancellationError { }
        precondition(cancelStart.duration(to: .now) < .seconds(1), "Queued cancellation waited for the active OCR")
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled worker returned") } catch is CancellationError { }
        let queued = Task { try await OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent("timeout")).run(image: cg) }
        queued.cancel()
        do { _ = try await queued.value; preconditionFailure("Cancelled queued task returned") } catch is CancellationError { }
        print("PASS: in-flight and pre-launch cancellation terminate/reap the worker and return cancellation")
        async let first = OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent("success")).run(image: cg)
        async let second = OCRWorkerOperation(executable: fakeDirectory.appendingPathComponent("success")).run(image: cg)
        let pair = try await (first, second)
        precondition(pair.0.isEmpty && pair.1.isEmpty)
        let events = try String(contentsOf: fakeDirectory.appendingPathComponent("events"), encoding: .utf8)
        precondition(events == "start\nend\nstart\nend\n", "Concurrent OCR workers overlapped")
        print("PASS: concurrent callers execute serially and leave no active workers")
        let record = fakeDirectory.appendingPathComponent("parent-crash")
        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        parent.arguments = ["--parent-crash", record.path]
        try parent.run(); parent.waitUntilExit()
        precondition(parent.terminationStatus == 0)
        let details = try String(contentsOf: record, encoding: .utf8).split(separator: "\n")
        let pid = Int32(details[0])!
        for _ in 0..<25 {
            if kill(pid, 0) != 0 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        precondition(kill(pid, 0) != 0, "Worker survived parent exit")
        precondition(!FileManager.default.fileExists(atPath: String(details[1])), "Crash left a screenshot raster")
        print("PASS: unexpected parent exit stops its worker and removes its staged screenshot")
    }
}
