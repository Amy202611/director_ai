import SwiftUI
import AVFoundation
import UIKit

final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    enum Phase { case idle, preparing, recording, pausing, paused, merging }
    @Published var ready = false
    @Published var status = "正在准备相机"
    @Published var phase:Phase = .idle
    @Published var seconds = 0.0
    @Published var front = false
    @Published var taking = false
    @Published var photoID:UUID?
    @Published var movieURL:URL?
    var image:UIImage?
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"moyu.camera")
    private let photos = AVCapturePhotoOutput()
    private let movies = AVCaptureMovieFileOutput()
    private var input:AVCaptureDeviceInput?
    private var audioInput:AVCaptureDeviceInput?
    private var configured = false
    private var clips:[URL] = []
    private var total = 0.0
    private var wantsFinish = false
    private var stopSession = false
    private var timer:Timer?
    private func ui(_ f:@escaping()->Void) { DispatchQueue.main.async(execute:f) }
    func start() {
        if NSClassFromString("XCTestCase") != nil { return }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: prepare()
        case .notDetermined: AVCaptureDevice.requestAccess(for:.video) { granted in
            if granted { self.prepare() } else { self.ui { self.status = "请在系统设置中允许使用相机。" } }
        }
        default: status = "请在系统设置中允许使用相机，也可从相册导入。"
        }
    }
    private func prepare() {
        queue.async {
            do {
                self.stopSession = false
                if !self.configured {
                    self.session.beginConfiguration()
                    do {
                        self.session.sessionPreset = .high
                        guard let d = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw Media.error("没有可用相机") }
                        let input = try AVCaptureDeviceInput(device:d)
                        guard self.session.canAddInput(input),self.session.canAddOutput(self.photos),self.session.canAddOutput(self.movies) else { throw Media.error("无法配置相机") }
                        self.session.addInput(input); self.input = input
                        self.session.addOutput(self.photos); self.session.addOutput(self.movies)
                        self.photos.maxPhotoQualityPrioritization = .quality
                        self.configured = true
                        self.session.commitConfiguration()
                    } catch { self.session.commitConfiguration(); throw error }
                }
                if !self.session.isRunning { self.session.startRunning() }
                self.ui { self.ready = true; self.status = "" }
            } catch { self.ui { self.ready = false; self.status = error.localizedDescription } }
        }
    }
    private func orient(_ c:AVCaptureConnection?) {
        guard let c else { return }
        if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = input?.device.position == .front }
    }
    func takePhoto() {
        guard phase == .idle,!taking else { return }; taking = true
        queue.async {
            guard self.configured,self.session.isRunning else { self.ui { self.taking = false; self.status = "相机尚未就绪" }; return }
            self.orient(self.photos.connection(with:.video))
            let p = AVCapturePhotoSettings(); p.photoQualityPrioritization = .quality
            self.photos.capturePhoto(with:p,delegate:self)
        }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        let image = photo.fileDataRepresentation().flatMap { Media.decode($0) }
        ui {
            self.taking = false
            if let image { self.image = image; self.photoID = UUID() }
            else { self.status = error?.localizedDescription ?? "照片读取失败" }
        }
    }
    func flip() {
        guard phase == .idle,!taking else { return }
        queue.async {
            guard let old = self.input else { return }
            do {
                guard let d = AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:old.device.position == .back ? .front : .back) else { return }
                let replacement = try AVCaptureDeviceInput(device:d)
                self.session.beginConfiguration(); self.session.removeInput(old)
                if self.session.canAddInput(replacement) { self.session.addInput(replacement); self.input = replacement }
                else { self.session.addInput(old) }
                self.session.commitConfiguration()
                self.ui { self.front = self.input?.device.position == .front }
            } catch { self.ui { self.status = error.localizedDescription } }
        }
    }
    func begin(audio:Bool) {
        guard phase == .idle else { return }; phase = .preparing; seconds = 0
        if audio && AVCaptureDevice.authorizationStatus(for:.audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for:.audio) { granted in self.prepare(); self.firstClip(audio:granted) }
        } else { firstClip(audio:audio && AVCaptureDevice.authorizationStatus(for:.audio) == .authorized) }
    }
    private func firstClip(audio:Bool) {
        queue.async {
            self.clips = []; self.total = 0
            self.session.beginConfiguration()
            if let old = self.audioInput { self.session.removeInput(old); self.audioInput = nil }
            if audio,let d = AVCaptureDevice.default(for:.audio),let a = try? AVCaptureDeviceInput(device:d),self.session.canAddInput(a) {
                self.session.addInput(a); self.audioInput = a
            }
            self.session.commitConfiguration(); self.recordClip()
        }
    }
    private func recordClip() {
        guard configured,session.isRunning else { ui { self.phase = .idle; self.status = "相机尚未就绪，请重试" }; return }
        orient(movies.connection(with:.video)); wantsFinish = false
        if let c = movies.connection(with:.video),movies.availableVideoCodecTypes.contains(.h264) { movies.setOutputSettings([AVVideoCodecKey:AVVideoCodecType.h264],for:c) }
        movies.startRecording(to:Media.file(".mov"),recordingDelegate:self)
    }
    func pause() {
        guard phase == .recording else { return }; phase = .pausing
        queue.async { self.wantsFinish = false; self.movies.stopRecording() }
    }
    func resume() {
        guard phase == .paused else { return }; phase = .preparing
        queue.async { if !self.session.isRunning { self.session.startRunning() }; self.recordClip() }
    }
    func finish() {
        guard phase == .recording || phase == .paused else { return }
        let paused = phase == .paused; phase = .merging
        queue.async { if paused { self.merge() } else { self.wantsFinish = true; self.movies.stopRecording() } }
    }
    func fileOutput(_ output:AVCaptureFileOutput,didStartRecordingTo fileURL:URL,from connections:[AVCaptureConnection]) {
        let base = total
        ui {
            self.phase = .recording; self.timer?.invalidate()
            let start = ProcessInfo.processInfo.systemUptime
            self.timer = Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in self?.seconds = base+ProcessInfo.processInfo.systemUptime-start }
        }
    }
    func fileOutput(_ output:AVCaptureFileOutput,didFinishRecordingTo url:URL,from connections:[AVCaptureConnection],error:Error?) {
        ui { self.timer?.invalidate() }
        queue.async {
            let ok = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            if ok {
                self.clips.append(url)
                let duration = CMTimeGetSeconds(AVURLAsset(url:url).duration)
                if duration.isFinite { self.total += duration }
            }
            if self.stopSession && self.session.isRunning { self.session.stopRunning() }
            if self.wantsFinish && ok { self.merge() }
            else {
                let total = self.total, empty = self.clips.isEmpty
                self.ui { self.seconds = total; self.phase = empty ? .idle : .paused; if !ok { self.status = error?.localizedDescription ?? "录像失败" } }
            }
        }
    }
    private func merge() {
        let urls = clips; ui { self.phase = .merging }
        Task {
            do {
                let output = try await Media.merge(urls)
                for url in urls { try? FileManager.default.removeItem(at:url) }
                self.queue.async { self.clips = []; self.total = 0 }
                self.ui { self.movieURL = output; self.phase = .idle; self.seconds = 0 }
            } catch { self.ui { self.phase = .paused; self.status = error.localizedDescription } }
        }
    }
    func suspend() {
        queue.async {
            if self.movies.isRecording { self.stopSession = true; self.wantsFinish = false; self.movies.stopRecording(); self.ui { self.phase = .pausing } }
            else if self.session.isRunning { self.session.stopRunning() }
            self.ui { self.ready = false }
        }
    }
}
struct CameraPreview:UIViewRepresentable {
    @ObservedObject var camera:Camera
    final class Surface:UIView {
        override class var layerClass:AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview:AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let c = preview.connection,c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        }
    }
    func makeUIView(context:Context)->Surface {
        let view = Surface(); view.preview.session = camera.session; view.preview.videoGravity = .resizeAspect; return view
    }
    func updateUIView(_ view:Surface,context:Context) {
        if let c = view.preview.connection,c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = camera.front }
    }
}
