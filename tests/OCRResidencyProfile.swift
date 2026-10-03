import AppKit
import Darwin
import Vision

/// Diagnostic comparison, not a shipping OCR transport. Both modes use the
/// production accurate OCR operation. The worker exits after each recognition.
private final class WeakOCRReferences {
    weak var request: VNRecognizeTextRequest?
    weak var operation: OCRRecognitionOperation?
}

@main struct OCRResidencyProfile {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "worker" {
            let image = NSImage(contentsOfFile: arguments[1])!
            let regions = try await OCRService.shared.recognizeRegions(from: image)
            let rows = regions.map { region -> [String:Any] in
                ["id":region.id,"text":region.text,"confidence":region.confidence,
                 "bounds":[region.bounds.minX,region.bounds.minY,region.bounds.width,region.bounds.height]]
            }
            let response: [String:Any] = ["regions":rows,"observedFootprintMiB":footprint()]
            let data = try JSONSerialization.data(withJSONObject:response,options:[.sortedKeys])
            FileHandle.standardOutput.write(data)
            return
        }
        let mode = arguments.first ?? "in-process"
        precondition(["in-process","in-process-png","in-process-cancel","worker-parent","window-only"].contains(mode))
        let baseline = report("baseline")
        if mode == "window-only" {
            var retainedWindow: OCRResultWindowController?
            for iteration in 1...5 {
                autoreleasepool {
                    let controller = OCRResultWindowController(text:String(repeating:"LibreShot public OCR result. ",count:8))
                    controller.window?.layoutIfNeeded()
                    controller.close()
                    precondition(controller.window?.contentView == nil)
                    retainedWindow = controller // Matches AppDelegate retaining one closed controller.
                }
                _ = report("window_closed_\(iteration)")
            }
            try await Task.sleep(for:.seconds(15))
            precondition(retainedWindow?.window?.contentView == nil)
            let retained = report("window_idle_15s") - baseline
            print("RESULT window-only: retained=\(retained) MiB; one closed controller retained, hosting view removed")
            fflush(stdout)
            if retained > 32 { exit(1) }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot-OCR-Residency-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let input = directory.appendingPathComponent("public-fixture.png")
        let executable = Bundle.main.url(forAuxiliaryExecutable:"LibreShotOCRProbeWorker")
            ?? URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        var image: NSImage? = fixture()
        weak var originalImage = image
        if mode == "worker-parent" || mode == "in-process-png" {
            let data = CaptureService().pngData(from:image!)!
            try data.write(to:input)
            image = nil
            if mode == "in-process-png" { image = NSImage(contentsOf:input)! }
        }
        weak var recognizedImage = image
        var firstRows: [[String:Any]]?
        var references: [WeakOCRReferences] = []
        for iteration in 1...5 {
            if mode.hasPrefix("in-process") {
                // VN request and operation ownership match OCRService's call site.
                let cgImage = image!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
                let reference = WeakOCRReferences()
                references.append(reference)
                var operation: OCRRecognitionOperation? = autoreleasepool {
                    let request = VNRecognizeTextRequest()
                    reference.request = request
                    return OCRRecognitionOperation(request:request)
                }
                reference.operation = operation
                let regions = try await operation!.run(image:cgImage)
                precondition(!regions.isEmpty, "Recognition must produce text")
                if firstRows == nil { firstRows = regions.map { ["id":$0.id,"text":$0.text,"confidence":$0.confidence,"bounds":[$0.bounds.minX,$0.bounds.minY,$0.bounds.width,$0.bounds.height]] } }
                operation = nil
                if mode == "in-process-cancel" { reference.request?.cancel() }
                await Task.yield()
                print("LIFETIME x\(iteration): operation alive=\(reference.operation != nil); request alive=\(reference.request != nil)")
            } else {
                let response = try await Task.detached { () throws -> [String:Any] in
                    let child = Process()
                    child.executableURL = executable
                    child.arguments = ["worker",input.path]
                    let output = Pipe()
                    child.standardOutput = output
                    try child.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    child.waitUntilExit()
                    guard child.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
                    return try JSONSerialization.jsonObject(with:data) as! [String:Any]
                }.value
                let rows = response["regions"] as! [[String:Any]]
                precondition(!rows.isEmpty, "Recognition must produce text")
                if let firstRows {
                    precondition(NSDictionary(dictionary:["regions":firstRows]).isEqual(to:["regions":rows]),"Worker output changed")
                } else { firstRows = rows }
                print("WORKER exited x\(iteration); observed footprint=\(response["observedFootprintMiB"]!) MiB")
            }
            _ = report("after_\(iteration)")
        }
        if let firstRows {
            let data = try JSONSerialization.data(withJSONObject:["regions":firstRows],options:[.sortedKeys])
            print("OCR_RESULT " + String(data:data,encoding:.utf8)!)
        }
        image = nil
        await Task.yield()
        precondition(originalImage == nil && recognizedImage == nil,"Fixture image retained")
        print("LIFETIME fixture released")
        _ = report("scope_released")
        try await Task.sleep(for:.seconds(15))
        let settled = report("idle_15s")
        let aliveOperations = references.filter { $0.operation != nil }.count
        let aliveRequests = references.filter { $0.request != nil }.count
        print("LIFETIME settled: operations=\(aliveOperations), requests=\(aliveRequests)")
        precondition(aliveOperations == 0, "Application OCR operations retained")
        let retained = settled - baseline
        print("RESULT \(mode): retained=\(retained) MiB; diagnostic retained budget=32 MiB (not a 10 MiB product claim)")
        fflush(stdout)
        if retained > 32 { exit(1) }
    }

    @MainActor private static func fixture() -> NSImage {
        let image = NSImage(size:NSSize(width:1200,height:700))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x:0,y:0,width:1200,height:700).fill()
        for row in 0..<12 {
            ("LibreShot public OCR fixture row \(row)" as NSString).draw(at:NSPoint(x:35,y:row*50+30),
                withAttributes:[.font:NSFont.systemFont(ofSize:24),.foregroundColor:NSColor.black])
        }
        image.unlockFocus()
        return image
    }
    private static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)
            }
        }
        precondition(result == KERN_SUCCESS)
        return Double(info.phys_footprint)/1048576
    }
    private static func report(_ stage:String) -> Double {
        let value = footprint()
        print("SAMPLE,\(Date().timeIntervalSince1970),\(getpid()),\(stage),\(String(format:"%.3f",value))")
        fflush(stdout)
        return value
    }
}
