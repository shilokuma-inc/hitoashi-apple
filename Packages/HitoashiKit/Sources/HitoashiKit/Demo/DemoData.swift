import Foundation

/// 見本のデータ（仕様書 §3「見本の表示」）。
/// 権限を許可する前の見本・スクリーンショット・UI テスト・パッケージのテストで同じものを使う。
/// 実在の個人や予定ではない。天気も実際の値ではない
public struct DemoWorld: Sendable {
    public var now: Date
    public var calendar: Calendar
    public var bases: [BasePlace]
    public var events: [PlanEvent]
    /// 予定の id ごとの場所（座標つきの予定のぶん）
    public var places: [String: ResolvedPlace]
    public var forecasts: [PlaceCell: PlaceForecast]
    public var spots: [PlaceCell: NearbySpots]

    /// 計画を作る入力にする
    public func plannerInput(preferences: Preferences = Preferences(), isPro: Bool = false) -> WeekPlanner.Input {
        WeekPlanner.Input(
            events: events,
            places: places,
            bases: bases,
            forecasts: forecasts,
            spots: spots,
            preferences: preferences,
            isPro: isPro,
            now: now,
            calendar: calendar
        )
    }
}

public enum DemoData {
    public static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    // 見本の場所
    static let home = Coordinate(latitude: 35.6566, longitude: 139.6700)
    static let work = Coordinate(latitude: 35.6812, longitude: 139.7645)
    static let shibuya = Coordinate(latitude: 35.6642, longitude: 139.6997)
    static let ebisu = Coordinate(latitude: 35.6467, longitude: 139.7101)

    /// 見本の「いま」: 2026-11-12（木）9:41
    public static var now: Date { date(day: 0, hour: 9, minute: 41) }

    /// - Parameter alertToday: 今日に重大な警報が出ている見本にする（休む日の画面用）
    public static func world(alertToday: Bool = false) -> DemoWorld {
        let fetchedAt = date(day: 0, hour: 9, minute: 2)
        var forecasts: [PlaceCell: PlaceForecast] = [:]
        for coordinate in [home, work, shibuya, ebisu] {
            let cell = PlaceCell(coordinate)
            forecasts[cell] = forecast(cell: cell, fetchedAt: fetchedAt, alertToday: alertToday)
        }
        let events = makeEvents()
        var places: [String: ResolvedPlace] = [:]
        for event in events {
            if let coordinate = event.coordinate {
                places[event.id] = ResolvedPlace(coordinate: coordinate, name: event.locationText ?? "", source: .eventCoordinate)
            }
        }
        return DemoWorld(
            now: now,
            calendar: calendar,
            bases: [
                BasePlace(id: "home", kind: .home, name: "自宅", coordinate: home),
                BasePlace(id: "work", kind: .work, name: "職場", coordinate: work)
            ],
            events: events,
            places: places,
            forecasts: forecasts,
            spots: makeSpots()
        )
    }

    /// 見本の日付（今日 = 2026-11-12 を 0 として、その日の時刻）
    public static func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 11
        parts.day = 12 + day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? .distantPast
    }

    // MARK: - 予定

    private static func event(
        _ id: String,
        _ title: String,
        day: Int,
        from: (Int, Int),
        to end: (Int, Int),
        location: String? = nil,
        at coordinate: Coordinate? = nil
    ) -> PlanEvent {
        PlanEvent(
            id: id,
            title: title,
            start: date(day: day, hour: from.0, minute: from.1),
            end: date(day: day, hour: end.0, minute: end.1),
            locationText: location,
            coordinate: coordinate,
            calendarID: "demo"
        )
    }

    private static func makeEvents() -> [PlanEvent] {
        let online = "https://example.com/meeting/000"
        return [
            // 今日（木）: 昼の雨が 15 時に上がる
            event("d0-1", "定例ミーティング", day: 0, from: (10, 0), to: (11, 0), location: online),
            event("d0-2", "打ち合わせ", day: 0, from: (13, 0), to: (14, 30), location: "渋谷 神南オフィス", at: shibuya),
            event("d0-3", "1on1", day: 0, from: (16, 0), to: (17, 0), location: "8F Fuji"),
            event("d0-4", "会食", day: 0, from: (19, 0), to: (21, 0), location: "恵比寿", at: ebisu),
            // あす（金）: 晴れ
            event("d1-1", "朝会", day: 1, from: (9, 30), to: (10, 0), location: online),
            event("d1-2", "レビュー会", day: 1, from: (14, 0), to: (15, 30), location: "丸の内 3-2-1", at: work),
            event("d1-3", "面談", day: 1, from: (17, 0), to: (18, 0), location: online),
            // 土・日は予定なし
            // 月: 一日じゅう雨
            event("d4-1", "朝会", day: 4, from: (9, 30), to: (10, 30), location: online),
            event("d4-2", "レビュー会", day: 4, from: (14, 0), to: (15, 30), location: "丸の内 3-2-1", at: work),
            event("d4-3", "面談", day: 4, from: (17, 0), to: (18, 0), location: online),
            // 火: 荒れた天気
            event("d5-1", "定例ミーティング", day: 5, from: (10, 0), to: (11, 0), location: online),
            event("d5-2", "設計レビュー", day: 5, from: (14, 0), to: (15, 0), location: online),
            // 水
            event("d6-1", "定例ミーティング", day: 6, from: (10, 0), to: (11, 0), location: online),
            event("d6-2", "打ち合わせ", day: 6, from: (15, 0), to: (16, 0), location: "渋谷 神南オフィス", at: shibuya),
            // 木
            event("d7-1", "朝会", day: 7, from: (9, 30), to: (10, 0), location: online),
            event("d7-2", "勉強会", day: 7, from: (16, 0), to: (17, 30), location: "5F Sakura")
        ]
    }

    // MARK: - スポット

    private static func spot(_ id: String, _ name: String, _ latitude: Double, _ longitude: Double, _ category: SpotCategory) -> Spot {
        Spot(id: id, name: name, coordinate: Coordinate(latitude: latitude, longitude: longitude), category: category)
    }

    private static func makeSpots() -> [PlaceCell: NearbySpots] {
        [PlaceCell(shibuya): shibuyaSpots, PlaceCell(work): workSpots, PlaceCell(home): homeSpots]
    }

    private static var shibuyaSpots: NearbySpots {
        NearbySpots(
            parks: [
                spot("p-yoyogi", "代々木公園", 35.6688, 139.6968, .park),
                spot("p-kitaya", "北谷公園", 35.6638, 139.7006, .park),
                spot("p-miyashita", "宮下公園", 35.6620, 139.7020, .park)
            ],
            stations: [
                spot("s-harajuku", "原宿駅", 35.6702, 139.7027, .station),
                spot("s-shibuya", "渋谷駅", 35.6580, 139.7016, .station)
            ],
            covered: [spot("c-parco", "渋谷パルコ", 35.6620, 139.6988, .covered)],
            gyms: [spot("g-jinnan", "神南スポーツジム", 35.6631, 139.7001, .gym)],
            tracks: [spot("t-oda", "代々木公園 陸上競技場", 35.6665, 139.6975, .track)]
        )
    }

    private static var workSpots: NearbySpots {
        NearbySpots(
            parks: [
                spot("p-wadakura", "和田倉噴水公園", 35.6842, 139.7610, .park),
                spot("p-hibiya", "日比谷公園", 35.6736, 139.7560, .park)
            ],
            stations: [
                spot("s-otemachi", "大手町駅", 35.6849, 139.7663, .station),
                spot("s-yurakucho", "有楽町駅", 35.6751, 139.7633, .station)
            ],
            covered: [
                spot("c-marubiru", "丸ビル", 35.6812, 139.7638, .covered),
                spot("c-kitte", "KITTE", 35.6797, 139.7650, .covered)
            ],
            gyms: [spot("g-marunouchi", "丸の内スポーツジム", 35.6800, 139.7655, .gym)],
            tracks: [spot("t-kokyo", "皇居外苑", 35.6805, 139.7580, .track)]
        )
    }

    private static var homeSpots: NearbySpots {
        NearbySpots(
            parks: [
                spot("p-kitazawa", "北沢川緑道", 35.6540, 139.6668, .park),
                spot("p-hanegi", "羽根木公園", 35.6630, 139.6560, .park)
            ],
            stations: [
                spot("s-shimokita", "下北沢駅", 35.6614, 139.6680, .station),
                spot("s-ikenoue", "池ノ上駅", 35.6607, 139.6735, .station)
            ],
            covered: [spot("c-ekiue", "シモキタエキウエ", 35.6614, 139.6679, .covered)],
            gyms: [],
            tracks: [spot("t-hanegi", "羽根木公園", 35.6630, 139.6560, .track)]
        )
    }

    // MARK: - 天気

    private struct DaySpec {
        var kind: WeatherKind
        var high: Double
        var low: Double
        /// 雨の時間（0〜23 時）
        var rainHours: Range<Int> = 0..<0
        var rainChance: Double = 0.7
        var wind: Double = 2
    }

    private static let daySpecs: [DaySpec] = [
        DaySpec(kind: .rain, high: 18, low: 9, rainHours: 11..<15, rainChance: 0.75, wind: 3),
        DaySpec(kind: .clear, high: 19, low: 8),
        DaySpec(kind: .clear, high: 20, low: 9),
        DaySpec(kind: .cloudy, high: 16, low: 10),
        DaySpec(kind: .rain, high: 13, low: 10, rainHours: 0..<24, rainChance: 0.8, wind: 4),
        DaySpec(kind: .severeStorm, high: 14, low: 11, rainHours: 0..<24, rainChance: 0.95, wind: 16),
        DaySpec(kind: .partlyCloudy, high: 17, low: 9),
        DaySpec(kind: .clear, high: 18, low: 8),
        DaySpec(kind: .cloudy, high: 15, low: 9, rainHours: 18..<24, rainChance: 0.6),
        DaySpec(kind: .clear, high: 17, low: 7)
    ]

    private static func forecast(cell: PlaceCell, fetchedAt: Date, alertToday: Bool) -> PlaceForecast {
        var hours: [HourForecast] = []
        var days: [DayForecast] = []
        var specs = daySpecs
        if alertToday {
            specs[0] = DaySpec(kind: .heavyRain, high: 14, low: 11, rainHours: 0..<24, rainChance: 0.95, wind: 9)
        }
        for (index, spec) in specs.enumerated() {
            let sunrise = date(day: index, hour: 6, minute: 14 + index)
            let sunset = date(day: index, hour: 16, minute: 38 - index / 2)
            days.append(
                DayForecast(
                    date: date(day: index, hour: 0),
                    kind: spec.kind,
                    high: spec.high,
                    low: spec.low,
                    precipitationChance: spec.rainHours.isEmpty ? 0.1 : spec.rainChance,
                    sunrise: sunrise,
                    sunset: sunset
                )
            )
            for hour in 0..<24 {
                hours.append(hourForecast(spec: spec, day: index, hour: hour))
            }
        }
        let alerts = alertToday
            ? [
                WeatherAlertInfo(
                    summary: "大雨警報",
                    source: "気象庁",
                    detailsURL: URL(string: "https://www.jma.go.jp/bosai/warning/"),
                    severity: .severe
                )
            ]
            : []
        return PlaceForecast(cell: cell, fetchedAt: fetchedAt, hours: hours, days: days, alerts: alerts)
    }

    private static func hourForecast(spec: DaySpec, day: Int, hour: Int) -> HourForecast {
        // 6 時がいちばん低く、14 時がいちばん高い
        let phase = cos(Double(hour - 14) / 24 * 2 * .pi)
        let temperature = (spec.high + spec.low) / 2 + (spec.high - spec.low) / 2 * phase
        let rainy = spec.rainHours.contains(hour)
        let isDaylight = (7...16).contains(hour)
        let kind: WeatherKind
        if rainy {
            kind = spec.kind.isWet || spec.kind == .severeStorm ? spec.kind : .rain
        } else if spec.kind.isWet {
            kind = .clear
        } else {
            kind = spec.kind
        }
        return HourForecast(
            date: date(day: day, hour: hour),
            kind: kind,
            temperature: temperature.rounded(),
            apparentTemperature: (temperature - (spec.wind > 5 ? 3 : 1)).rounded(),
            precipitationChance: rainy ? spec.rainChance : (spec.kind == .cloudy ? 0.2 : 0.05),
            precipitationAmount: rainy ? 1.5 : 0,
            windSpeed: spec.wind,
            windGust: spec.wind > 8 ? spec.wind + 6 : nil,
            uvIndex: isDaylight && (10...14).contains(hour) ? 3 : (isDaylight ? 1 : 0),
            isDaylight: isDaylight,
            cloudCover: rainy ? 0.95 : (kind == .clear ? 0.15 : 0.6)
        )
    }
}
