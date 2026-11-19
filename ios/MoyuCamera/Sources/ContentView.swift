import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit
import UIKit

struct ImportedMovie:Transferable {
    let url:URL
    static var transferRepresentation:some TransferRepresentation {
        FileRepresentation(contentType:.movie) { item in SentTransferredFile(item.url) } importing: { item in
            let output = Media.file("."+((item.file.pathExtension.isEmpty) ? "mov" : item.file.pathExtension))
            try FileManager.default.copyItem(at:item.file,to:output)
            return ImportedMovie(url:output)
        }
    }
}
@MainActor struct ContentView:View {
    @StateObject private var store = StampStore()
    @StateObject private var camera = Camera()
    @StateObject private var locator = Locator()
    @Environment(\.scenePhase) private var scene
    @AppStorage("moyu.interface.v3") private var mode = 1
    @State private var image:UIImage?
    @State private var video:URL?
    @State private var videoSize = CGSize(width:9,height:16)
    @State private var player:AVPlayer?
    @State private var selection:PhotosPickerItem?
    @State private var videoMode = false
    @State private var microphone = true
    @State private var keepAudio = true
    @State private var resolution = 1920
    @State private var editing = false
    @State private var previewing = false
    @State private var importing = false
    @State private var exporting = false
    @State private var outputImage:UIImage?
    @State private var outputVideo:URL?
    @State private var progress = 0.0
    @State private var exportTask:Task<Void,Never>?
    @State private var message:String?
    @State private var oldAddress = ""
    private let modes = ["沉浸拍摄","简约编辑","专业工作台"]
    private var hasMedia:Bool { image != nil || video != nil }
    private var busyRecording:Bool { camera.phase != .idle }
    private var tint:Color { mode == 2 ? .orange : .teal }
    var body:some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing:10) {
                    stage.frame(height:mode == 0 && !hasMedia ? max(220,geo.size.height*0.6) : max(150,min(280,geo.size.height*0.38)))
                    if !hasMedia && !camera.status.isEmpty { Text(camera.status).font(.caption).foregroundStyle(.secondary) }
                    if mode == 0 && !hasMedia {
                        HStack {
                            Button(action:locate) { Label("GPS定位",systemImage:"location.fill") }
                            Spacer()
                            Button("编辑水印") { editing = true }.disabled(busyRecording)
                            Spacer()
                            Button(action:camera.flip) { Image(systemName:"arrow.triangle.2.circlepath.camera") }.disabled(busyRecording)
                        }.font(.footnote)
                        Spacer(minLength:0)
                        controls
                    } else {
                        ScrollView {
                            StampEditor(store:store,locator:locator,locate:locate)
                            if video != nil { videoOptions.padding(.top,14) }
                        }.scrollDismissesKeyboard(.interactively)
                        if !hasMedia { controls }
                    }
                    if hasMedia {
                        HStack {
                            Button("重新拍摄",action:reset).buttonStyle(.bordered)
                            Button(action:export) {
                                Label(video == nil ? "预览并保存照片" : "预览并导出视频",systemImage:"square.and.arrow.down").frame(maxWidth:.infinity)
                            }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(.horizontal,14).padding(.bottom,8)
                    .disabled(importing || exporting)
                    .overlay { if importing || exporting { progressView } }
            }
            .navigationTitle("摸鱼相机").navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .tint(tint).preferredColorScheme(mode == 1 ? .light : .dark)
            .task { camera.start() }
            .task(id:selection) { await importMedia() }
            .onChange(of:camera.photoID) { _ in
                if let captured = camera.image { store.beginMedia(); image = captured; video = nil; player?.pause(); player = nil; camera.suspend() }
            }
            .onChange(of:camera.movieURL) { url in if let url { Task { await selectVideo(url) } } }
            .onChange(of:locator.resultID) { _ in
                if let found = locator.address {
                    if store.value.address == oldAddress { store.value.address = found }
                    else { locator.status = "已保留手动地址；定位结果："+found }
                }
            }
            .onChange(of:scene) { phase in
                if phase == .active && !hasMedia { camera.start() }
                else if phase == .background { camera.suspend(); locator.cancel(); player?.pause() }
            }
            .sheet(isPresented:$editing) {
                NavigationStack {
                    ScrollView { StampEditor(store:store,locator:locator,locate:locate).padding() }
                        .navigationTitle("编辑水印").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { editing = false } } }
                }.presentationDetents([.medium,.large])
            }
            .sheet(isPresented:$previewing) { SavePreview(image:outputImage,video:outputVideo) }
            .alert("提示",isPresented:Binding(get:{message != nil},set:{if !$0 { message = nil }})) {
                Button("知道了",role:.cancel) { message = nil }
                Button("系统权限设置") { if let url = URL(string:UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            } message: { Text(message ?? "") }
        }
    }
    private var stage:some View {
        GeometryReader { geo in
            let aspect = image?.size ?? (video != nil ? videoSize : (videoMode ? CGSize(width:9,height:16) : CGSize(width:3,height:4)))
            let rect = AVMakeRect(aspectRatio:aspect,insideRect:CGRect(origin:.zero,size:geo.size))
            ZStack(alignment:.top) {
                Color.black
                ZStack {
                    if let image { Image(uiImage:image).resizable().scaledToFit() }
                    else if let player,video != nil { VideoPlayer(player:player) }
                    else { CameraPreview(camera:camera) }
                    StampOverlay(store:store,interactive:!busyRecording)
                }.frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                if busyRecording {
                    HStack {
                        Image(systemName:camera.phase == .paused ? "pause.fill" : "record.circle.fill").foregroundStyle(.red)
                        Text(duration(camera.seconds)).monospacedDigit()
                        Text(phaseText).font(.caption)
                    }.foregroundStyle(.white).padding(8).background(.black.opacity(0.7),in:Capsule()).padding(8)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius:18))
    }
    @ToolbarContentBuilder private var toolbar:some ToolbarContent {
        ToolbarItem(placement:.navigationBarLeading) {
            PhotosPicker(selection:$selection,matching:.any(of:[.images,.videos])) { Label("相册",systemImage:"photo.on.rectangle") }
                .disabled(busyRecording || importing || exporting)
        }
        ToolbarItem(placement:.navigationBarTrailing) {
            Menu {
                Picker("界面模式",selection:$mode) { ForEach(0..<3,id:\.self) { Text(modes[$0]).tag($0) } }
            } label: { Label("切换模式",systemImage:"slider.horizontal.3") }.disabled(busyRecording || exporting)
        }
    }
    private var controls:some View {
        VStack(spacing:10) {
            Picker("拍摄模式",selection:$videoMode) { Text("拍照").tag(false); Text("录像").tag(true) }
                .pickerStyle(.segmented).disabled(busyRecording || camera.taking)
            if videoMode {
                HStack {
                    Toggle("录制原声",isOn:$microphone).font(.footnote).disabled(busyRecording)
                    Spacer()
                    Button(action:camera.flip) { Image(systemName:"arrow.triangle.2.circlepath.camera") }.disabled(busyRecording)
                }
                HStack(spacing:22) {
                    if camera.phase == .idle {
                        recordButton("开始录像","record.circle.fill",.red) { camera.begin(audio:microphone) }.disabled(!camera.ready)
                    } else if camera.phase == .recording {
                        recordButton("暂停","pause.circle.fill",.orange,action:camera.pause)
                        recordButton("结束录像","stop.circle.fill",.red,action:camera.finish)
                    } else if camera.phase == .paused {
                        recordButton("继续录像","play.circle.fill",.teal,action:camera.resume)
                        recordButton("结束录像","stop.circle.fill",.red,action:camera.finish)
                    } else { ProgressView(); Text(phaseText).font(.footnote) }
                }
                Text("暂停不计入视频时长；结束后可编辑整段视频的水印。").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button(action:camera.flip) { Image(systemName:"arrow.triangle.2.circlepath.camera").font(.title2) }.disabled(camera.taking)
                    Spacer()
                    Button(action:camera.takePhoto) {
                        ZStack { Circle().stroke(tint,lineWidth:3).frame(width:66,height:66); Circle().fill(tint).frame(width:53,height:53) }
                    }.disabled(!camera.ready || camera.taking)
                    Spacer()
                    Button { editing = true } label: { Image(systemName:"slider.horizontal.3").font(.title2) }
                }.padding(.horizontal,28)
                if camera.taking { ProgressView("正在拍照") }
            }
        }
    }
    private func recordButton(_ title:String,_ icon:String,_ color:Color,action:@escaping()->Void)->some View {
        Button(action:action) { VStack(spacing:4) { Image(systemName:icon).font(.system(size:46)); Text(title).font(.caption.bold()) } }.tint(color)
    }
    private var videoOptions:some View {
        VStack(alignment:.leading,spacing:12) {
            Label("视频导出",systemImage:"film").font(.headline)
            Picker("分辨率",selection:$resolution) { Text("720p").tag(1280); Text("1080p").tag(1920) }.pickerStyle(.segmented)
            Toggle("保留原声",isOn:$keepAudio)
            Text("MP4 · 整段使用当前水印 · 不覆盖原视频").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
    private var phaseText:String {
        switch camera.phase {
        case .idle:return "准备录像"
        case .preparing:return "正在准备"
        case .recording:return "正在录像"
        case .pausing:return "正在暂停"
        case .paused:return "录像已暂停"
        case .merging:return "合并录像片段"
        }
    }
    private func duration(_ value:Double)->String {
        let seconds = Int(value.isFinite ? max(0,value) : 0); return String(format:"%02d:%02d",seconds/60,seconds%60)
    }
    private var progressView:some View {
        VStack(spacing:12) {
            if exporting { ProgressView(value:progress); Text("\(Int(progress*100))%"); Text("正在合成视频水印"); Button("取消导出",role:.cancel) { exportTask?.cancel() } }
            else { ProgressView(); Text("正在读取素材") }
        }.padding(24).frame(width:250).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
    private func locate() { oldAddress = store.value.address; locator.request() }
    private func reset() {
        player?.pause(); player = nil; image = nil; video = nil; outputImage = nil; outputVideo = nil; camera.start()
    }
    private func importMedia() async {
        guard let selection else { return }
        importing = true; camera.suspend(); defer { importing = false }
        do {
            if selection.supportedContentTypes.contains(where:{$0.conforms(to:.movie)}) {
                guard let movie = try await selection.loadTransferable(type:ImportedMovie.self) else { throw Media.error("视频读取失败") }
                guard !Task.isCancelled else { return }; await selectVideo(movie.url)
            } else {
                guard let data = try await selection.loadTransferable(type:Data.self),let result = Media.decode(data) else { throw Media.error("照片读取失败") }
                guard !Task.isCancelled else { return }; store.beginMedia(); player?.pause(); player = nil; video = nil; image = result
            }
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
        if !hasMedia { camera.start() }
    }
    private func selectVideo(_ url:URL) async {
        importing = true; camera.suspend(); defer { importing = false }
        do {
            let asset = AVURLAsset(url:url)
            guard let track = try await asset.loadTracks(withMediaType:.video).first else { throw Media.error("视频没有画面") }
            let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
            let bounds = CGRect(origin:.zero,size:size).applying(transform)
            videoSize = CGSize(width:abs(bounds.width),height:abs(bounds.height))
            store.beginMedia(); player?.pause(); image = nil; video = url; player = AVPlayer(url:url)
        } catch { message = error.localizedDescription }
    }
    private func export() {
        let stamp = store.snapshot()
        if let image { outputImage = StampRenderer.photo(image,stamp); outputVideo = nil; previewing = true }
        else if let video {
            player?.pause(); progress = 0; exporting = true
            let limit = CGFloat(resolution), audio = keepAudio
            exportTask = Task {
                do {
                    let output = try await Media.export(video,stamp:stamp,limit:limit,keepAudio:audio) { value in Task { @MainActor in progress = value } }
                    try Task.checkCancellation(); outputVideo = output; outputImage = nil; previewing = true
                } catch { message = Task.isCancelled ? "已取消导出，原视频保留。" : error.localizedDescription }
                exporting = false
            }
        }
    }
}
@MainActor struct SavePreview:View {
    let image:UIImage?
    let video:URL?
    @Environment(\.dismiss) private var dismiss
    @State private var player:AVPlayer?
    @State private var saving = false
    @State private var message:String?
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(spacing:20) {
                    if let image { Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:16)) }
                    if let player { VideoPlayer(player:player).frame(height:380).clipShape(RoundedRectangle(cornerRadius:16)) }
                    Label("水印已合成到画面",systemImage:"checkmark.circle.fill")
                    Button {
                        saving = true
                        Task {
                            do { try await Media.save(image:image,video:video); message = "已保存到系统相册。" }
                            catch { message = error.localizedDescription }
                            saving = false
                        }
                    } label: { Label(saving ? "正在保存…" : "保存到系统相册",systemImage:"square.and.arrow.down").frame(maxWidth:.infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(saving)
                    Button("返回继续编辑") { dismiss() }.buttonStyle(.bordered).disabled(saving)
                }.padding()
            }.navigationTitle(video == nil ? "保存水印照片" : "保存水印视频").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("关闭") { dismiss() }.disabled(saving) } }
                .onAppear { if let video,player == nil { player = AVPlayer(url:video) } }
                .onDisappear { player?.pause() }
                .interactiveDismissDisabled(saving)
                .alert("保存结果",isPresented:Binding(get:{message != nil},set:{if !$0 {message = nil}})) { Button("知道了",role:.cancel) { message = nil } } message: { Text(message ?? "") }
        }
    }
}
