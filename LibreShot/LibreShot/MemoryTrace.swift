#if DEBUG
import Darwin
import Foundation

// Opt-in diagnostics for local profiling builds. Events are fixed labels and
// never include screenshot pixels, OCR text, or translated text.
enum MemoryTrace {
    private static let logger: MemoryTraceLogger? = {
        guard let path = ProcessInfo.processInfo.environment["LIBRESHOT_MEMORY_TRACE"],
              !path.isEmpty else { return nil }
        return MemoryTraceLogger(path: path)
    }()

    static func mark(_ event: StaticString) {
        logger?.mark(String(describing: event))
    }

    static func markAfterRelease(_ event: StaticString) {
        guard let logger else { return }
        let label = String(describing: event)
        logger.mark(label)
        for seconds in [1, 5, 15, 60] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(seconds)) {
                logger.mark("\(label)_idle_\(seconds)s")
            }
        }
    }
}

private final class MemoryTraceLogger: @unchecked Sendable {
    private let lock = NSLock()
    private let file: FileHandle

    init?(path: String) {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { return nil }
        file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        write("epoch_seconds,pid,event,footprint_bytes\n")
    }

    func mark(_ event: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
        write("\(Date().timeIntervalSince1970),\(getpid()),\(event),\(footprint)\n")
    }

    private func write(_ line: String) {
        lock.withLock {
            try? file.write(contentsOf: Data(line.utf8))
        }
    }
}
#endif
