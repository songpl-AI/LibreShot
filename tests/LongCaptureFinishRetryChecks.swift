import AppKit

private final class ScriptedFrameSource: LongCaptureFrameSource, @unchecked Sendable {
    private var receiver: ((LongCaptureFrame) -> Void)?
    var isRunning: Bool { receiver != nil }
    private(set) var startedSelections: [CGRect] = []
    var finalFrame: LongCaptureFrame?
    var finishError: LongCaptureError?
    var startError: Error?

    func start(region: LongCaptureRegion, onFrame: @escaping (LongCaptureFrame) -> Void) async throws {
        startedSelections.append(region.selectionRect)
        receiver = onFrame
        if let startError { throw startError }
    }

    func send(_ frame: LongCaptureFrame) { receiver?(frame) }
    func pause() {}
    func resume() {}

    func finishFrame() async throws -> LongCaptureFrame? {
        receiver = nil
        if let finishError { throw finishError }
        return finalFrame
    }

    func stop() async { receiver = nil }
}

@main
struct LongCaptureFinishRetryChecks {
    @MainActor static func main() async {
        do {
            try await reconnectAfterMissingRows()
            try await waitForStableFinish()
            try await cancelAfterRetry()
            try await stopWhenRecoveryIsCancelled()
            try await stopOnTerminalFailure()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor private static func reconnectAfterMissingRows() async throws {
        let source = ScriptedFrameSource()
        let session = try makeSession(source)
        try await session.start()
        source.send(frame(offset: 80, time: 1))
        source.finalFrame = frame(offset: 1000, time: 2)

        guard case .resumedCapture = try await session.finish(), session.status == .capturing, source.isRunning else {
            throw CheckFailure("first Finish must return to live capture with the same selection")
        }
        guard session.progress.appendedPixelHeight == 400, session.progress.warning?.contains("滚回") == true,
              source.startedSelections.count == 2, source.startedSelections.first == source.startedSelections.last else {
            throw CheckFailure("failed Finish must keep the confirmed 400px and restart the same selection with guidance")
        }
        source.send(frame(offset: 80, time: 3))
        source.send(frame(offset: 160, time: 4))
        source.finalFrame = frame(offset: 160, time: 5)
        try expectExactImage(try await session.finish(), height: 480)
        guard session.status == .completed, !source.isRunning else {
            throw CheckFailure("completed Finish must leave the stream stopped")
        }
        print("PASS: reconnecting after a failed Finish saves all 480px exactly once")
    }

    @MainActor private static func waitForStableFinish() async throws {
        let source = ScriptedFrameSource()
        let session = try makeSession(source)
        try await session.start()
        source.send(frame(offset: 80, time: 1))
        source.finishError = .unstableFinish
        for _ in 0..<2 {
            guard case .resumedCapture = try await session.finish(), session.status == .capturing,
                  source.isRunning, session.progress.appendedPixelHeight == 400,
                  session.progress.warning?.contains("稳定") == true else {
                throw CheckFailure("each unstable Finish must keep the 400px and show the stability guidance")
            }
        }
        source.finishError = nil
        source.finalFrame = frame(offset: 80, time: 2)
        try expectExactImage(try await session.finish(), height: 400)
        print("PASS: after two unstable Finish attempts, waiting for the same position to settle saves all 400px")
    }

    @MainActor private static func cancelAfterRetry() async throws {
        let source = ScriptedFrameSource()
        let session = try makeSession(source)
        try await session.start()
        source.finishError = .unstableFinish
        guard case .resumedCapture = try await session.finish() else {
            throw CheckFailure("capture must resume before cancellation")
        }
        await session.cancel()
        guard session.status == .cancelled, !source.isRunning else {
            throw CheckFailure("cancelling the resumed session must stop the stream")
        }
        print("PASS: cancelling after a retry stops the resumed stream")
    }

    @MainActor private static func stopWhenRecoveryIsCancelled() async throws {
        let source = ScriptedFrameSource()
        let session = try makeSession(source)
        try await session.start()
        source.finishError = .unstableFinish
        source.startError = CancellationError()
        do {
            _ = try await session.finish()
            throw CheckFailure("a cancelled restart must end the session")
        } catch is CancellationError {
            guard session.status == .cancelled, !source.isRunning else {
                throw CheckFailure("a partially restarted stream must stop when restart is cancelled")
            }
        }
        print("PASS: cancellation during restart stops any partially restarted stream")
    }

    @MainActor private static func stopOnTerminalFailure() async throws {
        let source = ScriptedFrameSource()
        let session = try makeSession(source)
        try await session.start()
        source.finishError = .storageFailed
        do {
            _ = try await session.finish()
            throw CheckFailure("a storage failure must be reported to the caller")
        } catch LongCaptureError.storageFailed {
            guard case .failed = session.status, !source.isRunning, source.startedSelections.count == 1 else {
                throw CheckFailure("a storage failure must end capture without reopening the stream")
            }
        }
        print("PASS: terminal storage failure ends the session and reaches the caller")
    }

    @MainActor private static func makeSession(_ source: ScriptedFrameSource) throws -> LongCaptureSession {
        let selection = CGRect(x: 0, y: 0, width: 240, height: 320)
        let region = LongCaptureRegion(selectionRect: selection, screenRect: selection,
                                       screenFrame: selection, displayID: 1)
        return try LongCaptureSession(region: region, initialImage: image(offset: 0), frameSource: source)
    }

    @MainActor private static func expectExactImage(_ result: LongCaptureSession.FinishResult, height: Int) throws {
        guard case .completed(let resultImage) = result else {
            throw CheckFailure("Finish must return the completed image")
        }
        let output = resultImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let reference = image(offset: 0, height: height)
        guard let output, output.width == reference.width, output.height == reference.height,
              output.dataProvider?.data as Data? == reference.dataProvider?.data as Data? else {
            throw CheckFailure("Finish must preserve every expected pixel")
        }
    }

    static func frame(offset: Int, time: Double) -> LongCaptureFrame {
        LongCaptureFrame(image: image(offset: offset), timestamp: time)
    }

    static func image(offset: Int, height: Int = 320) -> CGImage {
        let width = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var hash = UInt32((offset + y) * width + x) &* 0x9e3779b9
                hash ^= hash >> 16
                hash = hash &* 0x7feb352d
                let value = UInt8(truncatingIfNeeded: hash >> 16)
                let pixel = (y * width + x) * 4
                bytes[pixel] = value
                bytes[pixel + 1] = value
                bytes[pixel + 2] = value
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    struct CheckFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
