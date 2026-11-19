import SwiftUI
import UIKit

struct Stamp: Codable, Equatable {
    var date = Date()
    var showDate = true, showTime = true
    var address = ""
    var top = "马克", main = "水印相机", badge = "真实时间"
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
@MainActor final class StampStore: ObservableObject {
    @Published var value: Stamp { didSet { save() } }
    init() {
        value = UserDefaults.standard.data(forKey:"moyu.stamp.v3")
            .flatMap { try? JSONDecoder().decode(Stamp.self,from:$0) } ?? Stamp()
    }
    func save() {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data,forKey:"moyu.stamp.v3") }
    }
}
enum StampRenderer {
    static func brandRect(_ size:CGSize,_ c:Stamp) -> CGRect {
        let u = min(size.width,size.height)/600, w = min(size.width,size.height)/600*106, h = min(size.width,size.height)/600*84
        return CGRect(x:c.x < 0 ? size.width-14*u-w : min(max(0,CGFloat(c.x)*size.width-w/2),size.width-w),
                      y:c.y < 0 ? size.height-14*u-h : min(max(0,CGFloat(c.y)*size.height-h/2),size.height-h),width:w,height:h)
    }
    static func overlay(_ size:CGSize,_ c:Stamp) -> UIImage {
        guard size.width > 0,size.height > 0 else { return UIImage() }
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size:size,format:f).image { _ in draw(size,c) }
    }
    static func photo(_ image:UIImage,_ c:Stamp) -> UIImage {
        let ratio = min(1,2560/max(image.size.width,image.size.height))
        let size = CGSize(width:max(1,floor(image.size.width*ratio)),height:max(1,floor(image.size.height*ratio)))
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true
        return UIGraphicsImageRenderer(size:size,format:f).image { _ in image.draw(in:CGRect(origin:.zero,size:size)); draw(size,c) }
    }
    private static func draw(_ size:CGSize,_ c:Stamp) {
        let u = min(size.width,size.height)/600, margin = min(size.width,size.height)/600*14
        let font = UIFont.boldSystemFont(ofSize:18*u*CGFloat(c.scale))
        let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 2*u; shadow.shadowOffset = CGSize(width:0,height:u)
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        let attrs:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:UIColor.white,.shadow:shadow,.paragraphStyle:p]
        var rows:[String] = []
        if !c.timeText.isEmpty { rows.append("时间："+c.timeText) }
        if !c.address.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { rows.append("地点："+c.address) }
        let width = max(1,size.width-(c.hasBrand ? 106*u+margin : 0)-2*margin)
        let heights = rows.map { min(font.lineHeight*3,ceil(($0 as NSString).boundingRect(with:CGSize(width:width,height:font.lineHeight*3),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs,context:nil).height)+5*u) }
        var y = size.height-margin-heights.reduce(0,+)
        for (i,row) in rows.enumerated() {
            (row as NSString).draw(with:CGRect(x:margin,y:y,width:width,height:heights[i]),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine],attributes:attrs,context:nil)
            y += heights[i]
        }
        guard c.hasBrand else { return }
        let b = brandRect(size,c)
        func line(_ text:String,_ y:CGFloat,_ height:CGFloat,_ point:CGFloat,_ color:UIColor = .white) {
            guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
            let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byTruncatingTail
            let font = UIFont.boldSystemFont(ofSize:point*u)
            let measured = (text as NSString).size(withAttributes:[.font:font]).width
            let fitted = UIFont.boldSystemFont(ofSize:max(8*u,font.pointSize*min(1,b.width/max(1,measured))))
            (text as NSString).draw(in:CGRect(x:b.minX,y:b.minY+y*u,width:b.width,height:height*u),
                withAttributes:[.font:fitted,.foregroundColor:color,.paragraphStyle:style,.shadow:shadow])
        }
        line(c.top.isEmpty ? "" : "··"+c.top+"··",1,24,18)
        line(c.main,25,25,19)
        if !c.badge.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            UIColor(white:0.93,alpha:0.8).setFill()
            UIBezierPath(roundedRect:CGRect(x:b.minX+7*u,y:b.minY+49*u,width:b.width-14*u,height:20*u),cornerRadius:3*u).fill()
            line(c.badge,50,20,13,.darkGray)
        }
        if c.custom { line("自定义",71,13,9) }
    }
}
