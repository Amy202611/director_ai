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
    private func white(_ image:UIImage,top:Bool)->Int {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        let rendered = UIGraphicsImageRenderer(size:image.size,format:f).image { _ in image.draw(at:.zero) }
        guard let cg = rendered.cgImage,let data = cg.dataProvider?.data,let bytes = CFDataGetBytePtr(data),cg.bitsPerPixel == 32 else { return 0 }
        let w = Int(image.size.width),h = Int(image.size.height)
        let start = top ? 0 : h/2,end = top ? h/2 : h
        var count = 0
        for y in start..<end { for x in 0..<w {
            let p = y*cg.bytesPerRow+x*4
            if bytes[p]>170 && bytes[p+1]>170 && bytes[p+2]>170 { count += 1 }
        } }
        return count
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
