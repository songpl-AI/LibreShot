import SwiftUI

struct SelectionLoupeReading: Equatable {
    var x: Int
    var y: Int
    var red: Int
    var green: Int
    var blue: Int
    /// Row-major RGB samples. The center sample is the pixel under the pointer.
    var grid: [SIMD3<UInt8>]
    var side: Int

    var hexText: String { String(format: "HEX:#%02X%02X%02X", red, green, blue) }
    var rgbText: String { "RGB:\(red),\(green),\(blue)" }
    var copyText: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var copyRGBText: String { "\(red),\(green),\(blue)" }
}

enum SelectionLoupeSampler {
    /// Enough surrounding pixels to recognize the content, not only the one color cell.
    static let radius = 16
    static var side: Int { radius * 2 + 1 }
    static let loupeSize: CGFloat = 176
    static var pixelSize: CGFloat { loupeSize / CGFloat(side) }
    static let cardSize = CGSize(width: 176, height: 86)
    static var stackSize: CGSize { CGSize(width: max(loupeSize, cardSize.width), height: loupeSize + 6 + cardSize.height) }

    static func sample(image: CGImage, scale: CGFloat, point: CGPoint) -> SelectionLoupeReading? {
        guard scale > 0, image.width > 0, image.height > 0 else { return nil }
        let px = min(max(Int(floor(point.x * scale)), 0), image.width - 1)
        let py = min(max(Int(floor(point.y * scale)), 0), image.height - 1)
        let grid = magnified(image: image, centerX: px, centerY: py, radius: radius)
        let center = grid[radius * side + radius]
        return SelectionLoupeReading(x: Int(point.x.rounded()), y: Int(point.y.rounded()),
                                     red: Int(center.x), green: Int(center.y), blue: Int(center.z),
                                     grid: grid, side: side)
    }

    /// A selection usually grows down and right. Keep the loupe below and left of the pointer
    /// so it does not cover the edge being drawn. Flip only when that side leaves the screen.
    static func origin(anchor: CGPoint, bounds: CGSize, gap: CGFloat = 18) -> CGPoint {
        let size = stackSize
        var origin = CGPoint(x: anchor.x - gap - size.width, y: anchor.y + gap)
        if origin.x < 8 { origin.x = anchor.x + gap }
        if origin.y + size.height > bounds.height - 8 { origin.y = anchor.y - gap - size.height }
        origin.x = min(max(8, origin.x), max(8, bounds.width - size.width - 8))
        origin.y = min(max(8, origin.y), max(8, bounds.height - size.height - 8))
        return origin
    }

    private static func magnified(image: CGImage, centerX: Int, centerY: Int, radius: Int) -> [SIMD3<UInt8>] {
        let side = radius * 2 + 1
        var pixels = Array(repeating: SIMD3<UInt8>(0, 0, 0), count: side * side)
        let request = CGRect(x: centerX - radius, y: centerY - radius, width: side, height: side)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let visible = request.intersection(bounds).integral
        // Readouts are always sRGB so HEX/RGB values match common pickers even on a
        // Display P3 screen. Device RGB is only a fallback and is not the target space.
        let readoutSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard visible.width >= 1, visible.height >= 1, let crop = image.cropping(to: visible),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: readoutSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return pixels }
        let destX = visible.minX - request.minX
        let destYFromTop = visible.minY - request.minY
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(x: destX, y: CGFloat(side) - destYFromTop - visible.height,
                                      width: visible.width, height: visible.height))
        let buffer = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for row in 0..<side {
            for col in 0..<side {
                let index = (row * side + col) * 4
                pixels[row * side + col] = SIMD3(buffer[index], buffer[index + 1], buffer[index + 2])
            }
        }
        return pixels
    }
}

struct SelectionLoupeView: View {
    let reading: SelectionLoupeReading
    var showsRGB = false
    var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                let cell = size.width / CGFloat(reading.side)
                for row in 0..<reading.side {
                    for col in 0..<reading.side {
                        let sample = reading.grid[row * reading.side + col]
                        let color = Color(red: Double(sample.x) / 255, green: Double(sample.y) / 255, blue: Double(sample.z) / 255)
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell + 0.5, height: cell + 0.5)
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                let mid = CGFloat(reading.side / 2)
                let center = CGRect(x: mid * cell, y: mid * cell, width: cell, height: cell)
                var cross = Path()
                cross.move(to: CGPoint(x: 0, y: center.midY))
                cross.addLine(to: CGPoint(x: center.minX, y: center.midY))
                cross.move(to: CGPoint(x: center.maxX, y: center.midY))
                cross.addLine(to: CGPoint(x: size.width, y: center.midY))
                cross.move(to: CGPoint(x: center.midX, y: 0))
                cross.addLine(to: CGPoint(x: center.midX, y: center.minY))
                cross.move(to: CGPoint(x: center.midX, y: center.maxY))
                cross.addLine(to: CGPoint(x: center.midX, y: size.height))
                context.stroke(cross, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 3))
                context.stroke(cross, with: .color(Color(red: 0.25, green: 0.52, blue: 1)), style: StrokeStyle(lineWidth: 1.5))
                context.stroke(Path(center), with: .color(.white), style: StrokeStyle(lineWidth: 1))
            }
            .frame(width: SelectionLoupeSampler.loupeSize, height: SelectionLoupeSampler.loupeSize)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.85), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text("坐标: \(reading.x),\(reading.y)")
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: Double(reading.red) / 255, green: Double(reading.green) / 255, blue: Double(reading.blue) / 255))
                        .frame(width: 10, height: 10)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.85), lineWidth: 0.5))
                    Text(showsRGB ? "sRGB \(reading.rgbText)" : "sRGB \(reading.hexText)")
                }
                Text(copied ? "已复制" : "按 ⌘ + C 复制色值")
                Text("按 Shift 切换 RGB/HEX")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(8)
            .frame(width: SelectionLoupeSampler.cardSize.width, height: SelectionLoupeSampler.cardSize.height, alignment: .topLeading)
            .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("selection-loupe")
        .accessibilityLabel("\(reading.x),\(reading.y) 原图取色 \(showsRGB ? reading.rgbText : reading.hexText) sRGB")
    }
}
