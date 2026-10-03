import Foundation
import Darwin

@main struct OCRWorker {
    static func main() async {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let requestID = UUID(uuidString: arguments[2]) else { exit(64) }
        let directory = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        guard directory.lastPathComponent == "LibreShot-OCR-\(requestID.uuidString)",
              directory.deletingLastPathComponent().resolvingSymlinksInPath() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL else { exit(64) }
        // Also stop on an unexpected parent crash, which cannot invoke cancelAll().
        let parent = getppid()
        let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        monitor.schedule(deadline: .now() + 1, repeating: 1)
        monitor.setEventHandler {
            if getppid() != parent || parent == 1 {
                try? FileManager.default.removeItem(at: directory)
                exit(71)
            }
        }
        monitor.resume()
        defer { monitor.cancel() }
        let response: OCRWire.Response
        do {
            let image = try OCRWire.read(directory: directory, requestID: requestID)
            // The mapped raster stays valid after unlinking; a parent crash leaves no screenshot file.
            try? FileManager.default.removeItem(at: directory)
            let regions = try await OCRRecognitionOperation().run(image: image)
            response = OCRWire.Response(version: OCRWire.version, requestID: requestID, regions: regions, error: nil)
        } catch {
            response = OCRWire.Response(version: OCRWire.version, requestID: requestID, regions: [], error: String(error.localizedDescription.prefix(500)))
        }
        do {
            let data = try JSONEncoder().encode(response)
            guard data.count <= OCRWire.maximumResponseBytes else { exit(65) }
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch { exit(74) }
    }
}
