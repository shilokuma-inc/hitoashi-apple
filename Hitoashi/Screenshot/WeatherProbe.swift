//
//  WeatherProbe.swift
//  Hitoashi
//
//  WeatherKit から実際に予報を取れるかを確かめる（DEBUG のビルドだけ）。
//  App ID の設定（Capabilities と App Services の両方で WeatherKit を有効にする）が効いているかの切り分けに使う。
//
//    Hitoashi -weather-probe YES    → 標準出力に WEATHER-PROBE の行を出して終わる
//

#if DEBUG
import CoreLocation
import Foundation
import HitoashiKit
import WeatherKit

enum WeatherProbe {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-weather-probe")

    static func runIfRequested() async {
        guard isRequested else {
            return
        }
        let tokyo = PlaceCell(Coordinate(latitude: 35.6812, longitude: 139.7645))
        do {
            let forecast = try await WeatherFetcher().forecast(for: tokyo, now: .now)
            let first = forecast.hours.first
            let alerts = "alertsAvailable=\(forecast.alertsAvailable) alertsSupported=\(forecast.alertsSupported)"
            let summary = "hours=\(forecast.hours.count) days=\(forecast.days.count) \(alerts)"
            print("WEATHER-PROBE ok \(summary)")
            let kind = first.map { String(describing: $0.kind) } ?? "-"
            print("WEATHER-PROBE first=\(kind) \(first?.temperature ?? 0)C chance=\(first?.precipitationChance ?? 0)")
            // 警報と分単位の降水が、この地点で提供されているか（提供なし / 一時的に取れない を見分ける）
            let center = tokyo.center
            let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let availability = try await WeatherService.shared.weather(for: location, including: .availability)
            print("WEATHER-PROBE availability alert=\(availability.alertAvailability) minute=\(availability.minuteAvailability)")
        } catch {
            print("WEATHER-PROBE error \(error)")
        }
        fflush(stdout)
        exit(0)
    }
}
#endif
