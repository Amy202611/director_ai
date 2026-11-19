import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

let destination = CommandLine.arguments[1]
let sourceURL = URL(fileURLWithPath:"Resources/AppIconSource.png")
let sourceData = try Data(contentsOf:sourceURL)
guard let source = CGImageSourceCreateWithData(sourceData as CFData,nil),
      let image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
      image.width >= 1024,image.height >= 1024 else { fatalError("Missing or invalid supplied camera icon") }

func render(_ image:CGImage, _ pixels:Int) throws -> CGImage {
    guard let space = CGColorSpace(name:CGColorSpace.sRGB),
          let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,space:space,
            bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { fatalError("Icon bitmap") }
    context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:CGFloat(pixels),height:CGFloat(pixels)))
    context.interpolationQuality = .high
    context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(pixels),height:CGFloat(pixels)))
    guard let output = context.makeImage() else { fatalError("Icon render failed") }
    return output
}
func quality(_ image:CGImage) throws -> Double {
    let sampled = try render(image,64)
    guard let bytes = sampled.dataProvider?.data,let pointer = CFDataGetBytePtr(bytes) else { fatalError("Icon pixels") }
    var visible = 0
    for y in 0..<64 { for x in 0..<64 {
        let p = y*sampled.bytesPerRow+x*4
        if max(pointer[p],max(pointer[p+1],pointer[p+2])) > 40 { visible += 1 }
    } }
    let fraction = Double(visible)/4096
    guard fraction > 0.1 else { fatalError("Refusing blank black app icon") }
    return fraction
}
let icon = try render(image,1024)
let visible = try quality(icon)
guard let writer = CGImageDestinationCreateWithURL(URL(fileURLWithPath:destination) as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("Icon PNG destination") }
CGImageDestinationAddImage(writer,icon,nil)
guard CGImageDestinationFinalize(writer) else { fatalError("Icon PNG write failed") }
let decoded = CGImageSourceCreateWithURL(URL(fileURLWithPath:destination) as CFURL,nil)!
guard let check = CGImageSourceCreateImageAtIndex(decoded,0,nil) else { fatalError("Generated icon cannot be decoded") }
_ = try quality(check)
let catalog = URL(fileURLWithPath:destination).deletingLastPathComponent()
var entries: [[String:Any]] = []
for size in [20,29,40,60] {
    for scale in [2,3] {
        let pixels = size*scale, name = "AppIcon-\(size*scale).png"
        let resized = try render(image,pixels)
        guard let target = CGImageDestinationCreateWithURL(catalog.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("Icon variant") }
        CGImageDestinationAddImage(target,resized,nil)
        guard CGImageDestinationFinalize(target) else { fatalError("Icon variant write") }
        entries.append(["filename":name,"idiom":"iphone","size":"\(size)x\(size)","scale":"\(scale)x"])
    }
}
entries.append(["filename":URL(fileURLWithPath:destination).lastPathComponent,"idiom":"ios-marketing","size":"1024x1024","scale":"1x"])
try JSONSerialization.data(withJSONObject:["images":entries,"info":["author":"xcode","version":1]],options:.prettyPrinted).write(to:catalog.appendingPathComponent("Contents.json"))
let report: [String:Any] = ["sourceSHA256":SHA256.hash(data:sourceData).map { String(format:"%02x",$0) }.joined(),
    "width":check.width,"height":check.height,"visiblePixelFraction":visible,"blankBlackIcon":false]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"build/artifacts/ICON-REPORT.json"))
print("Camera icon rendered with ImageIO/CoreGraphics and verified:",visible)
