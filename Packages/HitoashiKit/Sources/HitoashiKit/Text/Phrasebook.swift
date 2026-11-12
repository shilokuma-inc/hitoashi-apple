import Foundation

/// 判定や提案を、利用者向けの文にする。
/// 判定は内部の値（℃・m/s）で行い、ここで言語と単位に直す（仕様書 §5-13）。
/// 日本語は、数字と助数詞の間を空けない（「20分」「15時まで」）
public struct Phrasebook: Sendable {
    public enum Language: String, Sendable {
        case japanese
        case english
    }

    public var language: Language
    public var usesFahrenheit: Bool
    /// 時刻を文字にするときの暦（タイムゾーンを含む）
    public var calendar: Calendar
    public var uses24Hour: Bool

    public init(language: Language = .japanese, usesFahrenheit: Bool = false, calendar: Calendar, uses24Hour: Bool = true) {
        self.language = language
        self.usesFahrenheit = usesFahrenheit
        self.calendar = calendar
        self.uses24Hour = uses24Hour
    }

    var isJapanese: Bool { language == .japanese }

    // MARK: - 数と時刻

    public func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    func clock(hour: Int, minute: Int) -> String {
        if uses24Hour {
            return String(format: "%d:%02d", hour, minute)
        }
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour.isMultiple(of: 12) ? 12 : hour % 12
        return String(format: "%d:%02d %@", display, minute, suffix)
    }

    /// 「15時」/ "3 PM"
    public func hour(_ hour: Int) -> String {
        if isJapanese {
            return "\(hour)時"
        }
        if uses24Hour {
            return "\(hour):00"
        }
        let display = hour.isMultiple(of: 12) ? 12 : hour % 12
        return "\(display) \(hour < 12 ? "AM" : "PM")"
    }

    public func temperature(_ celsius: Double) -> String {
        let value = usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    public func minutes(_ value: Int) -> String {
        isJapanese ? "\(value)分" : "\(value) min"
    }

    public func duration(minutes value: Int) -> String {
        let hours = value / 60
        let rest = value % 60
        if hours == 0 {
            return minutes(rest)
        }
        if isJapanese {
            return rest == 0 ? "\(hours)時間" : "\(hours)時間\(rest)分"
        }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    public func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public func wind(_ metersPerSecond: Double) -> String {
        if isJapanese {
            return "\(Int(metersPerSecond.rounded()))m/s"
        }
        return usesFahrenheit
            ? "\(Int((metersPerSecond * 2.237).rounded())) mph"
            : "\(Int((metersPerSecond * 3.6).rounded())) km/h"
    }

    public func distance(meters: Double) -> String {
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10)m"
        }
        return String(format: "%.1fkm", meters / 1000)
    }

    // MARK: - 天気と判定

    private static let weatherNames: [WeatherKind: (japanese: String, english: String)] = [
        .clear: ("晴れ", "Clear"),
        .partlyCloudy: ("晴れ時々くもり", "Partly cloudy"),
        .cloudy: ("くもり", "Cloudy"),
        .fog: ("霧", "Fog"),
        .drizzle: ("小雨", "Drizzle"),
        .rain: ("雨", "Rain"),
        .heavyRain: ("大雨", "Heavy rain"),
        .thunder: ("雷雨", "Thunderstorms"),
        .snow: ("雪", "Snow"),
        .sleet: ("みぞれ", "Sleet"),
        .windy: ("強風", "Windy"),
        .smoke: ("煙・砂ぼこり", "Smoke or dust"),
        .severeStorm: ("暴風雨", "Severe storm")
    ]

    public func weatherName(_ kind: WeatherKind) -> String {
        let names = Self.weatherNames[kind]
        return (isJapanese ? names?.japanese : names?.english) ?? kind.rawValue
    }

    public func verdictName(_ level: VerdictLevel) -> String {
        switch level {
        case .great:
            isJapanese ? "外がおすすめ" : "Great outside"
        case .caution:
            isJapanese ? "外は気をつけて" : "Outside, with care"
        case .indoor:
            isJapanese ? "屋内がおすすめ" : "Better indoors"
        case .rest:
            isJapanese ? "きょうは休む日" : "A day to rest"
        }
    }

    // MARK: - ひと足

    /// 「代々木公園まで歩く」
    public func title(for plan: StepPlan) -> String {
        let name = plan.spot?.name ?? ""
        switch plan.activity {
        case .walk:
            if plan.spot == nil {
                return isJapanese ? "近くをひと回り歩く" : "Walk around nearby"
            }
            return isJapanese ? "\(name)まで歩く" : "Walk to \(name)"
        case .coveredWalk:
            return isJapanese ? "\(name)の中を歩く" : "Walk inside \(name)"
        case .jog:
            return isJapanese ? "\(name)を走る" : "Run at \(name)"
        case .gym:
            return isJapanese ? "\(name)でトレーニング" : "Work out at \(name)"
        case .onTheSpot:
            return isJapanese ? "その場でストレッチ" : "Stretch where you are"
        }
    }

    /// 「代々木公園まで」「渋谷ヒカリエの中を」（代わりの案と通知に使う）
    public func destination(for plan: StepPlan) -> String {
        let name = plan.spot?.name ?? ""
        switch plan.activity {
        case .walk:
            if plan.spot == nil {
                return isJapanese ? "近くをひと回り" : "around nearby"
            }
            return isJapanese ? "\(name)まで" : "to \(name)"
        case .coveredWalk:
            return isJapanese ? "\(name)の中を" : "inside \(name)"
        case .jog:
            return isJapanese ? "\(name)を走って" : "a run at \(name)"
        case .gym:
            return isJapanese ? "\(name)で" : "at \(name)"
        case .onTheSpot:
            return isJapanese ? "その場でストレッチ" : "a stretch where you are"
        }
    }

    public func alternateLabel(_ label: AlternatePlan.Label) -> String {
        switch label {
        case .ifRain:
            isJapanese ? "雨なら" : "If it rains"
        case .ifClear:
            isJapanese ? "晴れたら" : "If it clears"
        }
    }

    /// 「渋谷ヒカリエの中を15分」
    public func alternateText(_ alternate: AlternatePlan) -> String {
        let plan = alternate.plan
        if plan.activity == .onTheSpot {
            return isJapanese ? "その場でストレッチを\(minutes(plan.minutes))" : "Stretch for \(minutes(plan.minutes))"
        }
        return isJapanese
            ? "\(destination(for: plan))\(minutes(plan.minutes))"
            : "\(minutes(plan.minutes)) \(destination(for: plan))"
    }

    /// 「15:00 に終わる予定のあと」「昼休みに」
    public func slotLabel(_ slot: Slot) -> String {
        switch slot.kind {
        case .lunch:
            return isJapanese ? "昼休みに" : "At lunch"
        case .freeDay:
            return isJapanese ? "予定のない日" : "A free day"
        case .beforeFirst:
            if let next = slot.nextEventStart {
                return isJapanese ? "\(time(next)) に始まる予定のまえ" : "Before your \(time(next)) plan"
            }
            return isJapanese ? "予定のまえ" : "Before your plan"
        case .between, .afterLast:
            if let end = slot.previousEventEnd {
                return isJapanese ? "\(time(end)) に終わる予定のあと" : "After your plan ends at \(time(end))"
            }
            return isJapanese ? "予定のあと" : "After your plan"
        }
    }

    // MARK: - 決め手

    public func headline(_ headline: Headline, level: VerdictLevel) -> String {
        switch headline {
        case .alert:
            return isJapanese ? "警報が出ています" : "A weather alert is in effect"
        case .heat(let apparent):
            if level == .caution {
                return isJapanese
                    ? "体感\(temperature(apparent))。日かげを歩き、水を持って"
                    : "Feels like \(temperature(apparent)). Keep to the shade and carry water"
            }
            return isJapanese ? "体感\(temperature(apparent))。屋内で" : "Feels like \(temperature(apparent)). Stay inside"
        case .cold(let apparent):
            return isJapanese ? "体感\(temperature(apparent))。あたたかくして" : "Feels like \(temperature(apparent)). Dress warm"
        case .windy(let speed):
            return isJapanese ? "風\(wind(speed))。風の弱い道を" : "Wind \(wind(speed)). Pick a sheltered street"
        case .uv(let index):
            return isJapanese ? "UV \(index)。帽子があると安心" : "UV \(index). A hat helps"
        case .comfortable(let apparent):
            return isJapanese
                ? "体感\(temperature(apparent))。歩くのにちょうどいい"
                : "Feels like \(temperature(apparent)). Good for a walk"
        case .rainUntil, .rainFrom, .rainLikely, .rainPossible, .smoke, .dark, .sunsetIn, .goldenHour:
            return skyHeadline(headline)
        }
    }

    /// 雨の時刻・降水確率・明るさについての決め手
    private func skyHeadline(_ headline: Headline) -> String {
        switch headline {
        case .rainUntil(let hour):
            isJapanese ? "雨は\(self.hour(hour))まで" : "Rain until \(self.hour(hour))"
        case .rainFrom(let hour):
            isJapanese ? "雨は\(self.hour(hour))から" : "Rain from \(self.hour(hour))"
        case .rainLikely(let chance):
            isJapanese ? "降水確率\(percent(chance))。屋根のあるところで" : "\(percent(chance)) chance of rain. Stay under cover"
        case .rainPossible(let chance):
            isJapanese ? "降水確率\(percent(chance))。傘があると安心" : "\(percent(chance)) chance of rain. Bring an umbrella"
        case .smoke:
            isJapanese ? "煙や砂ぼこりの予報。屋根のあるところで" : "Smoke or dust in the air. Stay under cover"
        case .dark:
            isJapanese ? "日没後。明るい通りを" : "After dark. Keep to lit streets"
        case .sunsetIn(let value):
            isJapanese ? "日没まで\(duration(minutes: value))" : "\(duration(minutes: value)) until sunset"
        case .goldenHour:
            isJapanese ? "夕暮れの中を歩けます" : "You can walk into the sunset"
        default:
            ""
        }
    }

    /// 決め手の 1 行（「雨は15時まで。日没まで1時間28分。」）
    public func headlineLine(for suggestion: Suggestion) -> String {
        let parts = suggestion.headlines.map { headline($0, level: suggestion.verdict.level) }
        return isJapanese ? parts.map { $0 + "。" }.joined() : parts.map { $0 + "." }.joined(separator: " ")
    }

    /// 判定の理由（詳細の「くわしく」に使う）
    public func reasonText(_ reason: VerdictReason) -> String {
        switch reason {
        case .alert(let summary):
            summary
        case .storm:
            isJapanese ? "荒れた天気" : "Severe weather"
        case .heat(let air, let apparent):
            isJapanese ? "気温\(temperature(air))・体感\(temperature(apparent))" : "\(temperature(air)), feels like \(temperature(apparent))"
        case .cold(let apparent):
            isJapanese ? "体感\(temperature(apparent))" : "Feels like \(temperature(apparent))"
        case .precipitation(let chance):
            isJapanese ? "降水確率\(percent(chance))" : "\(percent(chance)) chance of rain"
        case .wetWeather(let kind):
            weatherName(kind)
        case .wind(let speed):
            isJapanese ? "風\(wind(speed))" : "Wind \(wind(speed))"
        case .dark:
            isJapanese ? "日没後" : "After dark"
        case .uv(let index):
            "UV \(index)"
        }
    }

    /// 1 日のうちのいつごろか（前夜のお知らせに使う）
    func dayPart(_ date: Date) -> String {
        switch calendar.component(.hour, from: date) {
        case ..<10:
            isJapanese ? "朝" : "in the morning"
        case 10..<12:
            isJapanese ? "昼前" : "before noon"
        case 12..<15:
            isJapanese ? "昼すぎ" : "in the early afternoon"
        case 15..<18:
            isJapanese ? "夕方" : "in the late afternoon"
        default:
            isJapanese ? "夜" : "in the evening"
        }
    }
}
