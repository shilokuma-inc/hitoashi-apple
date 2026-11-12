import Foundation

/// 外で動くときの快適さ（0〜100）。時間ごとの予報から計算する（仕様書 §5-5）。
/// 快適さ = max(0, 100 − 減点の合計)。減点は要素ごとに上限がある
public enum Comfort {
    public static func score(_ hour: HourForecast) -> Double {
        max(0, 100 - penalty(hour))
    }

    static func penalty(_ hour: HourForecast) -> Double {
        let apparent = hour.apparentTemperature
        var temperature = 0.0
        if apparent > 24 {
            temperature = (apparent - 24) * 5
        } else if apparent < 12 {
            temperature = (12 - apparent) * 3
        }
        var precipitation = hour.precipitationChance * 100 * 0.4
        if hour.kind.isWet {
            precipitation = max(precipitation, 30)
        }
        let wind = hour.windSpeed > 3 ? (hour.windSpeed - 3) * 3 : 0
        let uv = hour.uvIndex > 5 ? Double(hour.uvIndex - 5) * 3 : 0
        let dark = hour.isDaylight ? 0.0 : 10
        return min(temperature, 40) + min(precipitation, 40) + min(wind, 20) + min(uv, 15) + dark
    }

    /// 雨で外に出にくい時間か（「雨は 15 時まで」の判定に使う）
    public static func isRainy(_ hour: HourForecast) -> Bool {
        hour.precipitationChance >= 0.5 || hour.precipitationAmount >= 0.5 || hour.kind.isWet
    }
}

/// 空き時間の中で、動く時間（移動 + ひと足）の長さの窓をずらし、快適さがいちばん高い窓を選ぶ（仕様書 §5-5）
public enum WindowPicker {
    public struct Window: Hashable, Sendable {
        public var interval: DateInterval
        /// 窓にかかる時間の快適さの、いちばん低い値
        public var comfort: Double
    }

    /// - Parameter minutes: 窓の長さ（分）
    public static func pick(in slot: DateInterval, minutes: Int, forecast: PlaceForecast, preferEarliest: Bool = false) -> Window? {
        let length = TimeInterval(minutes * 60)
        guard slot.duration >= length else {
            return nil
        }
        let step: TimeInterval = 5 * 60
        var start = roundUp(slot.start, step: step)
        var best: Window?
        while start.addingTimeInterval(length) <= slot.end {
            let interval = DateInterval(start: start, duration: length)
            if let comfort = comfort(of: interval, forecast: forecast) {
                // 同点は早い開始
                if best == nil || comfort > (best?.comfort ?? 0) {
                    best = Window(interval: interval, comfort: comfort)
                }
                if preferEarliest {
                    break
                }
            }
            start = start.addingTimeInterval(step)
        }
        guard var window = best else {
            return nil
        }
        // 直前の時間が雨だったら、その時間の終わりから 10 分あける（「雨は 15 時まで。15:10 から」）
        let hourStart = floorToHour(window.interval.start)
        if !preferEarliest,
           let previous = forecast.hour(at: hourStart.addingTimeInterval(-1)),
           Comfort.isRainy(previous),
           window.interval.start < hourStart.addingTimeInterval(10 * 60) {
            let shifted = DateInterval(start: hourStart.addingTimeInterval(10 * 60), duration: length)
            if shifted.end <= slot.end, let comfort = comfort(of: shifted, forecast: forecast), comfort >= window.comfort {
                window = Window(interval: shifted, comfort: comfort)
            }
        }
        return window
    }

    /// 窓にかかる時間の快適さの最小値（判定と同じく、悪いほうに合わせる）。予報が無ければ nil
    public static func comfort(of interval: DateInterval, forecast: PlaceForecast) -> Double? {
        let hours = forecast.hours(overlapping: interval)
        guard !hours.isEmpty else {
            return nil
        }
        return hours.map(Comfort.score).min()
    }

    static func roundUp(_ date: Date, step: TimeInterval) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / step).rounded(.up) * step)
    }

    static func floorToHour(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 3600).rounded(.down) * 3600)
    }
}
