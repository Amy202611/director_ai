import SwiftUI
import UIKit

struct Stamp: Codable, Equatable {
    var date = Date()
    var showDate = true, showTime = true
    var address = ""
    var device = "", note = ""
    var top = "马克", main = "水印相机", badge = "真实时间"
    var serial: String?
    var serialText: String { serial.map { "防伪 " + $0 } ?? "" }
    var custom = false
    var scale = 1.0, x = -1.0, y = -1.0
    var hasBrand: Bool { [top,main,badge].contains { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } }
    var timeText: String {
        guard showDate || showTime else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier:"zh_CN"); f.calendar = Calendar(identifier:.gregorian)
        f.dateFormat = showDate ? (showTime ? "yyyy年M月d日 EEEE HH:mm" : "yyyy年M月d日 EEEE") : "HH:mm"
        return f.string(from:date)
    }
}
enum StampSerial {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<15).map { _ in alphabet.randomElement(using:&generator)! })
    }
}
@MainActor final class StampStore: ObservableObject {
    @Published var value: Stamp { didSet { save() } }
    @Published private(set) var mediaSerial = StampSerial.make()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var template = defaults.data(forKey:"moyu.stamp.v3")
            .flatMap { try? JSONDecoder().decode(Stamp.self,from:$0) } ?? Stamp()
        template.serial = nil
        value = template
    }
    func beginMedia() { mediaSerial = StampSerial.make() }
    func snapshot() -> Stamp { var stamp = value; stamp.serial = mediaSerial; return stamp }
    func save() {
        var template = value; template.serial = nil
        if let data = try? JSONEncoder().encode(template) { defaults.set(data,forKey:"moyu.stamp.v3") }
    }
}
enum StampRenderer {
    static func brandRect(_ size:CGSize,_ c:Stamp) -> CGRect {
        let u = min(size.width,size.height)/600, w = min(size.width,size.height)/600*106, h = min(size.width,size.height)/600*84
        let reserved: CGFloat = c.serialText.isEmpty ? 0 : 19*u
        return CGRect(x:c.x < 0 ? size.width-14*u-w : min(max(0,CGFloat(c.x)*size.width-w/2),size.width-w),
                      y:c.y < 0 ? size.height-14*u-h-reserved : min(max(0,CGFloat(c.y)*size.height-h/2),max(0,size.height-h-reserved)),width:w,height:h)
    }
    static func overlay(_ size:CGSize,_ c:Stamp, rasterScale:CGFloat = 1) -> UIImage {
        guard size.width > 0,size.height > 0 else { return UIImage() }
        let f = UIGraphicsImageRendererFormat(); f.scale = max(1,rasterScale)
        return UIGraphicsImageRenderer(size:size,format:f).image { _ in draw(size,c) }
    }
    static func photo(_ image:UIImage,_ c:Stamp) -> UIImage {
        let pixels = CGSize(width:image.size.width*image.scale,height:image.size.height*image.scale)
        let ratio = min(1,4096/max(pixels.width,pixels.height))
        let size = CGSize(width:max(1,floor(pixels.width*ratio)),height:max(1,floor(pixels.height*ratio)))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size:size,format:f).image { _ in image.draw(in:CGRect(origin:.zero,size:size)); draw(size,c) }
    }
    struct TextRow {
        var text: String
        var rect: CGRect
    }
    static func detailRows(_ size: CGSize, _ c: Stamp) -> [TextRow] {
        let u = min(size.width,size.height)/600, margin = 14*u
        let font = UIFont.systemFont(ofSize:18*u*CGFloat(c.scale),weight:.semibold)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key:Any] = [.font:font,.paragraphStyle:p]
        var text: [String] = []
        if !c.timeText.isEmpty { text.append("时间："+c.timeText) }
        if !c.address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { text.append("地点："+c.address) }
        if !c.device.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { text.append("机型："+c.device) }
        if !c.note.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { text.append(c.note) }
        let width = max(1,size.width-(c.hasBrand ? 106*u+margin : 0)-2*margin)
        let heights = text.map { ceil(($0 as NSString).boundingRect(with:CGSize(width:width,height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs,context:nil).height)+5*u }
        let serialGap: CGFloat = c.serialText.isEmpty ? 0 : 19*u
        var y = size.height-margin-serialGap-heights.reduce(0,+)
        return text.enumerated().map { i,row in
            let result = TextRow(text:row,rect:CGRect(x:margin,y:y,width:width,height:heights[i]))
            y += heights[i]; return result
        }
    }
    private static func draw(_ size:CGSize,_ c:Stamp) {
        let u = min(size.width,size.height)/600, margin = 14*u
        let font = UIFont.systemFont(ofSize:18*u*CGFloat(c.scale),weight:.semibold)
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 0.45*u; shadow.shadowOffset = CGSize(width:0,height:0.6*u)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        let attrs:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor.white,.shadow:shadow,.paragraphStyle:p,.strokeColor:UIColor.black.withAlphaComponent(0.6),.strokeWidth: -1.4]
        for row in detailRows(size,c) {
            (row.text as NSString).draw(with:row.rect,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs,context:nil)
        }
        if !c.serialText.isEmpty {
            let style = NSMutableParagraphStyle(); style.alignment = .right
            let serialFont = UIFont.monospacedSystemFont(ofSize:11.5*u,weight:.medium)
            (c.serialText as NSString).draw(in:CGRect(x:margin,y:size.height-margin-serialFont.lineHeight,width:size.width-2*margin,height:serialFont.lineHeight+u),
                withAttributes:[.font:serialFont,.foregroundColor:UIColor.white,.shadow:shadow,.paragraphStyle:style,.strokeColor:UIColor.black.withAlphaComponent(0.6),.strokeWidth: -1.2])
        }
        guard c.hasBrand else { return }
        let b = brandRect(size,c)
        func brandAttributes(_ font:UIFont,_ color:UIColor,_ style:NSParagraphStyle) -> [NSAttributedString.Key:Any] {
            var values: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color,.paragraphStyle:style]
            if color.isEqual(UIColor.white) { values[.shadow] = shadow; values[.strokeColor] = UIColor.black.withAlphaComponent(0.6); values[.strokeWidth] = -1.2 }
            return values
        }
        func line(_ text:String,_ y:CGFloat,_ height:CGFloat,_ point:CGFloat,_ color:UIColor = .white) {
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
            let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
            let font = UIFont.boldSystemFont(ofSize:point*u)
            let measured = (text as NSString).size(withAttributes:[.font:font]).width
            let fitted = UIFont.boldSystemFont(ofSize:max(8*u,font.pointSize*min(1,b.width/max(1,measured))))
            (text as NSString).draw(in:CGRect(x:b.minX,y:b.minY+y*u,width:b.width,height:height*u),
                withAttributes:brandAttributes(fitted,color,style))
        }
        line(c.top.isEmpty ? "" : "·· "+c.top+" ··",1,24,18)
        line(c.main,25,25,19)
        if !c.badge.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            UIColor(white:1,alpha:0.96).setFill()
            UIBezierPath(roundedRect:CGRect(x:b.minX+7*u,y:b.minY+49*u,width:b.width-14*u,height:20*u),cornerRadius:3*u).fill()
            line(c.badge,50,20,13,.darkGray)
        }
        if c.custom { line("自定义",71,13,9) }
    }
}
