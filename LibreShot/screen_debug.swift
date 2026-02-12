
import ScreenCaptureKit
import AppKit

@main
struct ScreenInfo {
    static func main() async {
        do {
            let content = try await SCShareableContent.current
            print("--- SCDisplay Info ---")
            for display in content.displays {
                print("Display ID: \(display.displayID)")
                print("  SCDisplay Size: \(display.width) x \(display.height)")
            }
            
            print("\n--- NSScreen Info ---")
            await MainActor.run {
                for screen in NSScreen.screens {
                    let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    print("Screen ID: \(id ?? 0)")
                    print("  Frame (Points): \(screen.frame.width) x \(screen.frame.height)")
                    print("  Scale Factor: \(screen.backingScaleFactor)")
                    let pixelWidth = screen.frame.width * screen.backingScaleFactor
                    let pixelHeight = screen.frame.height * screen.backingScaleFactor
                    print("  Calculated Pixels: \(Int(pixelWidth)) x \(Int(pixelHeight))")
                }
            }
        } catch {
            print("Error: \(error)")
        }
        exit(0)
    }
}
