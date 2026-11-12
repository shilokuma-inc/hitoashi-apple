//
//  WeatherFetcher.swift
//  Hitoashi
//
//  天気を取る（WeatherKit）。1 回の呼び出しで、地点の「時間ごと（10 日ぶん）・日ごと・警報」をまとめて取る
//  （仕様書 §5-10。まとめて取ると 1 リクエスト）。値は、判定に使う形（℃・m/s・mm/h）に直して渡す。
//

import CoreLocation
import HitoashiKit
import WeatherKit

struct WeatherFetcher {
    func forecast(for cell: PlaceCell, now: Date) async throws -> PlaceForecast {
        let center = cell.center
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
        let end = start.addingTimeInterval(10 * 24 * 3600)
        let (hourly, daily, alerts, availability) = try await WeatherService.shared.weather(
            for: location,
            including: .hourly(startDate: start, endDate: end),
            .daily(startDate: start.addingTimeInterval(-24 * 3600), endDate: end),
            .alerts,
            .availability
        )
        return PlaceForecast(
            cell: cell,
            fetchedAt: now,
            hours: hourly.forecast.map(Self.hour),
            days: daily.forecast.map(Self.day),
            alerts: (alerts ?? []).map(Self.alert),
            alertsAvailable: availability.alertAvailability == .available,
            alertsSupported: availability.alertAvailability != .unsupported
        )
    }

    private static func hour(_ hour: HourWeather) -> HourForecast {
        HourForecast(
            date: hour.date,
            kind: kind(hour.condition),
            temperature: hour.temperature.converted(to: .celsius).value,
            apparentTemperature: hour.apparentTemperature.converted(to: .celsius).value,
            precipitationChance: hour.precipitationChance,
            precipitationAmount: hour.precipitationAmount.converted(to: .millimeters).value,
            windSpeed: hour.wind.speed.converted(to: .metersPerSecond).value,
            windGust: hour.wind.gust?.converted(to: .metersPerSecond).value,
            uvIndex: hour.uvIndex.value,
            isDaylight: hour.isDaylight,
            cloudCover: hour.cloudCover
        )
    }

    private static func day(_ day: DayWeather) -> DayForecast {
        DayForecast(
            date: day.date,
            kind: kind(day.condition),
            high: day.highTemperature.converted(to: .celsius).value,
            low: day.lowTemperature.converted(to: .celsius).value,
            precipitationChance: day.precipitationChance,
            sunrise: day.sun.sunrise,
            sunset: day.sun.sunset
        )
    }

    /// 警報。文面と発表機関は、発表されたまま持つ（言い換えない）
    private static func alert(_ alert: WeatherAlert) -> WeatherAlertInfo {
        let severity: AlertSeverity
        switch alert.severity {
        case .minor:
            severity = .minor
        case .moderate:
            severity = .moderate
        case .severe:
            severity = .severe
        case .extreme:
            severity = .extreme
        case .unknown:
            severity = .unknown
        @unknown default:
            severity = .unknown
        }
        return WeatherAlertInfo(summary: alert.summary, source: alert.source, detailsURL: alert.detailsURL, severity: severity)
    }

    /// WeatherKit の天気を、判定に要る粒度にまとめる（仕様書 §5-5）
    private static let kinds: [WeatherCondition: WeatherKind] = [
        .clear: .clear, .mostlyClear: .clear, .hot: .clear, .frigid: .clear,
        .partlyCloudy: .partlyCloudy, .mostlyCloudy: .cloudy, .cloudy: .cloudy,
        .foggy: .fog, .haze: .fog,
        .smoky: .smoke, .blowingDust: .smoke,
        .drizzle: .drizzle, .freezingDrizzle: .drizzle, .sunShowers: .drizzle,
        .rain: .rain, .freezingRain: .rain, .heavyRain: .heavyRain,
        .hail: .sleet, .sleet: .sleet, .wintryMix: .sleet,
        .snow: .snow, .heavySnow: .snow, .flurries: .snow, .sunFlurries: .snow, .blowingSnow: .snow,
        .thunderstorms: .thunder, .isolatedThunderstorms: .thunder, .scatteredThunderstorms: .thunder, .strongStorms: .thunder,
        .hurricane: .severeStorm, .tropicalStorm: .severeStorm, .blizzard: .severeStorm,
        .windy: .windy, .breezy: .clear
    ]

    private static func kind(_ condition: WeatherCondition) -> WeatherKind {
        kinds[condition] ?? .cloudy
    }
}
