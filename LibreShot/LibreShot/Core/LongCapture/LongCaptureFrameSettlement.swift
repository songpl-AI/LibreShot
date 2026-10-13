import Foundation

/// A finite observation window for the final capture position. Call every method
/// on the capture output queue. This owns at most one latest real payload; the
/// clock and timers belong to its caller, so idle streams need no second frame.
nonisolated final class LongCaptureFrameSettlement<Payload> {
    enum Failure: Error, Equatable {
        case deadlineReached
        case invalidTimestamp
        case nonMonotonicTime
        case cancelled
    }

    enum Update {
        /// Schedule a check even when ScreenCaptureKit sends no more frames.
        case waiting(nextCheckAt: TimeInterval)
        /// The latest observed payload, with its real capture timestamp intact.
        case settled(Payload)
        case failed(Failure)
        /// A terminal result was already delivered; never retain/replay it.
        case terminal
    }

    let deadline: TimeInterval
    private let quietInterval: TimeInterval
    private let areEqual: (Payload, Payload) -> Bool
    private var latest: Payload?
    private var quietSince: TimeInterval?
    private var lastReceiptTime: TimeInterval
    private var finished = false

    init?(startedAt: TimeInterval, quietInterval: TimeInterval = 0.25,
          timeout: TimeInterval = 2, areEqual: @escaping (Payload, Payload) -> Bool) {
        let deadline = startedAt + timeout
        guard startedAt.isFinite, quietInterval.isFinite, timeout.isFinite,
              quietInterval > 0, timeout > quietInterval, deadline.isFinite,
              deadline > startedAt, startedAt + quietInterval > startedAt else { return nil }
        self.deadline = deadline
        self.quietInterval = quietInterval
        self.areEqual = areEqual
        lastReceiptTime = startedAt
    }

    /// A changed complete frame restarts the quiet window. Identical complete
    /// frames still replace the payload but do not postpone completion forever.
    /// Receipt time must come from one monotonic clock, not presentation time.
    func observe(_ payload: Payload, receivedAt time: TimeInterval) -> Update {
        if let failure = validate(time) { return failure }
        guard time < deadline else { return fail(.deadlineReached) }
        if let previous = latest {
            if !areEqual(previous, payload) { quietSince = time }
        } else {
            quietSince = time
        }
        latest = payload
        return check(at: time)
    }

    /// Use this for timer checks or idle notifications. Idle conveys no new
    /// image, so it cannot reset the quiet window or invent a capture timestamp.
    func poll(at time: TimeInterval) -> Update {
        if let failure = validate(time) { return failure }
        return check(at: time)
    }

    @discardableResult
    func cancel() -> Update {
        guard !finished else { return .terminal }
        return fail(.cancelled)
    }

    private func validate(_ time: TimeInterval) -> Update? {
        guard !finished else { return .terminal }
        guard time.isFinite else { return fail(.invalidTimestamp) }
        guard time >= lastReceiptTime else { return fail(.nonMonotonicTime) }
        lastReceiptTime = time
        return nil
    }

    private func check(at time: TimeInterval) -> Update {
        // The hard deadline wins even if a late timer would otherwise settle a
        // stale payload. A timeout never returns an earlier accepted picture.
        guard time < deadline else { return fail(.deadlineReached) }
        guard let quietSince, let latest else { return .waiting(nextCheckAt: deadline) }
        let quietDeadline = quietSince + quietInterval
        guard time >= quietDeadline else {
            return .waiting(nextCheckAt: min(quietDeadline, deadline))
        }
        finished = true
        self.latest = nil
        self.quietSince = nil
        return .settled(latest)
    }

    private func fail(_ reason: Failure) -> Update {
        finished = true
        latest = nil
        quietSince = nil
        return .failed(reason)
    }
}
