import XCTest
import AVFoundation
import UIKit
@testable import MoyuCamera

final class CameraPipelineTests:XCTestCase {
    func testDatesAndEmptyFields() {
        var s = Stamp()
        var c = Calendar(identifier:.gregorian); c.timeZone = .current
        s.date = c.date(from:DateComponents(year:2026,month:1,day:1,hour:9,minute:5))!
        XCTAssertTrue(s.timeText.contains("2026年1月1日"))
        XCTAssertTrue(s.timeText.contains("星期四"))
        XCTAssertTrue(s.timeText.hasSuffix("09:05"))
        s.showDate = false; XCTAssertEqual(s.timeText,"09:05")
        s.showTime = false; XCTAssertEqual(s.timeText,"")
        s.top = ""; s.main = ""; s.badge = ""; XCTAssertFalse(s.hasBrand)
    }
    func testPhotoEmptyAndMovedWatermark() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let source = UIGraphicsImageRenderer(size:CGSize(width:600,height:800),format:format).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(x:0,y:0,width:600,height:800))
        }
        var s = Stamp(); s.showDate = false; s.showTime = false; s.top = ""; s.main = ""; s.badge = ""
        XCTAssertEqual(white(StampRenderer.photo(source,s),top:false),0)
        s.badge = "TEST"
        let baked = StampRenderer.photo(source,s)
        XCTAssertGreaterThan(white(baked,top:false),50)
        XCTAssertEqual(white(baked,top:true),0)
        XCTAssertEqual(white(source,top:false),0)
        s.x = 0.2; s.y = 0.2
        let moved = StampRenderer.photo(source,s)
        XCTAssertGreaterThan(white(moved,top:true),50)
        XCTAssertEqual(white(moved,top:false),0)
    }
    func testPauseResumeMergeDuration() async throws {
        let a = try await fixture(frames:15,rotated:false)
        let b = try await fixture(frames:30,rotated:false)
        defer { remove([a,b]) }
        let output = try await Media.merge([a,b])
        defer { remove([output]) }
        let duration = try await AVURLAsset(url:output).load(.duration)
        XCTAssertEqual(CMTimeGetSeconds(duration),1.5,accuracy:0.12)
    }
    func testPortraitVideoWatermarkMatchesPreview() async throws {
        let source = try await fixture(frames:30,rotated:true)
        defer { remove([source]) }
        var s = Stamp(); s.showDate = false; s.showTime = false; s.top = ""; s.main = ""; s.badge = "TEST"
        let output = try await Media.export(source,stamp:s,limit:320,keepAudio:false,progress:{_ in})
        defer { remove([output]) }
        let asset = AVURLAsset(url:output)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width,240,accuracy:2); XCTAssertEqual(size.height,320,accuracy:2)
        let audio = try await asset.loadTracks(withMediaType:.audio)
        XCTAssertTrue(audio.isEmpty)
        let gen = AVAssetImageGenerator(asset:asset); gen.appliesPreferredTrackTransform = true
        let image = UIImage(cgImage:try gen.copyCGImage(at:CMTime(value:1,timescale:2),actualTime:nil))
        XCTAssertGreaterThan(white(image,top:false),20,"Saved video watermark must be at the bottom")
        XCTAssertEqual(white(image,top:true),0,"Saved video must match preview, without vertical flip")
    }
    func testSerialLengthAlphabetAndRandomness() {
        var values = Set<String>()
        for _ in 0..<500 {
            let code = StampSerial.make()
            XCTAssertEqual(code.count,15)
            XCTAssertNotNil(code.range(of:"^[A-Z0-9]{15}$",options:.regularExpression))
            XCTAssertTrue(values.insert(code).inserted)
            var stamp = Stamp(); stamp.serial = code
            XCTAssertEqual(stamp.serialText,"防伪 "+code)
            XCTAssertFalse(stamp.serialText.contains("©"))
        }
    }
    @MainActor func testPhotoIdentitySurvivesEditingSavingAndTemplateReload() throws {
        let suite = "camera.tests."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store = StampStore(defaults:defaults)
        let first = store.snapshot().serial
        store.value.address = "天津市和平区完整地址"; store.save()
        XCTAssertEqual(store.snapshot().serial,first)
        store.save(); XCTAssertEqual(store.snapshot().serial,first)
        let template = try JSONDecoder().decode(Stamp.self,from:defaults.data(forKey:"moyu.stamp.v3")!)
        XCTAssertNil(template.serial)
        store.beginMedia()
        XCTAssertNotEqual(store.snapshot().serial,first)
        var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Stamp())) as! [String:Any]
        legacy.removeValue(forKey:"serial")
        let decoded = try JSONDecoder().decode(Stamp.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(decoded.serial)
    }
    func testLongAddressWrapsAndPreservesItsEnding() {
        var stamp = Stamp()
        stamp.address = String(repeating:"天津市和平区康定路地铁站出口附近",count:5)+"最终门牌号"
        stamp.serial = "Q7M4K9X2R8P5T6A"
        let rows = StampRenderer.detailRows(CGSize(width:600,height:800),stamp)
        let address = rows.first { $0.text.hasPrefix("地点：") }!
        XCTAssertTrue(address.text.hasSuffix("最终门牌号"))
        XCTAssertGreaterThan(address.rect.height,UIFont.systemFont(ofSize:18,weight:.semibold).lineHeight*3)
        XCTAssertGreaterThanOrEqual(address.rect.minY,0)
        XCTAssertLessThan(address.rect.maxY,800-14-15)
    }
    func testRetinaPhotoAndPreviewRetainPixelDimensions() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 2; format.opaque = true
        let source = UIGraphicsImageRenderer(size:CGSize(width:300,height:400),format:format).image { _ in
            UIColor.black.setFill(); UIRectFill(CGRect(x:0,y:0,width:300,height:400))
        }
        let output = StampRenderer.photo(source,Stamp())
        XCTAssertEqual(output.cgImage?.width,600); XCTAssertEqual(output.cgImage?.height,800)
        let preview = StampRenderer.overlay(CGSize(width:200,height:300),Stamp(),rasterScale:3)
        XCTAssertEqual(preview.cgImage?.width,600); XCTAssertEqual(preview.cgImage?.height,900)
    }
    func testCompiledHomeScreenIconHasColoredArtwork() throws {
        let bundle = Bundle(for:Camera.self)
        let paths = bundle.paths(forResourcesOfType:"png",inDirectory:nil).filter { URL(fileURLWithPath:$0).lastPathComponent.hasPrefix("AppIcon") }
        XCTAssertFalse(paths.isEmpty,"Compiled iPhone icon rasters must be present")
        for path in paths {
            let icon = try XCTUnwrap(UIImage(contentsOfFile:path))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let sampled = UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:format).image { _ in
                icon.draw(in:CGRect(x:0,y:0,width:64,height:64))
            }
            let cg = try XCTUnwrap(sampled.cgImage)
            let data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = CFDataGetBytePtr(data)!
            var bright = 0, colors = Set<Int>()
            for y in 0..<64 { for x in 0..<64 {
                let p = y*cg.bytesPerRow+x*4
                if max(bytes[p],max(bytes[p+1],bytes[p+2])) > 40 { bright += 1 }
                colors.insert(Int(bytes[p]/32)*64+Int(bytes[p+1]/32)*8+Int(bytes[p+2]/32))
            } }
            XCTAssertGreaterThan(bright,409,"App icon must not be a black square")
            XCTAssertGreaterThan(colors.count,16,"App icon must contain real artwork")
        }
    }
    private func white(_ image:UIImage,top:Bool)->Int {
        guard let cg = image.cgImage else { XCTFail("Missing pixels"); return 0 }
        let w = cg.width,h = cg.height
        print("Watermark pixel format: bitsPerComponent=\(cg.bitsPerComponent), bitsPerPixel=\(cg.bitsPerPixel), size=\(w)x\(h)")
        guard let space = CGColorSpace(name:CGColorSpace.sRGB),
              let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:space,
                bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data else { XCTFail("RGBA normalization failed"); return 0 }
        context.draw(cg,in:CGRect(x:0,y:0,width:CGFloat(w),height:CGFloat(h)))
        let bytes = pixels.assumingMemoryBound(to:UInt8.self)
        let start = top ? 0 : h/2,end = top ? h/2 : h
        var count = 0
        for y in start..<end { for x in 0..<w {
            let p = y*context.bytesPerRow+x*4
            if bytes[p]>170 && bytes[p+1]>170 && bytes[p+2]>170 { count += 1 }
        } }
        return count
    }
    func testPixelInspectionPreservesGrayscaleRows() throws {
        let w = 20,h = 20
        var bytes = [UInt8](repeating:0,count:w*h)
        for y in 0..<10 { for x in 0..<20 { bytes[y*w+x] = 255 } }
        let data = Data(bytes)
        let provider = try XCTUnwrap(CGDataProvider(data:data as CFData))
        let cg = try XCTUnwrap(CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,
            space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),
            provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let image = UIImage(cgImage:cg)
        XCTAssertEqual(white(image,top:true),200)
        XCTAssertEqual(white(image,top:false),0)
    }
    private func fixture(frames:Int,rotated:Bool) async throws -> URL {
        let url = Media.file(".mov")
        let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[
            AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240])
        input.expectsMediaDataInRealTime = false
        if rotated { input.transform = CGAffineTransform(a:0,b:1,c:-1,d:0,tx:240,ty:0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:240])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime:.zero)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error! }
                try await Task.sleep(nanoseconds:10_000_000)
            }
            var buffer:CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault,320,240,kCVPixelFormatType_32ARGB,nil,&buffer) == kCVReturnSuccess,
                  let buffer else { throw Media.error("Test pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer,[])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<240 { for x in 0..<320 {
                let p = y*row+x*4; bytes[p] = 255; bytes[p+1] = 12; bytes[p+2] = 12; bytes[p+3] = 12
            } }
            CVPixelBufferUnlockBaseAddress(buffer,[])
            guard adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(index),timescale:30)) else { throw writer.error! }
        }
        input.markAsFinished(); writer.endSession(atSourceTime:CMTime(value:Int64(frames),timescale:30))
        await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in writer.finishWriting { c.resume() } }
        guard writer.status == .completed else { throw writer.error! }
        return url
    }
    private func remove(_ urls:[URL]) { for url in urls { try? FileManager.default.removeItem(at:url) } }
}
