import Foundation

/// Injected-clock checks only: no sleeping, app, display, permissions or images.
@main
struct LongCaptureFrameSettlementChecks {
    private final class Payload {
        let pixels: Int
        let captureTimestamp: Double
        init(_ pixels: Int, timestamp: Double) {
            self.pixels = pixels
            captureTimestamp = timestamp
        }
    }
    private typealias Window = LongCaptureFrameSettlement<Payload>
    private static var checks = 0

    static func main() {
        stationaryStreamNeedsOneFrame()
        repeatedCompleteKeepsQuietStart()
        changedFrameRestartsQuietStart()
        incomingChangeWinsAgainstDueTimer()
        noFrameAndContinuousChangeTimeout()
        deadlineRejectsOldOrNewPayload()
        clocksAndConfiguration()
        releaseAndCancellation()
        print("RESULT: \(checks) deterministic settlement checks passed")
    }

    private static func make(start: Double = 0) -> Window {
        Window(startedAt: start, areEqual: { $0.pixels == $1.pixels })!
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
        checks += 1
    }

    private static func waiting(_ update: Window.Update, until expected: Double, _ label: String) {
        guard case .waiting(let time) = update else { preconditionFailure(label) }
        check(abs(time - expected) < 1e-12, label)
    }

    private static func failed(_ update: Window.Update, _ reason: Window.Failure, _ label: String) {
        guard case .failed(let actual) = update else { preconditionFailure(label) }
        check(actual == reason, label)
    }

    private static func terminal(_ update: Window.Update, _ label: String) {
        guard case .terminal = update else { preconditionFailure(label) }
        check(true, label)
    }

    private static func stationaryStreamNeedsOneFrame() {
        let window = make()
        waiting(window.poll(at: 0), until: 2, "no frame waits only until hard deadline")
        let first = Payload(10, timestamp: 99.123)
        waiting(window.observe(first, receivedAt: 0.1), until: 0.35, "first complete starts quiet timer")
        waiting(window.poll(at: 0.2), until: 0.35, "idle does not reset quiet timer")
        waiting(window.poll(at: 0.349), until: 0.35, "quiet window is not shortened")
        guard case .settled(let result) = window.poll(at: 0.35) else {
            preconditionFailure("static page must settle without a second complete")
        }
        check(result === first && result.captureTimestamp == 99.123, "latest real timestamp is preserved")
        terminal(window.poll(at: 0.4), "settlement is delivered once")
    }

    private static func repeatedCompleteKeepsQuietStart() {
        let window = make()
        _ = window.observe(Payload(10, timestamp: 1), receivedAt: 0)
        _ = window.observe(Payload(10, timestamp: 2), receivedAt: 0.1)
        waiting(window.observe(Payload(10, timestamp: 3), receivedAt: 0.2), until: 0.25,
                "identical surfaces cannot keep restarting quiet window")
        let newest = Payload(10, timestamp: 4)
        guard case .settled(let result) = window.observe(newest, receivedAt: 0.25) else {
            preconditionFailure("repeated completes should settle")
        }
        check(result === newest && result.captureTimestamp == 4, "return latest actual identical frame")
    }

    private static func changedFrameRestartsQuietStart() {
        let window = make()
        _ = window.observe(Payload(20, timestamp: 1), receivedAt: 0)
        waiting(window.observe(Payload(7, timestamp: 2), receivedAt: 0.1), until: 0.35,
                "bounce change resets quiet clock")
        waiting(window.observe(Payload(0, timestamp: 3), receivedAt: 0.3), until: 0.55,
                "returned position starts its own quiet window")
        waiting(window.poll(at: 0.35), until: 0.55, "outdated timer cannot settle an old frame")
        guard case .settled(let result) = window.poll(at: 0.55) else {
            preconditionFailure("bounce should settle only on stable latest frame")
        }
        check(result.pixels == 0 && result.captureTimestamp == 3, "bounce never returns first transient frame")
    }

    private static func incomingChangeWinsAgainstDueTimer() {
        let window = make()
        _ = window.observe(Payload(20, timestamp: 1), receivedAt: 0)
        waiting(window.observe(Payload(0, timestamp: 2), receivedAt: 0.25), until: 0.5,
                "a changed frame delivered at due time is observed before settling")
        guard case .settled(let result) = window.poll(at: 0.5) else { preconditionFailure("latest must settle") }
        check(result.pixels == 0, "due timer cannot choose discarded bounce payload")
    }

    private static func noFrameAndContinuousChangeTimeout() {
        let empty = make()
        failed(empty.poll(at: 2), .deadlineReached, "no complete frame fails at deadline")
        terminal(empty.observe(Payload(1, timestamp: 1), receivedAt: 2.1), "late first frame cannot reopen timeout")
        let changing = make()
        for index in 0..<20 {
            waiting(changing.observe(Payload(index, timestamp: Double(index)), receivedAt: Double(index) / 10),
                    until: min(Double(index) / 10 + 0.25, 2), "continuous updates remain bounded")
        }
        failed(changing.poll(at: 2), .deadlineReached, "continuous animation never returns an old stable picture")
        terminal(changing.poll(at: 3), "hard deadline does not restart")
    }

    private static func deadlineRejectsOldOrNewPayload() {
        let beforeBoundary = make()
        _ = beforeBoundary.observe(Payload(1, timestamp: 1), receivedAt: 1.74)
        guard case .settled = beforeBoundary.poll(at: 1.99) else {
            preconditionFailure("quiet completed before deadline must settle")
        }
        check(true, "settlement remains possible just before hard deadline")
        let atBoundary = make()
        _ = atBoundary.observe(Payload(1, timestamp: 1), receivedAt: 1.75)
        failed(atBoundary.poll(at: 2), .deadlineReached, "hard deadline wins over equal quiet deadline")
        let lateTimer = make()
        _ = lateTimer.observe(Payload(1, timestamp: 1), receivedAt: 0)
        failed(lateTimer.poll(at: 2.01), .deadlineReached, "late timer cannot return stale payload")
        let lateFrame = make()
        failed(lateFrame.observe(Payload(1, timestamp: 1), receivedAt: 2), .deadlineReached,
               "frame exactly at hard deadline is rejected")
    }

    private static func clocksAndConfiguration() {
        let equalTimes = make(start: 10)
        _ = equalTimes.observe(Payload(1, timestamp: 8), receivedAt: 10)
        waiting(equalTimes.poll(at: 10), until: 10.25, "equal receipt times are valid")
        let backwards = make()
        _ = backwards.observe(Payload(1, timestamp: 8), receivedAt: 0.1)
        failed(backwards.poll(at: 0.09), .nonMonotonicTime, "backwards clock fails explicitly")
        let invalid = make()
        failed(invalid.observe(Payload(1, timestamp: 8), receivedAt: .nan), .invalidTimestamp,
               "NaN receipt time fails")
        failed(make().poll(at: .infinity), .invalidTimestamp, "infinite receipt time fails")
        check(Window(startedAt: .nan, areEqual: { _, _ in true }) == nil, "invalid start clock rejected")
        check(Window(startedAt: 0, quietInterval: 0, areEqual: { _, _ in true }) == nil, "zero quiet window rejected")
        check(Window(startedAt: 0, timeout: .infinity, areEqual: { _, _ in true }) == nil, "infinite deadline rejected")
        check(Window(startedAt: 0, quietInterval: 2, timeout: 2, areEqual: { _, _ in true }) == nil,
              "configuration must permit settlement before hard deadline")
        check(Window(startedAt: .greatestFiniteMagnitude, areEqual: { _, _ in true }) == nil,
              "clock unable to represent quiet/deadline rejected")
    }

    private static func releaseAndCancellation() {
        let earlyCancellation = make()
        failed(earlyCancellation.cancel(), .cancelled, "cancellation before any complete is immediate")
        terminal(earlyCancellation.poll(at: 0), "cancelled empty window never starts a timer")
        let window = make()
        weak var old: Payload?
        weak var newest: Payload?
        do {
            let payload = Payload(20, timestamp: 1)
            old = payload
            _ = window.observe(payload, receivedAt: 0)
        }
        check(old != nil, "latest owns only the current actual payload")
        do {
            let payload = Payload(0, timestamp: 2)
            newest = payload
            _ = window.observe(payload, receivedAt: 0.1)
        }
        check(old == nil && newest != nil, "new observation releases replaced payload")
        do {
            guard case .settled(let result) = window.poll(at: 0.35) else { preconditionFailure("release settlement") }
            check(result === newest, "consumer receives latest payload")
        }
        check(newest == nil, "settled state does not cache delivered payload")
        let repeated = make()
        weak var duplicateOld: Payload?
        do {
            let payload = Payload(5, timestamp: 1)
            duplicateOld = payload
            _ = repeated.observe(payload, receivedAt: 0)
        }
        _ = repeated.observe(Payload(5, timestamp: 2), receivedAt: 0.1)
        check(duplicateOld == nil, "identical pixels also replace and release old capture payload")
        _ = repeated.cancel()
        let cancelled = make()
        weak var retained: Payload?
        do {
            let payload = Payload(1, timestamp: 1)
            retained = payload
            _ = cancelled.observe(payload, receivedAt: 0)
        }
        failed(cancelled.cancel(), .cancelled, "cancellation is terminal")
        check(retained == nil, "cancel promptly releases latest")
        terminal(cancelled.cancel(), "repeated cancellation delivers no second result")
        terminal(cancelled.observe(Payload(1, timestamp: 2), receivedAt: 0.5), "cancelled state ignores later payload")
        let timedOut = make()
        weak var timeoutPayload: Payload?
        do {
            let payload = Payload(1, timestamp: 1)
            timeoutPayload = payload
            _ = timedOut.observe(payload, receivedAt: 1.9)
        }
        failed(timedOut.poll(at: 2), .deadlineReached, "late frame still times out")
        check(timeoutPayload == nil, "timeout releases latest without delivering it")
        let badClock = make()
        weak var clockPayload: Payload?
        do {
            let payload = Payload(1, timestamp: 1)
            clockPayload = payload
            _ = badClock.observe(payload, receivedAt: 0.1)
        }
        failed(badClock.poll(at: 0), .nonMonotonicTime, "invalid clock terminates window")
        check(clockPayload == nil, "clock failure releases latest")
    }
}
