import AppKit
let path = CommandLine.arguments[1]
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("icon bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let teal = NSColor(calibratedRed: 0.03, green: 0.40, blue: 0.41, alpha: 1)
teal.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 170, y: 270, width: 684, height: 480), xRadius: 90, yRadius: 90).fill()
NSBezierPath(roundedRect: NSRect(x: 340, y: 700, width: 344, height: 95), xRadius: 24, yRadius: 24).fill()
teal.setFill()
NSBezierPath(ovalIn: NSRect(x: 340, y: 345, width: 344, height: 344)).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 408, y: 413, width: 208, height: 208)).fill()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("icon PNG") }
try data.write(to: URL(fileURLWithPath: path))
