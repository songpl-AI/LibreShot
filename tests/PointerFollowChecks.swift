import AppKit
import SwiftUI

/// Area capture follows the pointer across displays: trigger anywhere, move the
/// mouse to the display you want, and the overlay plus its frozen preview move
/// with it. The move is debounced, and the overlay only moves once the new
/// display's preview has actually been captured — a failed capture keeps the
/// session on the current display instead of showing a blank canvas.
@main
struct PointerFollowChecks {
    @MainActor static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var failures = 0
        func check(_ passed: Bool, _ label: String) {
            print("\(passed ? "PASS" : "FAIL"): \(label)")
            if !passed { failures += 1 }
        }
        func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }

        let screens = NSScreen.screens
        guard screens.count > 1 else {
            print("SKIP: single-display host, pointer following needs at least two screens")
            exit(0)
        }
        let primary = screens[0]
        let secondary = screens[1]
        let secondaryID = displayID(secondary)

        var pointer = CGPoint(x: primary.frame.midX, y: primary.frame.midY)
        var requestedDisplayIDs: [CGDirectDisplayID?] = []
        var failingDisplayIDs: Set<CGDirectDisplayID> = []
        struct CaptureFailure: Error {}

        let controller = OverlayWindowController()
        controller.pointerLocationProvider = { pointer }
        controller.previewImageLoader = { id in
            requestedDisplayIDs.append(id)
            if let id, failingDisplayIDs.contains(id) { throw CaptureFailure() }
            let screen = screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id
            } ?? primary
            let size = screen.frame.size
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()
            return image
        }
        controller.show(onCapture: { _, _, _, _, _ in }, onCancel: {})
        defer { controller.close() }

        guard let window = controller.window else {
            print("FAIL: the capture overlay window was not created")
            exit(1)
        }
        func spin(until condition: @escaping () -> Bool, timeout: TimeInterval = 3) {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
        }
        spin { window.isVisible }
        check(window.isVisible, "the overlay appears on the display under the pointer")
        let startFrame = window.frame

        // A pointer that merely grazes the other display must not move the overlay.
        pointer = CGPoint(x: secondary.frame.midX, y: secondary.frame.midY)
        controller.followPointerIfNeeded(now: 100)
        check(window.frame == startFrame, "one poll on the seam keeps the overlay in place")

        // Staying on the other display moves the overlay and re-captures there.
        controller.followPointerIfNeeded(now: 100.5)
        spin { window.frame == secondary.frame }
        check(window.frame == secondary.frame, "the overlay follows the pointer to the secondary display")
        check(controller.getCurrentDisplayID() == secondaryID,
              "the capture target follows the pointer, not the trigger display")
        spin { requestedDisplayIDs.last ?? nil == secondaryID }
        check(requestedDisplayIDs.last ?? nil == secondaryID,
              "the frozen preview is re-captured from the secondary display")

        // Moving back must return to the original display as well.
        pointer = CGPoint(x: primary.frame.midX, y: primary.frame.midY)
        controller.followPointerIfNeeded(now: 101)
        controller.followPointerIfNeeded(now: 101.5)
        spin { window.frame == primary.frame }
        check(window.frame == primary.frame, "moving back returns the overlay to the first display")
        check(controller.getCurrentDisplayID() == displayID(primary),
              "the capture target returns with the pointer")

        // A display whose capture fails must not be adopted: the overlay and its
        // frozen preview stay where they are instead of showing a blank canvas.
        if let secondaryID { failingDisplayIDs = [secondaryID] }
        pointer = CGPoint(x: secondary.frame.midX, y: secondary.frame.midY)
        controller.followPointerIfNeeded(now: 200)
        controller.followPointerIfNeeded(now: 200.5)
        spin { false }  // let the failing capture settle
        check(window.frame == primary.frame, "a failed capture keeps the overlay on the current display")
        check(controller.getCurrentDisplayID() == displayID(primary),
              "a failed capture keeps the capture target on the current display")

        // The failed display is retried only after the back-off, then adopted.
        failingDisplayIDs = []
        controller.followPointerIfNeeded(now: 200.6)
        controller.followPointerIfNeeded(now: 201)
        check(window.frame == primary.frame, "a display that just failed is not retried immediately")
        controller.followPointerIfNeeded(now: 204)
        controller.followPointerIfNeeded(now: 204.5)
        spin { window.frame == secondary.frame }
        check(window.frame == secondary.frame, "the failed display is adopted once its capture succeeds")

        controller.close()
        print(failures == 0 ? "All pointer follow checks passed" : "\(failures) pointer follow check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
