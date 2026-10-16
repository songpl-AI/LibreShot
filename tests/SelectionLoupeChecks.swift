import AppKit
import SwiftUI

@main struct SelectionLoupeChecks {
    @MainActor static func main() {
        let image = solidImage(width: 6, height: 5) { x, y in
            if x == 2 && y == 1 { return (220, 30, 40) }
            if x == 2 && y == 0 { return (255, 0, 0) }
            if x == 2 && y == 2 { return (0, 0, 255) }
            return (10, UInt8(x * 20), UInt8(y * 30))
        }
        let reading = SelectionLoupeSampler.sample(image: image, scale: 2, point: CGPoint(x: 1.2, y: 0.6))
        precondition(reading?.x == 1 && reading?.y == 1, "Coordinates use screen points")
        precondition(reading?.red == 220 && reading?.green == 30 && reading?.blue == 40, "Center sample is the pixel under the pointer")
        let oriented = SelectionLoupeSampler.sample(image: image, scale: 1, point: CGPoint(x: 2, y: 1))!
        let above = oriented.grid[(SelectionLoupeSampler.radius - 1) * oriented.side + SelectionLoupeSampler.radius]
        let below = oriented.grid[(SelectionLoupeSampler.radius + 1) * oriented.side + SelectionLoupeSampler.radius]
        precondition(above == SIMD3<UInt8>(255, 0, 0) && below == SIMD3<UInt8>(0, 0, 255),
                     "Content above the pointer stays above it in the loupe, not flipped")
        precondition(reading?.hexText == "HEX:#DC1E28" && reading?.copyText == "#DC1E28")
        let edge = SelectionLoupeSampler.sample(image: image, scale: 1, point: CGPoint(x: 0, y: 0))!
        precondition(edge.grid[0] == SIMD3<UInt8>(0, 0, 0), "Pixels outside the image stay black")
        precondition(edge.red == 10, "The clamped edge pixel is still sampled")

        let bounds = CGSize(width: 800, height: 500)
        let size = SelectionLoupeSampler.stackSize
        let lowerLeft = SelectionLoupeSampler.origin(anchor: CGPoint(x: 500, y: 120), bounds: bounds)
        precondition(lowerLeft.x + size.width < 500 && lowerLeft.y > 120, "The loupe stays below and left of the pointer")
        let flipped = SelectionLoupeSampler.origin(anchor: CGPoint(x: 40, y: 470), bounds: bounds)
        precondition(flipped.x > 40 && flipped.y + size.height < 470, "The loupe flips above and right at the bottom-left corner")

        let model = OverlayViewModel()
        model.state = .idle
        model.updatePreviewImage(image, scale: 2)
        model.updateSelectionLoupe(at: CGPoint(x: 1.2, y: 0.6))
        let board = NSPasteboard(name: NSPasteboard.Name("LibreShot.Loupe.\(UUID().uuidString)"))
        precondition(model.copySelectionLoupeColor(to: board) && board.string(forType: .string) == "#DC1E28")
        let shift = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .shift, timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: 56)!
        precondition(!model.performSelectionLoupeShortcut(shift) && model.selectionLoupeShowsRGB)
        precondition(model.copySelectionLoupeColor(to: board) && board.string(forType: .string) == "220,30,40")
        model.state = .editing
        let copy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
                                     isARepeat: false, keyCode: 8)!
        precondition(!model.performSelectionLoupeShortcut(copy), "Finished editing keeps Command-C for the screenshot")
        print("PASS: selection loupe samples the pointer pixel, stays below-left, and copies HEX or RGB")
    }

    static func solidImage(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let buffer = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = pixel(x, y)
                let index = (y * width + x) * 4
                buffer[index] = color.0
                buffer[index + 1] = color.1
                buffer[index + 2] = color.2
                buffer[index + 3] = 255
            }
        }
        return context.makeImage()!
    }
}
