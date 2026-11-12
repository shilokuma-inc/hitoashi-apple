import Foundation

/// 通知の文面（仕様書 §4-7、§5-9）。
/// 題は「なぜ今か」、本文は「いつから・何分・どこへ」。予定の題名は、設定でオンにしたときだけ入れる
extension Phrasebook {
    public struct NoticeText: Hashable, Sendable {
        public var title: String
        public var body: String
    }

    /// 天気を言い切る文面（外の案）
    func assertiveOutdoor(_ suggestion: Suggestion) -> NoticeText {
        let start = time(suggestion.window.start)
        let title: String
        switch suggestion.headlines.first {
        case .rainUntil(let hour):
            title = isJapanese
                ? "雨は\(self.hour(hour))までの予報。\(start)から歩けます"
                : "Rain should stop by \(self.hour(hour)). Walk from \(start)"
        case .rainFrom(let hour):
            title = isJapanese
                ? "雨は\(self.hour(hour))からの予報。いまなら歩けます"
                : "Rain expected from \(self.hour(hour)). Now is dry"
        case .sunsetIn(let value):
            title = isJapanese
                ? "日没まで\(duration(minutes: value))。\(start)から、ひと足"
                : "\(duration(minutes: value)) until sunset. Step out at \(start)"
        case .goldenHour:
            title = isJapanese ? "夕暮れの中を歩けます。\(start)から" : "Walk into the sunset from \(start)"
        case .comfortable(let apparent):
            title = isJapanese
                ? "体感\(temperature(apparent))。歩くのにちょうどいい"
                : "Feels like \(temperature(apparent)). Good for a walk"
        default:
            title = isJapanese ? "\(start)から、ひと足" : "A short walk from \(start)"
        }
        let body = isJapanese
            ? "\(minutes(suggestion.plan.minutes))。\(destination(for: suggestion.plan))。"
            : "\(minutes(suggestion.plan.minutes)), \(destination(for: suggestion.plan))."
        return NoticeText(title: title, body: body)
    }

    /// 天気を言い切る文面（屋内の案）
    func assertiveIndoor(_ suggestion: Suggestion) -> NoticeText {
        let start = time(suggestion.window.start)
        let reason = suggestion.headlines.first.map { headline($0, level: suggestion.verdict.level) }
        let heading = reason ?? (isJapanese ? "\(start)から、ひと足" : "A short walk from \(start)")
        let what = title(for: suggestion.plan)
        let body = isJapanese
            ? "\(start)から\(minutes(suggestion.plan.minutes))。\(what)。"
            : "\(minutes(suggestion.plan.minutes)) from \(start). \(what)."
        return NoticeText(title: heading, body: body)
    }

    /// 降るかどうか五分五分のとき。1 通に両方の案を書く
    func bothPlans(_ suggestion: Suggestion) -> NoticeText {
        let start = time(suggestion.window.start)
        let title = isJapanese ? "\(start)から、ひと足" : "A short walk from \(start)"
        guard let alternate = suggestion.alternate else {
            return NoticeText(title: title, body: stale(suggestion).body)
        }
        let outdoor = suggestion.plan.activity.isOutdoor ? suggestion.plan : alternate.plan
        let indoor = suggestion.plan.activity.isOutdoor ? alternate.plan : suggestion.plan
        let body = isJapanese
            ? "晴れていれば\(destination(for: outdoor))。降っていたら\(destination(for: indoor))\(minutes(indoor.minutes))。"
            : "If it's dry, \(destination(for: outdoor)). If it rains, \(minutes(indoor.minutes)) \(destination(for: indoor))."
        return NoticeText(title: title, body: body)
    }

    /// 予報が古いとき。天気を書かない
    func stale(_ suggestion: Suggestion, eventTitle: String? = nil) -> NoticeText {
        let length = minutes(suggestion.plan.minutes)
        let title: String
        if let eventTitle, suggestion.slot.previousEventEnd != nil {
            title = isJapanese ? "「\(eventTitle)」のあとに、\(length)あります" : "\(length) free after \(eventTitle)"
        } else if let end = suggestion.slot.previousEventEnd {
            title = isJapanese
                ? "\(time(end)) に終わる予定のあとに、\(length)あります"
                : "\(length) free after your plan ends at \(time(end))"
        } else {
            title = isJapanese
                ? "\(time(suggestion.window.start))から、\(length)のひと足"
                : "A \(length) walk from \(time(suggestion.window.start))"
        }
        let body = isJapanese ? "いまの天気を確かめて、ひと足どうですか。" : "Check the sky, then take a short walk."
        return NoticeText(title: title, body: body)
    }

    /// 前夜のお知らせ
    func evening(_ suggestion: Suggestion) -> NoticeText {
        let title: String
        if suggestion.plan.activity.needsGear {
            title = isJapanese ? "あしたはウェアを持って" : "Pack your gear for tomorrow"
        } else {
            title = isJapanese ? "あしたは歩きやすい靴で" : "Wear comfortable shoes tomorrow"
        }
        let part = dayPart(suggestion.window.start)
        let body = isJapanese
            ? "\(part)に、\(minutes(suggestion.plan.minutes))のひと足があります。"
            : "There's a \(minutes(suggestion.plan.minutes)) walk \(part)."
        return NoticeText(title: title, body: body)
    }

    /// しばらく開いていないときの 1 通。予定にも天気にも触れない
    func nudge() -> NoticeText {
        isJapanese
            ? NoticeText(title: "ひと足、どうですか", body: "開くと、今日の予定と天気で提案します。")
            : NoticeText(title: "Time for a short walk?", body: "Open the app for today's plan and weather.")
    }
}
