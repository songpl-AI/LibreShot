import Foundation
import CoreGraphics
import Darwin

/// One recognition per child. Serial execution bounds model memory and staging files.
nonisolated final class OCRWorkerOperation: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "LibreShot.OCR.Worker", qos: .userInitiated)
    private static let registryLock = NSLock()
    private static var active: OCRWorkerOperation?
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false
    private var process: Process?
    private var continuation: CheckedContinuation<[OCRTextRegion], Error>?
    private let executable: URL?
    private let timeout: TimeInterval

    init(executable: URL? = Bundle.main.url(forAuxiliaryExecutable: "LibreShotOCRWorker"), timeout: TimeInterval = 120) {
        self.executable = executable
        self.timeout = timeout
    }

    static func cancelAll() {
        let operation = registryLock.withLock { active }
        operation?.cancel()
    }

    private func cancel(timeout: Bool = false) {
        let pending: CheckedContinuation<[OCRTextRegion], Error>? = lock.withLock {
            if timeout { timedOut = true } else { cancelled = true }
            if let process, process.isRunning {
                process.terminate()
                // A failed/stalled worker must not block the serial queue indefinitely.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self, weak process] in
                    guard let self, let process else { return }
                    self.lock.withLock {
                        if self.process === process && process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
            if !timeout && process == nil {
                let pending = continuation
                continuation = nil
                return pending
            }
            return nil
        }
        pending?.resume(throwing: CancellationError())
    }

    private func checkState() throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            if timedOut { throw OCRError.recognitionFailed("识别超时，请缩小选区后重试") }
        }
    }

    func run(image: CGImage) async throws -> [OCRTextRegion] {
        let regions: [OCRTextRegion] = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let alreadyCancelled = lock.withLock {
                    if cancelled { return true }
                    self.continuation = continuation
                    return false
                }
                if alreadyCancelled { continuation.resume(throwing: CancellationError()); return }
                Self.queue.async {
                    autoreleasepool {
                        let result: Result<[OCRTextRegion], Error>
                        do { result = .success(try self.perform(image: image)) }
                        catch { result = .failure(error) }
                        let pending = self.lock.withLock {
                            let pending = self.continuation
                            self.continuation = nil
                            return pending
                        }
                        pending?.resume(with: result)
                    }
                }
            }
        } onCancel: { self.cancel() }
        try Task.checkCancellation()
        return regions
    }

    private func perform(image: CGImage) throws -> [OCRTextRegion] {
        try checkState()
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw OCRError.recognitionFailed("缺少识别组件，请重新安装完整应用")
        }
        let requestID = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LibreShot-OCR-\(requestID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try OCRWire.write(image: image, requestID: requestID, directory: directory)
        try checkState()
        let child = Process()
        child.executableURL = executable
        child.arguments = [directory.path, requestID.uuidString]
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        // Serialize launch with cancellation so no child can escape a cancelled task.
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try child.run()
            process = child
        }
        Self.registryLock.withLock { Self.active = self }
        let deadline = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            if child.isRunning { cancel() }
            child.waitUntilExit()
            lock.withLock { process = nil }
            Self.registryLock.withLock { if Self.active === self { Self.active = nil } }
            try? output.fileHandleForReading.close()
        }
        var data = Data()
        while let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard data.count <= OCRWire.maximumResponseBytes - chunk.count else {
                throw OCRError.recognitionFailed("识别结果过大")
            }
            data.append(chunk)
        }
        child.waitUntilExit()
        deadline.cancel()
        try checkState()
        guard child.terminationReason == .exit, child.terminationStatus == 0 else {
            throw OCRError.recognitionFailed("识别进程异常退出，请重试")
        }
        do {
            return try OCRWire.validate(JSONDecoder().decode(OCRWire.Response.self, from: data), requestID: requestID)
        } catch let error as OCRError { throw error }
        catch { throw OCRError.recognitionFailed("无法读取识别结果") }
    }
}
