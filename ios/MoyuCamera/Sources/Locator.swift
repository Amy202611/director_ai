import Foundation
import CoreLocation
import Combine

final class Locator:NSObject,ObservableObject,CLLocationManagerDelegate {
    @Published var status = "点击定位获取当前地址，也可直接填写。"
    @Published var address:String?
    @Published var resultID:UUID?
    @Published var busy = false
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timeout:DispatchWorkItem?
    private var generation = 0
    private var started = Date.distantPast
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func request() {
        cancel(); busy = true; started = Date()
        guard CLLocationManager.locationServicesEnabled() else { complete("系统定位未开启，可手动填写地址。"); return }
        switch manager.authorizationStatus {
        case .notDetermined: status = "请允许使用期间访问位置"; manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse,.authorizedAlways: start()
        default: complete("定位权限未开启，可在系统设置开启或手动填写。")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        guard busy else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,.authorizedAlways: start()
        case .denied,.restricted: complete("未授权定位，可手动填写地址。")
        default: break
        }
    }
    private func start() {
        manager.startUpdatingLocation(); status = "正在获取当前位置…"
        schedule(30,message:"定位超时，可重试或手动填写。")
    }
    private func schedule(_ seconds:Double,message:String) {
        timeout?.cancel(); let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self,self.generation == token else { return }; self.complete(message)
        }
        timeout = work; DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:work)
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard busy,!geocoder.isGeocoding,let fix = locations.last,fix.horizontalAccuracy>=0,
              fix.timestamp>=started.addingTimeInterval(-5),abs(fix.timestamp.timeIntervalSinceNow)<15 else { return }
        manager.stopUpdatingLocation()
        let token = generation
        let coordinates = String(format:"%.6f, %.6f",fix.coordinate.latitude,fix.coordinate.longitude)
        status = "正在解析地址："+coordinates
        schedule(12,message:"坐标："+coordinates+"；街道解析超时，可手动填写。")
        geocoder.reverseGeocodeLocation(fix,preferredLocale:Locale(identifier:"zh_CN")) { [weak self] list,error in
            DispatchQueue.main.async {
                guard let self,self.busy,self.generation == token else { return }
                if let p = list?.first {
                    var parts:[String] = []
                    for item in [p.administrativeArea,p.locality,p.subLocality,p.thoroughfare,p.subThoroughfare] {
                        if let item,!item.isEmpty,parts.last != item { parts.append(item) }
                    }
                    if parts.isEmpty,let name = p.name { parts.append(name) }
                    if !parts.isEmpty {
                        self.address = parts.joined(); self.resultID = UUID()
                        self.complete("已获取当前地址，仍可修改。"); return
                    }
                }
                self.complete("坐标："+coordinates+"；暂时无法解析街道，可手动填写。")
            }
        }
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        complete("定位失败："+error.localizedDescription)
    }
    private func complete(_ text:String) { cancel(); status = text }
    func cancel() { generation += 1; timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation(); geocoder.cancelGeocode(); busy = false }
}
