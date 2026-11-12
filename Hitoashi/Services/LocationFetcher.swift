//
//  LocationFetcher.swift
//  Hitoashi
//
//  現在地を 1 回だけ取る。拠点（自宅・職場）を現在地から登録するときにだけ使う（仕様書 §5-3）。
//  許可は「使用中のみ」。バックグラウンドでは取らない。
//

import CoreLocation
import HitoashiKit

final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// 結果を待っている呼び出し（同時に呼ばれたら、同じ結果を全員に返す）
    private var waiters: [CheckedContinuation<Coordinate?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 現在地。許可されなかった・取れなかったときは nil
    func current() async -> Coordinate? {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            // すでに取得中なら、その結果を待つ
            guard waiters.count == 1 else {
                return
            }
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ coordinate: Coordinate?) {
        let waiting = waiters
        waiters = []
        for waiter in waiting {
            waiter.resume(returning: coordinate)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard !waiters.isEmpty else {
                return
            }
            switch status {
            case .notDetermined:
                break
            case .denied, .restricted:
                finish(nil)
            default:
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        Task { @MainActor in
            finish(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(nil)
        }
    }
}
