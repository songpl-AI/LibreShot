import AppKit
import SwiftUI

/// Area capture follows the pointer across displays: trigger anywhere, move the
/// mouse to the display you want, and the overlay plus its frozen preview move
/// with it. The move is debounced so grazing a screen seam does not thrash the
/// preview capture.
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
        var pointer = CGPoint(x: primary.frame.midX, y: primary.frame.midY)
        var requestedDisplayIDs: [CGDirectDisplayID?] = []

        let controller = OverlayWindowController()
        controller.pointerLocationProvider = { pointer }
        controller.previewImageLoader = { id in
            requestedDisplayIDs.append(id)
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
        let deadline = Date().addingTimeInterval(5)
        while !window.isVisible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(window.isVisible, "the overlay appears on the display under the pointer")
        let startFrame = window.frame

        // A pointer that merely grazes the other display must not move the overlay.
        let secondary = screens[1]
        pointer = CGPoint(x: secondary.frame.midX, y: secondary.frame.midY)
        controller.followPointerIfNeeded(now: 100)
        check(window.frame == startFrame, "one poll on the seam keeps the overlay in place")

        // Staying on the other display moves the overlay and re-captures there.
        controller.followPointerIfNeeded(now: 100.5)
        let settle = Date().addingTimeInterval(3)
        while window.frame != secondary.frame, Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(window.frame == secondary.frame, "the overlay follows the pointer to the secondary display")
        check(controller.getCurrentDisplayID() == displayID(secondary),
              "the capture target follows the pointer, not the trigger display")
        let previewDeadline = Date().addingTimeInterval(3)
        while requestedDisplayIDs.last ?? nil != displayID(secondary), Date() < previewDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(requestedDisplayIDs.last ?? nil == displayID(secondary),
              "the frozen preview is re-captured from the secondary display")

        // Moving back must return to the original display as well.
        pointer = CGPoint(x: primary.frame.midX, y: primary.frame.midY)
        controller.followPointerIfNeeded(now: 101)
        controller.followPointerIfNeeded(now: 101.5)
        let backDeadline = Date().addingTimeInterval(3)
        while window.frame != primary.frame, Date() < backDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(window.frame == primary.frame, "moving back returns the overlay to the first display")
        check(controller.getCurrentDisplayID() == displayID(primary),
              "the capture target returns with the pointer")

        controller.close()
        print(failures == 0 ? "All pointer follow checks passed" : "\(failures) pointer follow check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
