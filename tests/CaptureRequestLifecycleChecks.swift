import AppKit
import Foundation

@main struct CaptureRequestLifecycleChecks {
    static func main() async throws {
        try await cachedResultsAndFrameClaim()
        try await cancelledDuringContentLoading()
        try await resultDuringStartup(cancel: false)
        try await resultDuringStartup(cancel: true)
        try await resultDuringStartup(cancel: true, earlyFrame: true)
        try await failedStartupCleansOwner()
        try await serializedRequests()
        try await cancelledQueuedRequest()
        print("PASS: capture requests cache early cancellation/results, copy only one frame, wait for startup before teardown, clean failures and serialize concurrent requests")
    }

    static func cachedResultsAndFrameClaim() async throws {
        let cancelled = CaptureRequestState<Int>()
        cancelled.fail(CancellationError())
        precondition(!cancelled.claimFrame())
        do { _ = try await cancelled.waitForResult(); preconditionFailure("Early cancellation was lost") }
        catch is CancellationError {}

        let claimed = CaptureRequestState<Int>()
        precondition(claimed.claimFrame())
        claimed.fail(CancellationError())
        claimed.succeed(42) // Cancellation while the claimed frame is being copied.
        precondition(!claimed.claimFrame())
        do { _ = try await claimed.waitForResult(); preconditionFailure("Claiming a frame consumed cancellation") }
        catch is CancellationError {}

        let first = CaptureRequestState<Int>()
        let copies = LockedCounter()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            if first.claimFrame() {
                copies.increment()
                first.succeed(index)
            }
        }
        precondition(copies.value == 1, "Concurrent queued frames copied more than one image")
        first.fail(FakeCaptureError())
        let value = try await first.waitForResult()
        precondition((0..<200).contains(value))

        // A waiting continuation must also settle exactly once under competing
        // completion callbacks, rather than only supporting cached results.
        let waiting = CaptureRequestState<Int>()
        async let awaited = waiting.waitForResult()
        await Task.yield()
        DispatchQueue.concurrentPerform(iterations: 200) { waiting.succeed($0) }
        let waitedValue = try await awaited
        precondition((0..<200).contains(waitedValue))
    }

    static func cancelledDuringContentLoading() async throws {
        let request = CaptureRequestState<Int>()
        let contentEntered = TestLatch(), contentReady = TestLatch()
        let starts = LockedCounter(), stops = LockedCounter()
        let task = Task {
            try await withTaskCancellationHandler {
                // Simulates SCShareableContent's suspension, before there is
                // either an output callback or a result continuation.
                await contentEntered.signal()
                await contentReady.wait()
                return try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                    starts.increment()
                    request.succeed(1)
                }, stop: { stops.increment() })
            } onCancel: { request.fail(CancellationError()) }
        }
        await contentEntered.wait()
        task.cancel()
        await contentReady.signal()
        do { _ = try await task.value; preconditionFailure("Content-loading cancellation was lost") }
        catch is CancellationError {}
        precondition(starts.value == 0 && stops.value == 0, "Cancelled setup created or stopped a stream")
    }

    static func resultDuringStartup(cancel: Bool, earlyFrame: Bool = false) async throws {
        let request = CaptureRequestState<Int>()
        let startupEntered = TestLatch(), startupFinished = TestLatch()
        let stops = LockedCounter()
        let task = Task {
            try await withTaskCancellationHandler {
                try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                    await startupEntered.signal()
                    if !cancel || earlyFrame { request.succeed(23) }
                    await startupFinished.wait()
                }, stop: { stops.increment() })
            } onCancel: { request.fail(CancellationError()) }
        }
        await startupEntered.wait()
        if cancel { task.cancel() }
        // Give completion/cancellation a chance to run while startup remains
        // deliberately blocked. A first frame must never stop a starting stream.
        for _ in 0..<10 { await Task.yield() }
        precondition(stops.value == 0, "Teardown raced unfinished startCapture")
        await startupFinished.signal()
        if cancel {
            do { _ = try await task.value; preconditionFailure("Startup cancellation was lost") }
            catch is CancellationError {}
        } else {
            let image = try await task.value
            precondition(image == 23, "Early first frame was lost")
        }
        precondition(stops.value == 1, "Stream teardown must run exactly once")
    }

    static func failedStartupCleansOwner() async throws {
        for earlyFrame in [false, true] {
            let request = CaptureRequestState<Int>()
            let stops = LockedCounter()
            do {
                _ = try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                    if earlyFrame { request.succeed(7) }
                    throw FakeCaptureError() // Output registration or startup failure.
                }, stop: { stops.increment() })
                preconditionFailure("Failed stream startup returned an image")
            } catch is FakeCaptureError {}
            precondition(stops.value == 1, "Failed local stream/output owner was not cleaned")
        }
    }

    static func serializedRequests() async throws {
        let gate = StreamLifecycleGate()
        let live = LiveStreamCounter()
        try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<50 {
                group.addTask {
                    let request = CaptureRequestState<Int>()
                    return try await gate.withLock {
                        try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                            await live.started()
                            await Task.yield()
                            precondition(request.claimFrame())
                            request.succeed(index)
                            await Task.yield()
                        }, stop: {
                            await Task.yield()
                            await live.stopped()
                        })
                    }
                }
            }
            var results = Set<Int>()
            for try await result in group { results.insert(result) }
            precondition(results.count == 50, "Concurrent requests overwrote another request's result")
        }
        let totals = await live.totals()
        precondition(totals == [50, 50, 1, 0], "Starts overlapped a previous stream or its teardown")
    }

    static func cancelledQueuedRequest() async throws {
        let gate = StreamLifecycleGate()
        await gate.acquire()
        let request = CaptureRequestState<Int>()
        let entered = TestLatch()
        let starts = LockedCounter()
        let queued = Task {
            try await withTaskCancellationHandler {
                await entered.signal()
                return try await gate.withLock {
                    try await SingleFrameCaptureLifecycle.capture(request: request, start: {
                        starts.increment()
                        request.succeed(1)
                    }, stop: {})
                }
            } onCancel: { request.fail(CancellationError()) }
        }
        await entered.wait()
        queued.cancel()
        await gate.release()
        do { _ = try await queued.value; preconditionFailure("Queued request cancellation was lost") }
        catch is CancellationError {}
        precondition(starts.value == 0)
        // Cancellation and exceptions must release the gate for the next request.
        let following = try await gate.withLock { 99 }
        precondition(following == 99)
    }
}

private struct FakeCaptureError: Error {}

private actor TestLatch {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if signalled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private actor LiveStreamCounter {
    private var starts = 0, stops = 0, live = 0, maximum = 0
    func started() { starts += 1; live += 1; maximum = max(maximum, live) }
    func stopped() { stops += 1; live -= 1 }
    func totals() -> [Int] { [starts, stops, maximum, live] }
}
