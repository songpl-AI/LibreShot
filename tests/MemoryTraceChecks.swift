import Foundation

@main
struct MemoryTraceChecks {
    static func main() throws {
        MemoryTrace.markAfterRelease("smoke_test")
        Thread.sleep(forTimeInterval: 1.2)
        guard let path = ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_TRACE"] else {
            fatalError("Missing trace path")
        }
        let lines = try String(contentsOfFile: path, encoding: .utf8)
            .split(separator: "\n")
        precondition(lines.first == "epoch_seconds,pid,event,footprint_bytes")
        precondition(lines.count >= 3)
        let columns = lines.last?.split(separator: ",") ?? []
        precondition(columns.count == 4 && columns[2] == "smoke_test_idle_1s")
        precondition(Int64(columns[3]) ?? -1 > 0)
    }
}
