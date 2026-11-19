import UIKit
import Photos
import ImageIO
import AVFoundation

enum Media {
    static func file(_ suffix:String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+suffix) }
    static func error(_ text:String) -> NSError { NSError(domain:"MoyuCamera",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
    static func decode(_ data:Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData,nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:3072] as CFDictionary) else { return nil }
        return UIImage(cgImage:cg)
    }
    static func save(image:UIImage?,video:URL?) async throws {
        let status:PHAuthorizationStatus = await withCheckedContinuation { c in
            PHPhotoLibrary.requestAuthorization(for:.addOnly) { c.resume(returning:$0) }
        }
        guard status == .authorized || status == .limited else { throw error("请在系统设置中允许添加照片和视频。") }
        guard image != nil || video != nil else { throw error("没有可保存的素材") }
        try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
            PHPhotoLibrary.shared().performChanges {
                if let image { PHAssetChangeRequest.creationRequestForAsset(from:image) }
                else if let video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:video) }
            } completionHandler: { ok,err in
                if ok { c.resume() } else { c.resume(throwing:err ?? error("保存相册失败")) }
            }
        }
    }
    static func finish(_ exporter:AVAssetExportSession) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler(operation:{
            await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in exporter.exportAsynchronously { c.resume() } }
            guard exporter.status == .completed else { throw exporter.error ?? error("视频处理失败或已取消") }
            try Task.checkCancellation()
        },onCancel:{ exporter.cancelExport() })
    }
    static func merge(_ urls:[URL]) async throws -> URL {
        guard !urls.isEmpty else { throw error("没有可合并的录像片段") }
        let c = AVMutableComposition()
        guard let v = c.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw error("无法建立视频轨道") }
        var a:AVMutableCompositionTrack?
        var cursor = CMTime.zero
        for (index,url) in urls.enumerated() {
            let asset = AVURLAsset(url:url)
            guard let source = try await asset.loadTracks(withMediaType:.video).first else { throw error("录像片段缺少画面") }
            let range = try await source.load(.timeRange)
            try v.insertTimeRange(range,of:source,at:cursor)
            if index == 0 { v.preferredTransform = try await source.load(.preferredTransform) }
            if let audio = try await asset.loadTracks(withMediaType:.audio).first {
                if a == nil { a = c.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) }
                let ar = CMTimeRangeGetIntersection(range,try await audio.load(.timeRange))
                if ar.isValid && CMTimeCompare(ar.duration,.zero) > 0 { try a?.insertTimeRange(ar,of:audio,at:CMTimeAdd(cursor,CMTimeSubtract(ar.start,range.start))) }
            }
            cursor = CMTimeAdd(cursor,range.duration)
        }
        guard let ex = AVAssetExportSession(asset:c,presetName:AVAssetExportPresetHighestQuality) else { throw error("无法创建合并任务") }
        let output = file(".mp4"); ex.outputURL = output; ex.outputFileType = .mp4
        do { try await finish(ex); return output } catch { try? FileManager.default.removeItem(at:output); throw error }
    }
    static func export(_ url:URL,stamp:Stamp,limit:CGFloat,keepAudio:Bool,progress:@escaping(Double)->Void) async throws -> URL {
        let asset = AVURLAsset(url:url)
        guard let source = try await asset.loadTracks(withMediaType:.video).first else { throw error("视频没有画面轨道") }
        let range = try await source.load(.timeRange), natural = try await source.load(.naturalSize)
        let transform = try await source.load(.preferredTransform)
        let bounds = CGRect(origin:.zero,size:natural).applying(transform)
        guard abs(bounds.width)>0,abs(bounds.height)>0 else { throw error("视频尺寸无效") }
        let scale = min(1,limit/max(abs(bounds.width),abs(bounds.height)))
        let size = CGSize(width:max(2,floor(abs(bounds.width)*scale/2)*2),height:max(2,floor(abs(bounds.height)*scale/2)*2))
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw error("无法建立视频轨道") }
        try video.insertTimeRange(range,of:source,at:.zero)
        if keepAudio,let audio = try await asset.loadTracks(withMediaType:.audio).first,
           let target = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
            let ar = CMTimeRangeGetIntersection(range,try await audio.load(.timeRange))
            if ar.isValid && CMTimeCompare(ar.duration,.zero)>0 { try target.insertTimeRange(ar,of:audio,at:CMTimeSubtract(ar.start,range.start)) }
        }
        let li = AVMutableVideoCompositionLayerInstruction(assetTrack:video)
        li.setTransform(transform.concatenating(CGAffineTransform(translationX:-bounds.minX,y:-bounds.minY)).concatenating(CGAffineTransform(scaleX:scale,y:scale)),at:.zero)
        let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start:.zero,duration:range.duration); instruction.layerInstructions = [li]
        let vc = AVMutableVideoComposition(); vc.renderSize = size; vc.frameDuration = CMTime(value:1,timescale:30); vc.instructions = [instruction]
        let parent = CALayer(); parent.frame = CGRect(origin:.zero,size:size)
        let vl = CALayer(); vl.frame = parent.bounds
        let overlay = CALayer(); overlay.frame = parent.bounds
        overlay.contents = StampRenderer.overlay(size,stamp).cgImage
        parent.addSublayer(vl); parent.addSublayer(overlay)
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer:vl,in:parent)
        guard let ex = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else { throw error("无法创建视频导出任务") }
        let output = file(".mp4"); ex.outputURL = output; ex.outputFileType = .mp4; ex.videoComposition = vc; ex.shouldOptimizeForNetworkUse = true
        let monitor = Task { while !Task.isCancelled { progress(Double(ex.progress)); try? await Task.sleep(nanoseconds:200_000_000) } }
        defer { monitor.cancel() }
        do { try await finish(ex); progress(1); return output } catch { try? FileManager.default.removeItem(at:output); throw error }
    }
}
