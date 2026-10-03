import Foundation
import Darwin

@main struct OCRFakeWorker {
    static func main() throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let requestID = UUID(uuidString: CommandLine.arguments[2])!
        switch executable.lastPathComponent {
        case "crash": exit(42)
        case "json": FileHandle.standardOutput.write(Data("invalid json".utf8))
        case "oversize": FileHandle.standardOutput.write(Data(repeating: 32, count: OCRWire.maximumResponseBytes + 1))
        case "timeout":
            signal(SIGTERM, SIG_IGN)
            sleep(120)
        default:
            let log = executable.deletingLastPathComponent().appendingPathComponent("events")
            if executable.lastPathComponent == "success" {
                if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
                let handle = try FileHandle(forWritingTo: log)
                try handle.seekToEnd(); try handle.write(contentsOf: Data("start\n".utf8))
                usleep(150_000)
                try handle.write(contentsOf: Data("end\n".utf8)); try handle.close()
            }
            let response = OCRWire.Response(version: executable.lastPathComponent == "version" ? 99 : OCRWire.version,
                                            requestID: requestID, regions: [], error: nil)
            FileHandle.standardOutput.write(try JSONEncoder().encode(response))
        }
    }
}
