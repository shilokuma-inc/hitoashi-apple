import Foundation

/// 決め手（「なぜ今か」）を、効いた順に 2 つまで選ぶ（仕様書 §4-2、§5-5）。
/// 順は 警報 > 暑さ・寒さ > 降水の時刻 > 風 > 暗さ > UV > 夕暮れ
struct HeadlineBuilder {
    var verdict: Verdict
    var plan: StepPlan
    var window: DateInterval
    var forecast: PlaceForecast
    var day: DayForecast?
    var calendar: Calendar

    func build() -> [Headline] {
        let reasons = reasonHeadlines()
        // 警報・暑さ・寒さのあと、ほかの理由の前に、降水の時刻を差し込む
        let leading = reasons.prefix { headline in
            switch headline {
            case .alert, .heat, .cold:
                true
            default:
                false
            }
        }
        var result = Array(leading) + rainTiming() + Array(reasons.dropFirst(leading.count))
        if let sunset = sunsetHeadline() {
            result.append(sunset)
        }
        if result.isEmpty, let hour = forecast.hour(at: window.start) {
            result.append(.comfortable(apparent: hour.apparentTemperature))
        }
        return Array(result.prefix(2))
    }

    /// 判定の理由を、決め手の形にする
    private func reasonHeadlines() -> [Headline] {
        let maxChance = forecast.hours(overlapping: window).map(\.precipitationChance).max() ?? 0
        let isIndoor = verdict.level == .indoor
        return verdict.reasons.map { reason -> Headline in
            switch reason {
            case .alert, .storm:
                .alert
            case .heat(_, let apparent):
                .heat(apparent: apparent)
            case .cold(let apparent):
                .cold(apparent: apparent)
            case .precipitation(let chance):
                if isIndoor {
                    .rainLikely(chance: chance)
                } else {
                    .rainPossible(chance: chance)
                }
            case .wetWeather(let kind):
                // 煙・砂ぼこりで屋内にした日に「降水確率 0%」と書かない
                kind == .smoke ? .smoke : .rainLikely(chance: maxChance)
            case .wind(let speed):
                .windy(speed: speed)
            case .dark:
                .dark
            case .uv(let index):
                .uv(index)
            }
        }
    }

    /// 外の案だけ。直前の 3 時間に雨があれば「雨は ◯ 時まで」、直後の 3 時間に雨が来るなら「雨は ◯ 時から」
    private func rainTiming() -> [Headline] {
        guard plan.activity.isOutdoor else {
            return []
        }
        let before = forecast.hours(overlapping: DateInterval(start: window.start.addingTimeInterval(-3 * 3600), end: window.start))
        if let lastRain = before.last(where: { Comfort.isRainy($0) && $0.date.addingTimeInterval(3600) <= window.start }) {
            return [.rainUntil(hour: calendar.component(.hour, from: lastRain.date.addingTimeInterval(3600)))]
        }
        let after = forecast.hours(overlapping: DateInterval(start: window.end, end: window.end.addingTimeInterval(3 * 3600)))
        if let firstRain = after.first(where: { Comfort.isRainy($0) && $0.date >= window.end }) {
            return [.rainFrom(hour: calendar.component(.hour, from: firstRain.date))]
        }
        return []
    }

    /// 外の案だけ。日没の前 45 分にかかり、雲が少なければ夕暮れ。日没まで 2 時間以内なら、その残り
    private func sunsetHeadline() -> Headline? {
        guard plan.activity.isOutdoor, let sunset = day?.sunset, window.start < sunset else {
            return nil
        }
        let cloud = forecast.hour(at: window.start)?.cloudCover ?? 1
        if window.end > sunset.addingTimeInterval(-45 * 60), cloud < 0.5 {
            return .goldenHour
        }
        let minutes = Int(sunset.timeIntervalSince(window.start) / 60)
        return minutes <= 120 ? .sunsetIn(minutes: minutes) : nil
    }
}
