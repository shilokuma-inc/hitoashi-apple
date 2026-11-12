import Foundation

/// タイムラインの 1 行
public enum TimelineItem: Identifiable, Hashable, Sendable {
    case event(DayEvent)
    case suggestion(Suggestion)

    public var id: String {
        switch self {
        case .event(let event):
            "event-\(event.id)"
        case .suggestion(let suggestion):
            "suggestion-\(suggestion.id)"
        }
    }

    public var start: Date {
        switch self {
        case .event(let event):
            event.start
        case .suggestion(let suggestion):
            suggestion.window.start
        }
    }
}

/// 休む日（候補が 1 つも無く、休むの窓がある日）
public struct RestDay: Hashable, Sendable {
    public var reasons: [VerdictReason]
    /// 重大な警報（原文のまま出す）
    public var alerts: [WeatherAlertInfo]
}

/// 1 日ぶんの計画
public struct DayPlan: Hashable, Sendable {
    /// その日の始まり
    public var day: Date
    /// 今日を 0 とした日の番号
    public var dayIndex: Int
    /// 見出しに出す、その日の天気（拠点か、最初の予定の地点）
    public var forecast: DayForecast?
    /// その日の予報を取得した時刻（いちばん古いもの）
    public var forecastFetchedAt: Date?
    public var events: [DayEvent]
    /// 成立した提案のすべて（休むを除く。開始の早い順）
    public var candidates: [Suggestion]
    /// 今日のひと足
    public var top: Suggestion?
    /// 画面に出す提案（無料は今日のひと足だけ。3 日目以降は出さない）
    public var visible: [Suggestion]
    public var restDay: RestDay?

    /// 「ほかに N つ、ひと足の候補があります」の N
    public var hiddenCount: Int { candidates.count - visible.count }

    /// 予定と、画面に出す提案を、時刻順に並べたもの
    public var items: [TimelineItem] {
        (events.map(TimelineItem.event) + visible.map(TimelineItem.suggestion)).sorted { lhs, rhs in
            (lhs.start, lhs.id) < (rhs.start, rhs.id)
        }
    }
}

/// 1 日の予定・予報・スポットから、その日の計画を作る（仕様書 §5-1、§5-8）
public enum DayPlanner {
    public struct Input: Sendable {
        public var day: Date
        public var dayIndex: Int
        public var events: [DayEvent]
        public var dayBase: ResolvedPlace?
        public var forecasts: [PlaceCell: PlaceForecast]
        public var spots: [PlaceCell: NearbySpots]
        public var preferences: Preferences
        public var isPro: Bool
        public var now: Date
        public var calendar: Calendar
        public var rejectedSpotIDs: Set<String>
        public var recentSpotID: String?
        /// これまでに「やった」空き時間の種類ごとの回数（同じ段階・同じ快適さのときの順に使う）
        public var doneCounts: [SlotKind: Int]

        public init(
            day: Date,
            dayIndex: Int,
            events: [DayEvent],
            dayBase: ResolvedPlace?,
            forecasts: [PlaceCell: PlaceForecast],
            spots: [PlaceCell: NearbySpots],
            preferences: Preferences,
            isPro: Bool,
            now: Date,
            calendar: Calendar,
            rejectedSpotIDs: Set<String> = [],
            recentSpotID: String? = nil,
            doneCounts: [SlotKind: Int] = [:]
        ) {
            self.day = day
            self.dayIndex = dayIndex
            self.events = events
            self.dayBase = dayBase
            self.forecasts = forecasts
            self.spots = spots
            self.preferences = preferences
            self.isPro = isPro
            self.now = now
            self.calendar = calendar
            self.rejectedSpotIDs = rejectedSpotIDs
            self.recentSpotID = recentSpotID
            self.doneCounts = doneCounts
        }
    }

    public static func plan(_ input: Input) -> DayPlan {
        let suggestions = suggestions(for: input)
        let candidates = suggestions.filter { !$0.isRest }
        let top = candidates.max { lhs, rhs in
            rankKey(lhs, doneCounts: input.doneCounts, calendar: input.calendar)
                < rankKey(rhs, doneCounts: input.doneCounts, calendar: input.calendar)
        }
        var visible: [Suggestion] = []
        if input.isPro {
            visible = candidates
        } else if input.dayIndex <= 1, let top {
            visible = [top]
        }
        var restDay: RestDay?
        if candidates.isEmpty, let rest = suggestions.first(where: \.isRest) {
            let alerts = input.forecasts[rest.slot.place.cell]?.alerts.filter { $0.severity >= .severe } ?? []
            restDay = RestDay(reasons: rest.verdict.reasons, alerts: alerts)
        }
        let headerCell = input.dayBase?.cell ?? input.events.compactMap(\.place).first?.cell
        let headerForecast = headerCell.flatMap { input.forecasts[$0] }
        return DayPlan(
            day: input.day,
            dayIndex: input.dayIndex,
            forecast: headerForecast?.day(containing: input.day.addingTimeInterval(12 * 3600), calendar: input.calendar),
            forecastFetchedAt: input.forecasts.values.map(\.fetchedAt).min(),
            events: input.events,
            candidates: candidates,
            top: top,
            visible: visible,
            restDay: restDay
        )
    }

    /// 空き時間ごとの提案（休むを含む。開始の早い順）
    static func suggestions(for input: Input) -> [Suggestion] {
        let slots = SlotFinder.find(
            day: input.day,
            events: input.events,
            dayBase: input.dayBase,
            preferences: input.preferences,
            calendar: input.calendar,
            now: input.dayIndex == 0 ? input.now : nil
        )
        var suggestions: [Suggestion] = []
        var lastSpotID = input.recentSpotID
        for slot in slots {
            guard let forecast = input.forecasts[slot.place.cell] else {
                continue
            }
            // 重大な警報は、取得した当日にだけ当てる。同じ日に同じ場所を続けて先頭にしない
            let context = SuggestionEngine.Context(
                calendar: input.calendar,
                rejectedSpotIDs: input.rejectedSpotIDs,
                recentSpotID: lastSpotID,
                appliesSevereAlerts: input.calendar.isDate(forecast.fetchedAt, inSameDayAs: input.day)
            )
            if let suggestion = SuggestionEngine.suggest(
                slot: slot,
                forecast: forecast,
                spots: input.spots[slot.place.cell] ?? .empty,
                preferences: input.preferences,
                context: context
            ) {
                suggestions.append(suggestion)
                lastSpotID = suggestion.plan.spot?.id ?? lastSpotID
            }
        }
        return suggestions
    }

    /// 今日のひと足の順位（仕様書 §5-8）。① 段階 ② 快適さ（10 点刻み）③ 空き時間の種類 ④ 早い開始
    static func rankKey(_ suggestion: Suggestion, doneCounts: [SlotKind: Int], calendar: Calendar) -> RankKey {
        let level: Int
        if suggestion.plan.activity == .onTheSpot {
            level = 1
        } else if suggestion.verdict.level == .great {
            level = 3
        } else {
            level = 2
        }
        let order: [SlotKind] = [.lunch, .afterLast, .between, .freeDay, .beforeFirst]
        let kindRank = order.count - (order.firstIndex(of: suggestion.slot.kind) ?? order.count)
        // 同じ条件なら早い開始。予定のない日だけは、昼（13 時）に近いほうを先にする（休日の早朝を選ばない）
        var earliness = -suggestion.window.start.timeIntervalSinceReferenceDate
        if suggestion.slot.kind == .freeDay {
            let secondsOfDay = suggestion.window.start.timeIntervalSince(calendar.startOfDay(for: suggestion.window.start))
            earliness = -abs(secondsOfDay - 13 * 3600)
        }
        return RankKey(
            level: level,
            comfortBand: Int(suggestion.comfort / 10),
            done: doneCounts[suggestion.slot.kind] ?? 0,
            kind: kindRank,
            earliness: earliness
        )
    }

    struct RankKey: Comparable {
        var level: Int
        var comfortBand: Int
        var done: Int
        var kind: Int
        var earliness: Double

        static func < (lhs: RankKey, rhs: RankKey) -> Bool {
            (lhs.level, lhs.comfortBand, lhs.done, lhs.kind, lhs.earliness)
                < (rhs.level, rhs.comfortBand, rhs.done, rhs.kind, rhs.earliness)
        }
    }
}

/// 今週の歩きどき（Pro）。7 日ぶんの外の窓を、快適さの順に並べて上位を出す（1 日 1 つ）
public enum WeekOutlook {
    public static func best(in plans: [DayPlan], limit: Int = 3) -> [Suggestion] {
        let perDay: [Suggestion] = plans.prefix(7).compactMap { plan in
            plan.candidates
                .filter { $0.plan.activity.isOutdoor }
                .max { ($0.verdict.level, $0.comfort) < ($1.verdict.level, $1.comfort) }
        }
        let great = perDay.filter { $0.verdict.level == .great }
        // 「外がおすすめ」が足りなければ、「外は気をつけて」まで広げる
        let pool = great.count >= limit ? great : perDay
        return Array(
            pool.sorted { lhs, rhs in
                (lhs.verdict.level, lhs.comfort, -lhs.window.start.timeIntervalSinceReferenceDate)
                    > (rhs.verdict.level, rhs.comfort, -rhs.window.start.timeIntervalSinceReferenceDate)
            }
            .prefix(limit)
        )
    }
}
