import Foundation

/// 天気の種類（WeatherKit の WeatherCondition を、判定に要る粒度にまとめたもの）
public enum WeatherKind: String, Hashable, Sendable, Codable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case thunder
    case snow
    case sleet
    case windy
    /// 台風・熱帯低気圧・暴風雪など
    case severeStorm

    /// 雨・雪・雷の天気（小雨を含む。屋内の判定に使う。仕様書 §5-5）
    public var isWet: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .thunder, .snow, .sleet:
            true
        case .clear, .partlyCloudy, .cloudy, .fog, .windy, .severeStorm:
            false
        }
    }
}

/// 時間ごとの予報。値は ℃・m/s・mm/h
public struct HourForecast: Hashable, Sendable, Codable {
    /// その時間の始まり
    public var date: Date
    public var kind: WeatherKind
    public var temperature: Double
    public var apparentTemperature: Double
    /// 降水確率（0〜1）
    public var precipitationChance: Double
    /// 降水量（mm/h）
    public var precipitationAmount: Double
    /// 平均風速（m/s）
    public var windSpeed: Double
    /// 突風（m/s）
    public var windGust: Double?
    public var uvIndex: Int
    public var isDaylight: Bool
    /// 雲の量（0〜1）
    public var cloudCover: Double

    public init(
        date: Date,
        kind: WeatherKind,
        temperature: Double,
        apparentTemperature: Double,
        precipitationChance: Double,
        precipitationAmount: Double = 0,
        windSpeed: Double = 2,
        windGust: Double? = nil,
        uvIndex: Int = 1,
        isDaylight: Bool = true,
        cloudCover: Double = 0.3
    ) {
        self.date = date
        self.kind = kind
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.uvIndex = uvIndex
        self.isDaylight = isDaylight
        self.cloudCover = cloudCover
    }
}

/// 日ごとの予報
public struct DayForecast: Hashable, Sendable, Codable {
    /// その日の始まり（地点の現地時刻の 0 時）
    public var date: Date
    public var kind: WeatherKind
    public var high: Double
    public var low: Double
    public var precipitationChance: Double
    public var sunrise: Date?
    public var sunset: Date?

    public init(
        date: Date,
        kind: WeatherKind,
        high: Double,
        low: Double,
        precipitationChance: Double,
        sunrise: Date? = nil,
        sunset: Date? = nil
    ) {
        self.date = date
        self.kind = kind
        self.high = high
        self.low = low
        self.precipitationChance = precipitationChance
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

/// 気象警報の重大度
public enum AlertSeverity: Int, Hashable, Sendable, Codable, Comparable {
    case unknown = 0
    case minor
    case moderate
    case severe
    case extreme

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 気象警報。文面は発表されたまま持つ（言い換えない。仕様書 §8）
public struct WeatherAlertInfo: Hashable, Sendable, Codable {
    public var summary: String
    /// 発表機関の正式な名前
    public var source: String
    public var detailsURL: URL?
    public var severity: AlertSeverity

    public init(summary: String, source: String, detailsURL: URL?, severity: AlertSeverity) {
        self.summary = summary
        self.source = source
        self.detailsURL = detailsURL
        self.severity = severity
    }
}

/// 1 つの地点の予報（1 回の取得ぶん）
public struct PlaceForecast: Hashable, Sendable, Codable {
    public var cell: PlaceCell
    public var fetchedAt: Date
    public var hours: [HourForecast]
    public var days: [DayForecast]
    public var alerts: [WeatherAlertInfo]
    /// この地域で警報の情報を取れるか
    public var alertsAvailable: Bool

    public init(
        cell: PlaceCell,
        fetchedAt: Date,
        hours: [HourForecast],
        days: [DayForecast],
        alerts: [WeatherAlertInfo] = [],
        alertsAvailable: Bool = true
    ) {
        self.cell = cell
        self.fetchedAt = fetchedAt
        self.hours = hours
        self.days = days
        self.alerts = alerts
        self.alertsAvailable = alertsAvailable
    }

    /// 時間帯にかかる時間ごとの予報
    public func hours(overlapping interval: DateInterval) -> [HourForecast] {
        hours.filter { hour in
            hour.date < interval.end && hour.date.addingTimeInterval(3600) > interval.start
        }
    }

    /// その時刻を含む時間の予報
    public func hour(at date: Date) -> HourForecast? {
        hours.last { $0.date <= date && date < $0.date.addingTimeInterval(3600) }
    }

    /// その日の予報
    public func day(containing date: Date, calendar: Calendar) -> DayForecast? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
