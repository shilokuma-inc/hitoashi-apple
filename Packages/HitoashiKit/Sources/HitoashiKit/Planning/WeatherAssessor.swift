import Foundation

/// そと判定の段階（仕様書 §5-5）
public enum VerdictLevel: Int, Hashable, Sendable, Comparable, Codable {
    /// 休む（外へ出る案を出さない）
    case rest = 0
    /// 屋内
    case indoor
    /// 外は気をつけて
    case caution
    /// 外がおすすめ
    case great

    public static func < (lhs: VerdictLevel, rhs: VerdictLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 判定の理由。値は内部の単位（℃・m/s・0〜1）のまま持ち、文面にするときに直す
public enum VerdictReason: Hashable, Sendable {
    case alert(summary: String)
    case storm
    case heat(temperature: Double, apparent: Double)
    case cold(apparent: Double)
    case precipitation(chance: Double)
    case wetWeather(WeatherKind)
    case wind(speed: Double)
    case dark
    case uv(Int)
}

public struct Verdict: Hashable, Sendable {
    public var level: VerdictLevel
    /// その段階になった理由（効いた順）
    public var reasons: [VerdictReason]

    public init(level: VerdictLevel, reasons: [VerdictReason]) {
        self.level = level
        self.reasons = reasons
    }

    /// 降水が理由で屋内になったか（通知で言い切ってよいかの判断に使う）
    public var isIndoorBecauseOfRain: Bool {
        level == .indoor && reasons.contains { reason in
            switch reason {
            case .precipitation, .wetWeather:
                true
            case .alert, .storm, .heat, .cold, .wind, .dark, .uv:
                false
            }
        }
    }
}

/// 動く時間帯にかかる予報から、そと判定を出す（仕様書 §5-5 の表）。
/// 値は「以上・未満」で切る。悪い条件が 1 つでも当たれば、その段階になる
public enum WeatherAssessor {
    /// - Parameters:
    ///   - hours: 窓にかかる時間ごとの予報
    ///   - severeAlerts: この窓に当てる、重大な警報（severe / extreme）
    ///   - isDark: 窓が暗い時間（日没の 30 分後以降、または日の出前）にかかるか
    public static func assess(hours: [HourForecast], severeAlerts: [WeatherAlertInfo] = [], isDark: Bool) -> Verdict {
        let worst = Worst(hours: hours)
        let rest = restReasons(worst, severeAlerts: severeAlerts)
        if !rest.isEmpty {
            return Verdict(level: .rest, reasons: rest)
        }
        let indoor = indoorReasons(worst)
        if !indoor.isEmpty {
            return Verdict(level: .indoor, reasons: indoor)
        }
        let caution = cautionReasons(worst, isDark: isDark)
        return Verdict(level: caution.isEmpty ? .great : .caution, reasons: caution)
    }

    /// 窓にかかる時間の、いちばん悪い値
    struct Worst {
        var temperature: Double
        var maxApparent: Double
        var minApparent: Double
        var chance: Double
        var amount: Double
        var wind: Double
        var gust: Double
        var uv: Int
        var wetKind: WeatherKind?
        var hasStorm: Bool

        init(hours: [HourForecast]) {
            temperature = hours.map(\.temperature).max() ?? 0
            maxApparent = hours.map(\.apparentTemperature).max() ?? 0
            minApparent = hours.map(\.apparentTemperature).min() ?? 0
            chance = hours.map(\.precipitationChance).max() ?? 0
            amount = hours.map(\.precipitationAmount).max() ?? 0
            wind = hours.map(\.windSpeed).max() ?? 0
            gust = hours.compactMap(\.windGust).max() ?? 0
            uv = hours.map(\.uvIndex).max() ?? 0
            wetKind = hours.map(\.kind).first(where: \.keepsIndoors)
            hasStorm = hours.contains { $0.kind == .severeStorm }
        }
    }

    static func restReasons(_ worst: Worst, severeAlerts: [WeatherAlertInfo]) -> [VerdictReason] {
        var reasons: [VerdictReason] = severeAlerts.map { .alert(summary: $0.summary) }
        if worst.hasStorm {
            reasons.append(.storm)
        }
        if worst.temperature >= 35 || worst.maxApparent >= 40 {
            reasons.append(.heat(temperature: worst.temperature, apparent: worst.maxApparent))
        }
        if worst.minApparent < -15 {
            reasons.append(.cold(apparent: worst.minApparent))
        }
        if worst.wind >= 15 || worst.gust >= 20 {
            reasons.append(.wind(speed: worst.wind))
        }
        return reasons
    }

    static func indoorReasons(_ worst: Worst) -> [VerdictReason] {
        var reasons: [VerdictReason] = []
        if worst.temperature >= 31 || worst.maxApparent >= 31 {
            reasons.append(.heat(temperature: worst.temperature, apparent: worst.maxApparent))
        }
        if worst.minApparent < -5 {
            reasons.append(.cold(apparent: worst.minApparent))
        }
        if worst.chance >= 0.5 {
            reasons.append(.precipitation(chance: worst.chance))
        } else if let wetKind = worst.wetKind {
            reasons.append(.wetWeather(wetKind))
        } else if worst.amount >= 0.5 {
            reasons.append(.wetWeather(.rain))
        }
        if worst.wind >= 10 || worst.gust >= 15 {
            reasons.append(.wind(speed: worst.wind))
        }
        if worst.uv >= 11 {
            reasons.append(.uv(worst.uv))
        }
        return reasons
    }

    static func cautionReasons(_ worst: Worst, isDark: Bool) -> [VerdictReason] {
        var reasons: [VerdictReason] = []
        if worst.temperature >= 28 || worst.maxApparent >= 28 {
            reasons.append(.heat(temperature: worst.temperature, apparent: worst.maxApparent))
        }
        if worst.minApparent < 5 {
            reasons.append(.cold(apparent: worst.minApparent))
        }
        if worst.chance >= 0.3 {
            reasons.append(.precipitation(chance: worst.chance))
        }
        if worst.wind >= 7 {
            reasons.append(.wind(speed: worst.wind))
        }
        if isDark {
            reasons.append(.dark)
        }
        if worst.uv >= 8 {
            reasons.append(.uv(worst.uv))
        }
        return reasons
    }
}
