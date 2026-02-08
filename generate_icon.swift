import Cocoa

// 1. Create the base image (1024x1024 for high res)
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

// Draw background (White rounded rectangle, like macOS apps)
// Standard macOS icon shape is a squircle
let rect = CGRect(origin: .zero, size: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
NSColor.white.setFill()
path.fill()

// Draw Scissors (System Symbol)
// We'll draw it in the center, large and blue
if let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil) {
    let symbolSize = CGSize(width: 600, height: 600)
    let symbolRect = CGRect(
        x: (size.width - symbolSize.width) / 2,
        y: (size.height - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    
    // Tint the symbol blue (macOS Accent Color style)
    let config = NSImage.SymbolConfiguration(pointSize: 500, weight: .regular)
        .applying(.init(paletteColors: [.systemBlue]))
    
    if let tintedSymbol = symbol.withSymbolConfiguration(config) {
        tintedSymbol.draw(in: symbolRect)
    } else {
        // Fallback if tinting fails (shouldn't happen on modern macOS)
        symbol.draw(in: symbolRect)
    }
}

image.unlockFocus()

// 2. Save to file
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    
    let url = URL(fileURLWithPath: "icon_1024.png")
    try? pngData.write(to: url)
    print("Icon generated: \(url.path)")
} else {
    print("Failed to generate icon")
}
