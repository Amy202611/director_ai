import AppKit
let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile:"Resources/AppIconSource.png") else { fatalError("Missing supplied-camera icon adaptation") }
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,
    bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSColor.black.setFill()
NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
image.draw(in:NSRect(x:0,y:0,width:1024,height:1024),from:.zero,operation:.sourceOver,fraction:1)
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using:.png,properties:[:]) else { fatalError("PNG") }
try data.write(to:URL(fileURLWithPath:path))
