import Foundation
@testable import HitoashiKit

/// テストで使う暦と時刻（東京）。日付は見本と同じ 2026-11-12 を 0 日目にする
enum Fixture {
    static let calendar = DemoData.calendar

    static func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
        DemoData.date(day: day, hour: hour, minute: minute)
    }

    static var day0: Date { at(0) }

    static let office = ResolvedPlace(coordinate: DemoData.work, name: "職場", source: .base(.work))
    static let shibuya = ResolvedPlace(coordinate: DemoData.shibuya, name: "渋谷", source: .eventCoordinate)
    static let home = ResolvedPlace(coordinate: DemoData.home, name: "自宅", source: .base(.home))

    static func event(
        _ id: String,
        _ from: (Int, Int),
        _ end: (Int, Int),
        place: ResolvedPlace? = office,
        title: String = "予定",
        suppresses: Bool = false,
        transit: Bool = false
    ) -> DayEvent {
        DayEvent(
            id: id,
            title: title,
            start: at(from.0, from.1),
            end: at(end.0, end.1),
            place: place,
            suppressesSuggestions: suppresses,
            isTransit: transit
        )
    }

    /// 1 時間ぶんの予報
    static func hour(
        _ hour: Int,
        kind: WeatherKind = .clear,
        temperature: Double = 18,
        apparent: Double? = nil,
        chance: Double = 0,
        amount: Double = 0,
        wind: Double = 2,
        gust: Double? = nil,
        uv: Int = 1,
        daylight: Bool = true
    ) -> HourForecast {
        HourForecast(
            date: at(hour),
            kind: kind,
            temperature: temperature,
            apparentTemperature: apparent ?? temperature,
            precipitationChance: chance,
            precipitationAmount: amount,
            windSpeed: wind,
            windGust: gust,
            uvIndex: uv,
            isDaylight: daylight
        )
    }

    /// 1 日ぶんの予報（6〜21 時）。`customize` で時間ごとに変える
    static func forecast(
        for place: ResolvedPlace,
        fetchedAt: Date? = nil,
        sunset: (Int, Int) = (16, 38),
        alerts: [WeatherAlertInfo] = [],
        customize: (Int) -> HourForecast? = { _ in nil }
    ) -> PlaceForecast {
        let hours = (6...21).map { customize($0) ?? hour($0) }
        let day = DayForecast(
            date: day0,
            kind: .clear,
            high: 20,
            low: 9,
            precipitationChance: 0.1,
            sunrise: at(6, 14),
            sunset: at(sunset.0, sunset.1)
        )
        return PlaceForecast(cell: place.cell, fetchedAt: fetchedAt ?? at(9), hours: hours, days: [day], alerts: alerts)
    }

    static var book: Phrasebook { Phrasebook(calendar: calendar) }
}
