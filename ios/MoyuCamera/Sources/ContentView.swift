import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    enum Appearance: String, CaseIterable, Identifiable {
        case camera = "沉浸拍摄", light = "简约编辑", studio = "专业工作台"
        var id: String { rawValue }
    }
    @State private var mode = Appearance.light
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var timestamp = Date()
    @State private var address = ""
    @State private var showsWatermark = true
    @State private var importError: String?

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        return formatter.string(from: timestamp)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    VStack(alignment: .leading, spacing: 16) {
                        Label("日期与时间", systemImage: "calendar").font(.headline)
                        DatePicker("选择日期", selection: $timestamp, displayedComponents: .date)
                        DatePicker("选择时间", selection: $timestamp, displayedComponents: .hourAndMinute)
                        Button("填入当前日期与时间") { timestamp = Date() }
                            .buttonStyle(.bordered)
                        Divider()
                        Label("地点 / 地址", systemImage: "mappin.and.ellipse").font(.headline)
                        TextField("手动输入地址，留空不显示", text: $address)
                            .textFieldStyle(.roundedBorder)
                        Toggle("显示水印", isOn: $showsWatermark)
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("从相册选择照片", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("SwiftUI 原生基础工程 · 本地照片与水印预览\n拍照、GPS、视频导出尚未移植。")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .navigationTitle("摸鱼相机")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("界面模式", selection: $mode) {
                            ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Label("切换模式", systemImage: "slider.horizontal.3") }
                }
            }
            .tint(mode == .studio ? .orange : .teal)
            .preferredColorScheme(mode == .light ? .light : .dark)
            .task(id: selectedPhoto) { await importPhoto() }
            .alert("照片读取失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("知道了", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "") }
        }
    }

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [.teal.opacity(0.65), .indigo.opacity(0.8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: mode == .camera ? 390 : 270).clipped()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.aperture").font(.system(size: 64, weight: .light))
                    Text("选择照片，实时预览水印").font(.subheadline)
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if showsWatermark {
                VStack(alignment: .leading, spacing: 7) {
                    Text("时间：\(formattedDate)")
                    if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("地点：\(address)")
                    }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .frame(height: mode == .camera ? 390 : 270)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityLabel("照片和水印实时预览")
    }

    @MainActor private func importPhoto() async {
        guard let selectedPhoto else { return }
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self),
                  let decoded = UIImage(data: data) else {
                importError = "无法读取该照片，请选择另一张。"
                return
            }
            if !Task.isCancelled { image = decoded }
        } catch {
            if !Task.isCancelled { importError = error.localizedDescription }
        }
    }
}
