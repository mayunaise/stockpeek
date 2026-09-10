import AppKit

// Reuse the exact SF Symbol and accent color used by the application's sidebar.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.16, blue: 0.20, alpha: 1),
           ending: NSColor(srgbRed: 0.035, green: 0.045, blue: 0.065, alpha: 1))!.draw(in: tile, angle: -90)
NSColor(srgbRed: 0.65, green: 0.79, blue: 0.98, alpha: 0.20).setStroke()
tile.lineWidth = 2
tile.stroke()
let accent = NSColor(srgbRed: 0.65, green: 0.79, blue: 0.98, alpha: 1)
let configuration = NSImage.SymbolConfiguration(pointSize: 440, weight: .light)
    .applying(NSImage.SymbolConfiguration(paletteColors: [accent]))
let symbol = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
let width: CGFloat = 610
let height = width * symbol.size.height / symbol.size.width
symbol.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Assets/AppIcon.png"))
