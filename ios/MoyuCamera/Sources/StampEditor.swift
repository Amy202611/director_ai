import SwiftUI
import AVKit
import UIKit

@MainActor struct StampOverlay:View {
    @ObservedObject var store:StampStore
    var interactive = true
    @State private var origin:CGPoint?
    var body:some View {
        GeometryReader { geo in
            let size = geo.size, rect = StampRenderer.brandRect(geo.size,store.value)
            ZStack(alignment:.topLeading) {
                Image(uiImage:StampRenderer.overlay(size,store.value)).resizable()
                    .frame(width:size.width,height:size.height).allowsHitTesting(false)
                if store.value.hasBrand && interactive {
                    Rectangle().fill(Color.white.opacity(0.001))
                        .frame(width:rect.width+12,height:rect.height+12).position(x:rect.midX,y:rect.midY)
                        .gesture(DragGesture(coordinateSpace:.named("stamp"))
                            .onChanged { value in
                                if origin == nil { origin = CGPoint(x:rect.midX,y:rect.midY) }
                                guard let origin,size.width>0,size.height>0 else { return }
                                store.value.x = Double(min(max(rect.width/2,origin.x+value.translation.width),size.width-rect.width/2)/size.width)
                                store.value.y = Double(min(max(rect.height/2,origin.y+value.translation.height),size.height-rect.height/2)/size.height)
                            }.onEnded { _ in origin = nil })
                }
            }.coordinateSpace(name:"stamp")
        }
    }
}
@MainActor struct StampEditor:View {
    @ObservedObject var store:StampStore
    @ObservedObject var locator:Locator
    var locate:()->Void
    @State private var calendar = false
    @State private var clock = false
    @State private var saved = false
    @State private var draft = Date()
    private func field(_ key:WritableKeyPath<Stamp,String>)->Binding<String> {
        Binding(get:{store.value[keyPath:key]},set:{store.value[keyPath:key] = $0})
    }
    var body:some View {
        VStack(spacing:14) {
            card {
                Label("日期与时间",systemImage:"calendar").font(.headline)
                Button { draft = store.value.date; calendar = true } label: {
                    HStack { Text("选择日期"); Spacer(); Text(store.value.date,format:.dateTime.year().month().day()); Image(systemName:"calendar") }
                }.padding(10).background(Color.teal.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                Button { draft = store.value.date; clock = true } label: {
                    HStack { Text("选择时间"); Spacer(); Text(store.value.date,format:.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits)); Image(systemName:"clock") }
                }.padding(10).background(Color.teal.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                HStack {
                    Toggle("显示日期",isOn:$store.value.showDate)
                    Toggle("显示时间",isOn:$store.value.showTime)
                }.font(.footnote)
                Button("使用当前日期与时间") { store.value.date = Date(); store.value.showDate = true; store.value.showTime = true }.font(.footnote)
                Text("星期自动计算；关闭日期或时间后，相应内容不显示。").font(.caption).foregroundStyle(.secondary)
            }
            card {
                Label("地点 / 地址",systemImage:"mappin.and.ellipse").font(.headline)
                TextField("输入地址，留空不显示",text:field(\.address),axis:.vertical).textFieldStyle(.roundedBorder)
                HStack {
                    Button(action:locate) { Label("获取当前地址",systemImage:"location.fill") }.disabled(locator.busy)
                    Spacer()
                    if locator.busy { ProgressView(); Button("取消",action:locator.cancel) }
                }
                Text(locator.status).font(.caption).foregroundStyle(.secondary)
            }
            card {
                Label("水印标识",systemImage:"textformat").font(.headline)
                TextField("第一行",text:field(\.top)).textFieldStyle(.roundedBorder)
                TextField("第二行",text:field(\.main)).textFieldStyle(.roundedBorder)
                TextField("标签",text:field(\.badge)).textFieldStyle(.roundedBorder)
                TextField("手机型号（可留空）",text:field(\.device)).textFieldStyle(.roundedBorder)
                TextField("其他说明（可留空）",text:field(\.note),axis:.vertical).textFieldStyle(.roundedBorder)
                Text("拖动预览中的标识调整位置，文字留空自动隐藏。").font(.caption).foregroundStyle(.secondary)
                Button("回到右下角") { store.value.x = -1; store.value.y = -1 }.font(.footnote)
                Toggle("显示自定义说明",isOn:$store.value.custom).font(.subheadline)
                HStack { Text("文字大小").font(.footnote); Slider(value:$store.value.scale,in:0.8...1.3) }
                HStack {
                    Button("保存模板") { store.save(); saved = true }
                    Spacer()
                    Button("恢复默认",role:.destructive) { store.value = Stamp() }
                }.font(.footnote)
                Text("编辑自动保存；导出时使用当前预览设置。").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .alert("模板已保存",isPresented:$saved) { Button("知道了",role:.cancel) {} }
        .sheet(isPresented:$calendar) {
            NavigationStack {
                DatePicker("日期",selection:$draft,displayedComponents:.date).datePickerStyle(.graphical)
                    .padding().environment(\.locale,Locale(identifier:"zh_CN"))
                    .navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement:.cancellationAction) { Button("取消") { calendar = false } }
                        ToolbarItem(placement:.confirmationAction) { Button("完成") { applyDate(); calendar = false } }
                    }
            }.presentationDetents([.medium,.large])
        }
        .sheet(isPresented:$clock) {
            NavigationStack {
                VStack(spacing:20) {
                    DatePicker("时间",selection:$draft,displayedComponents:.hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().environment(\.locale,Locale(identifier:"zh_CN"))
                    Text("24小时制 · 上下滑动选择时分").font(.footnote).foregroundStyle(.secondary)
                }.padding().navigationTitle("选择时间").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement:.cancellationAction) { Button("取消") { clock = false } }
                        ToolbarItem(placement:.confirmationAction) { Button("完成") { applyTime(); clock = false } }
                    }
            }.presentationDetents([.medium])
        }
    }
    private func applyDate() {
        let c = Calendar(identifier:.gregorian)
        var p = c.dateComponents([.year,.month,.day],from:draft)
        let old = c.dateComponents([.hour,.minute],from:store.value.date)
        p.hour = old.hour; p.minute = old.minute
        if let date = c.date(from:p) { store.value.date = date; store.value.showDate = true }
    }
    private func applyTime() {
        let c = Calendar(identifier:.gregorian)
        var p = c.dateComponents([.year,.month,.day],from:store.value.date)
        let time = c.dateComponents([.hour,.minute],from:draft)
        p.hour = time.hour; p.minute = time.minute
        if let date = c.date(from:p) { store.value.date = date; store.value.showTime = true }
    }
    private func card<C:View>(@ViewBuilder content:()->C)->some View {
        VStack(alignment:.leading,spacing:12,content:content).padding(16).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}
