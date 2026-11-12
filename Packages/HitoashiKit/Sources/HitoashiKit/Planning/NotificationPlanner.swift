import Foundation

/// 知らせると確定した日の控え（仕様書 §5-9）。週の回数は、これで数える
public struct NoticeLedger: Hashable, Sendable, Codable {
    /// 確定した日（"2026-11-12" の形）
    public var confirmedDays: Set<String>

    public init(confirmedDays: Set<String> = []) {
        self.confirmedDays = confirmedDays
    }
}

/// 予約する通知
public struct PlannedNotice: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// 当日のお知らせ
        case day
        /// 前夜のお知らせ
        case evening
        /// しばらく開いていないときの 1 通
        case nudge
    }

    public var id: String
    public var kind: Kind
    public var fireDate: Date
    public var title: String
    public var body: String
    public var suggestionID: String?

    public init(id: String, kind: Kind, fireDate: Date, title: String, body: String, suggestionID: String? = nil) {
        self.id = id
        self.kind = kind
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.suggestionID = suggestionID
    }
}

/// 通知の計画（仕様書 §5-9）。
/// 知らせる日を決め（今日と明日だけ確定する）、48 時間先までの通知を作る。
/// 天気を言い切るのは、発火の時刻が予報の取得から 6 時間以内のときだけ
public enum NotificationPlanner {
    public struct Output: Sendable {
        public var notices: [PlannedNotice]
        public var ledger: NoticeLedger
    }

    public struct Input: Sendable {
        /// 今日からの計画（今日が先頭）
        public var plans: [DayPlan]
        public var ledger: NoticeLedger
        public var preferences: Preferences
        public var now: Date
        public var calendar: Calendar
        public var phrasebook: Phrasebook

        public init(
            plans: [DayPlan],
            ledger: NoticeLedger,
            preferences: Preferences,
            now: Date,
            calendar: Calendar,
            phrasebook: Phrasebook
        ) {
            self.plans = plans
            self.ledger = ledger
            self.preferences = preferences
            self.now = now
            self.calendar = calendar
            self.phrasebook = phrasebook
        }
    }

    public static func plan(_ input: Input) -> Output {
        var ledger = input.ledger
        var notices: [PlannedNotice] = []
        for plan in input.plans.prefix(2) {
            let key = dayKey(plan.day, calendar: input.calendar)
            guard let top = eligibleTop(plan) else {
                // 休む・「その場で」だけに落ちたら、通知をやめて回数を戻す
                ledger.confirmedDays.remove(key)
                continue
            }
            let confirms = shouldConfirm(plan, among: input.plans, ledger: ledger, preferences: input.preferences, calendar: input.calendar)
            if !ledger.confirmedDays.contains(key), confirms {
                ledger.confirmedDays.insert(key)
            }
            if ledger.confirmedDays.contains(key) {
                notices += self.notices(for: top, in: plan, key: key, input: input)
            }
        }
        if input.preferences.dayNoticeEnabled, let today = input.plans.first?.day {
            // 最後の更新から 3 日後の昼に、予定にも天気にも触れない 1 通。更新のたびに先へ送る
            let text = input.phrasebook.nudge()
            let fire = today.addingTimeInterval(3 * 24 * 3600 + 12 * 3600)
            notices.append(PlannedNotice(id: "nudge", kind: .nudge, fireDate: fire, title: text.title, body: text.body))
        }
        // 古い控えは捨てる（2 週間より前）
        let cutoff = dayKey(input.now.addingTimeInterval(-14 * 24 * 3600), calendar: input.calendar)
        ledger.confirmedDays = ledger.confirmedDays.filter { $0 >= cutoff }
        return Output(notices: notices.sorted { $0.fireDate < $1.fireDate }, ledger: ledger)
    }

    /// 確定した日の通知（当日のお知らせと、要るときは前夜のお知らせ）。48 時間先までに収まるものだけ
    static func notices(for top: Suggestion, in plan: DayPlan, key: String, input: Input) -> [PlannedNotice] {
        var result: [PlannedNotice] = []
        let preferences = input.preferences
        let horizon = input.now.addingTimeInterval(48 * 3600)
        // 8:00 より前に始まる窓は、当日は鳴らさない
        let startsEarly = minutesOfDay(top.window.start, calendar: input.calendar) < 8 * 60
        let fire = fireDate(for: top)
        if preferences.dayNoticeEnabled, !startsEarly, fire > input.now, fire <= horizon {
            let text = dayText(top, fire: fire, preferences: preferences, phrasebook: input.phrasebook)
            result.append(
                PlannedNotice(id: "day-\(key)", kind: .day, fireDate: fire, title: text.title, body: text.body, suggestionID: top.id)
            )
        }
        let evening = plan.day.addingTimeInterval(TimeInterval(-24 * 3600 + preferences.eveningNoticeMinutes * 60))
        let wanted = plan.dayIndex >= 1 && wantsEvening(top, startsEarly: startsEarly, preferences: preferences)
        if wanted, evening > input.now, evening <= horizon {
            let text = input.phrasebook.evening(top)
            result.append(
                PlannedNotice(
                    id: "evening-\(key)",
                    kind: .evening,
                    fireDate: evening,
                    title: text.title,
                    body: text.body,
                    suggestionID: top.id
                )
            )
        }
        return result
    }

    // MARK: - 知らせる日

    /// 通知の対象になる「今日のひと足」。「その場で」だけの日は通知しない
    static func eligibleTop(_ plan: DayPlan) -> Suggestion? {
        guard let top = plan.top, top.plan.activity != .onTheSpot else {
            return nil
        }
        return top
    }

    /// その日を「知らせる日」に確定するか。
    /// R = 週の回数 − 今週の確定数、D = その日を含む今週の残り日数。
    /// R = 0 なら知らせない。R ≥ D なら確定。それ以外は、その日が今週の残りの日の上位 R に入るとき
    static func shouldConfirm(
        _ plan: DayPlan,
        among plans: [DayPlan],
        ledger: NoticeLedger,
        preferences: Preferences,
        calendar: Calendar
    ) -> Bool {
        if preferences.weeklyTarget == .everyday {
            return true
        }
        let week = weekDays(containing: plan.day, calendar: calendar)
        let key = dayKey(plan.day, calendar: calendar)
        let confirmed = week.filter { $0 != key && ledger.confirmedDays.contains($0) }.count
        let remaining = preferences.weeklyTarget.rawValue - confirmed
        guard remaining > 0 else {
            return false
        }
        let rest = week.filter { $0 >= key }
        if remaining >= rest.count {
            return true
        }
        guard let own = eligibleTop(plan) else {
            return false
        }
        // 今週の残りの日で、この日より良い日がいくつあるか（同じなら早い日が先）
        let better = plans.filter { other in
            let otherKey = dayKey(other.day, calendar: calendar)
            guard otherKey > key, rest.contains(otherKey), !ledger.confirmedDays.contains(otherKey),
                  let top = eligibleTop(other) else {
                return false
            }
            return rank(top) > rank(own)
        }
        return better.count < remaining
    }

    static func rank(_ suggestion: Suggestion) -> Int {
        (suggestion.verdict.level == .great ? 3 : 2) * 100 + Int(suggestion.comfort / 10)
    }

    // MARK: - 時刻と文面

    /// 予定のあとの空き時間は「予定の終了 + 5 分」。それ以外は窓の 10 分前
    static func fireDate(for suggestion: Suggestion) -> Date {
        if let end = suggestion.slot.previousEventEnd, [.between, .afterLast].contains(suggestion.slot.kind) {
            return min(end.addingTimeInterval(5 * 60), suggestion.window.start)
        }
        return suggestion.window.start.addingTimeInterval(-10 * 60)
    }

    static func dayText(
        _ suggestion: Suggestion,
        fire: Date,
        preferences: Preferences,
        phrasebook: Phrasebook
    ) -> Phrasebook.NoticeText {
        let fresh = fire.timeIntervalSince(suggestion.forecastFetchedAt) <= 6 * 3600
        guard fresh else {
            let title = preferences.includesEventTitleInNotice ? suggestion.slot.previousEventTitle : nil
            return phrasebook.stale(suggestion, eventTitle: title)
        }
        let chance = suggestion.maxPrecipitationChance
        if suggestion.plan.activity.isOutdoor {
            return chance < 0.3 ? phrasebook.assertiveOutdoor(suggestion) : phrasebook.bothPlans(suggestion)
        }
        // 屋内の案: 理由が降水なら 60% 以上か雨の天気のとき、降水以外ならいつでも言い切る
        let wet = suggestion.verdict.reasons.contains { reason in
            if case .wetWeather = reason {
                return true
            }
            return false
        }
        if !suggestion.verdict.isIndoorBecauseOfRain || chance >= 0.6 || wet {
            return phrasebook.assertiveIndoor(suggestion)
        }
        return phrasebook.bothPlans(suggestion)
    }

    static func wantsEvening(_ suggestion: Suggestion, startsEarly: Bool, preferences: Preferences) -> Bool {
        switch preferences.eveningNotice {
        case .never:
            false
        case .always:
            true
        case .whenPreparationNeeded:
            suggestion.plan.activity.needsGear || startsEarly || suggestion.slot.kind == .beforeFirst
        }
    }

    // MARK: - 暦

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// その日を含む週（月〜日）の日の一覧
    static func weekDays(containing day: Date, calendar: Calendar) -> [String] {
        let weekday = calendar.component(.weekday, from: day)
        // 日曜 = 1。月曜を週の始まりにする
        let fromMonday = (weekday + 5) % 7
        let start = calendar.startOfDay(for: day)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - fromMonday, to: start).map { dayKey($0, calendar: calendar) }
        }
    }

    static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
