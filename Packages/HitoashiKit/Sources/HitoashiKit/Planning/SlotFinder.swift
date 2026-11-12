import Foundation

/// 1 日の予定から、空き時間を見つける（仕様書 §5-4）
public enum SlotFinder {
    /// ひと足が成立する最短の長さ（最短の動き 10 分 + ゆとり 5 分）
    public static let minimumUsableMinutes = 15

    /// - Parameters:
    ///   - day: その日の始まり（現地時刻の 0 時）
    ///   - events: その日の時刻つきの予定（場所の解決まで済んだもの。開始の早い順）
    ///   - dayBase: その日の拠点
    ///   - now: 今日の計算のときだけ渡す。過ぎた時間を切り落とす
    public static func find(
        day: Date,
        events: [DayEvent],
        dayBase: ResolvedPlace?,
        preferences: Preferences,
        calendar: Calendar,
        now: Date? = nil
    ) -> [Slot] {
        let active = DateInterval(
            start: day.addingTimeInterval(TimeInterval(preferences.activeStartMinutes * 60)),
            end: day.addingTimeInterval(TimeInterval(preferences.activeEndMinutes * 60))
        )
        var lunch = DateInterval(
            start: day.addingTimeInterval(TimeInterval(preferences.lunchStartMinutes * 60)),
            end: day.addingTimeInterval(TimeInterval(preferences.lunchEndMinutes * 60))
        )
        // 場所なしの「昼」「ランチ」の予定は、昼休みそのものとして扱う
        if let ownLunch = events.first(where: \.isLunchBreak) {
            lunch = DateInterval(start: ownLunch.start, end: ownLunch.end)
        }
        let busy = splitLongEvents(events.filter { !$0.isLunchBreak }, lunch: lunch, preferences: preferences)

        var drafts: [Draft] = []
        if busy.isEmpty {
            drafts = freeDayFrames(day: day, active: active, base: dayBase)
        } else {
            drafts = gaps(busy: busy, active: active)
            if let standalone = standaloneLunch(lunch: lunch, busy: busy, drafts: drafts, dayBase: dayBase) {
                drafts.append(standalone)
            }
        }

        let earliest = now.map { $0.addingTimeInterval(5 * 60) }
        let frame = Frame(active: active, lunch: lunch, earliest: earliest)
        return drafts
            .compactMap { slot(from: $0, frame: frame, preferences: preferences, calendar: calendar) }
            .sorted { $0.interval.start < $1.interval.start }
    }

    /// その日の枠（動ける時間帯・昼休み・今日なら「いま」）
    struct Frame {
        var active: DateInterval
        var lunch: DateInterval
        var earliest: Date?
    }

    /// 下書きを、動ける時間帯に切りそろえ、種類を決めて空き時間にする。短すぎれば nil
    static func slot(from draft: Draft, frame: Frame, preferences: Preferences, calendar: Calendar) -> Slot? {
        var start = max(draft.start, frame.active.start)
        if let earliest = frame.earliest {
            start = max(start, earliest)
        }
        let end = min(draft.end, frame.active.end)
        guard end > start else {
            return nil
        }
        var interval = DateInterval(start: start, end: end)
        var kind = draft.kind
        var reserved = 0
        // 昼休みと 20 分以上重なる空き時間は「昼休み」として、昼休みの時間の中だけで考える。
        // 昼食の 30 分は長さの条件で、窓の位置は縛らない
        if kind != .freeDay, preferences.allowedSlots.contains(.lunch),
           let overlap = interval.intersection(with: frame.lunch), overlap.duration >= 20 * 60 {
            kind = .lunch
            interval = overlap
            reserved = min(30, max(0, Int(interval.duration / 60) - minimumUsableMinutes))
        }
        guard preferences.allowedSlots.contains(kind) else {
            return nil
        }
        let slot = Slot(
            id: identifier(start: interval.start, kind: kind, calendar: calendar),
            kind: kind,
            interval: interval,
            place: draft.place,
            reservedMinutes: reserved,
            previousEventEnd: draft.previousEnd,
            previousEventTitle: draft.previousTitle,
            nextEventStart: draft.nextStart
        )
        return slot.usableMinutes >= minimumUsableMinutes ? slot : nil
    }

    // MARK: - 中身

    struct Draft {
        var kind: SlotKind
        var start: Date
        var end: Date
        var place: ResolvedPlace
        var previousEnd: Date?
        var previousTitle: String?
        var nextStart: Date?
    }

    /// 次の予定までの移動の余裕（分）。nil は「遠すぎるので、その間には提案しない」
    static func travelMarginMinutes(from: ResolvedPlace?, to: ResolvedPlace?) -> Int? {
        guard let from, let to else {
            return 10
        }
        let meters = from.coordinate.distance(to: to.coordinate)
        if meters <= 500 {
            return 10
        }
        if meters > 50_000 {
            return nil
        }
        return max(30, Int((meters / 1000 * 1.5 + 20).rounded(.up)))
    }

    /// 8 時間を超える時刻つきの予定（研修など）は、昼休みのところだけ空ける
    static func splitLongEvents(_ events: [DayEvent], lunch: DateInterval, preferences: Preferences) -> [DayEvent] {
        events.flatMap { event -> [DayEvent] in
            let isLong = event.end.timeIntervalSince(event.start) > 8 * 3600
            guard isLong, preferences.allowedSlots.contains(.lunch), event.start < lunch.start, lunch.end < event.end else {
                return [event]
            }
            var first = event
            first.end = lunch.start.addingTimeInterval(-5 * 60)
            var second = event
            second.id = event.id + "#2"
            second.start = lunch.end.addingTimeInterval(10 * 60)
            return [first, second]
        }
    }

    static func freeDayFrames(day: Date, active: DateInterval, base: ResolvedPlace?) -> [Draft] {
        guard let base else {
            return []
        }
        // 朝（〜11:00）/ 昼（11:00〜16:00）/ 夕（16:00〜）
        let cuts = [active.start, day.addingTimeInterval(11 * 3600), day.addingTimeInterval(16 * 3600), active.end]
        return zip(cuts, cuts.dropFirst()).compactMap { start, end in
            let from = max(start, active.start)
            let until = min(end, active.end)
            return until > from ? Draft(kind: .freeDay, start: from, end: until, place: base) : nil
        }
    }

    static func gaps(busy: [DayEvent], active: DateInterval) -> [Draft] {
        var drafts: [Draft] = []
        if let first = busy.first, let place = first.place, !first.suppressesSuggestions {
            drafts.append(
                Draft(
                    kind: .beforeFirst,
                    start: first.start.addingTimeInterval(-60 * 60),
                    end: first.start.addingTimeInterval(-10 * 60),
                    place: place,
                    nextStart: first.start
                )
            )
        }
        for (previous, next) in zip(busy, busy.dropFirst()) {
            guard !previous.suppressesSuggestions, !next.suppressesSuggestions else {
                continue
            }
            // 移動の予定のあとは、次の予定の場所で考える（50km の決まりは当てない）
            let place = previous.isTransit ? next.place : previous.place
            let margin = previous.isTransit ? 10 : travelMarginMinutes(from: previous.place, to: next.place)
            guard let place, let margin else {
                continue
            }
            drafts.append(
                Draft(
                    kind: .between,
                    start: previous.end.addingTimeInterval(5 * 60),
                    end: next.start.addingTimeInterval(TimeInterval(-margin * 60)),
                    place: place,
                    previousEnd: previous.end,
                    previousTitle: previous.title,
                    nextStart: next.start
                )
            )
        }
        if let last = busy.last, let place = last.place, !last.suppressesSuggestions, !last.isTransit {
            let start = last.end.addingTimeInterval(5 * 60)
            drafts.append(
                Draft(
                    kind: .afterLast,
                    start: start,
                    end: start.addingTimeInterval(90 * 60),
                    place: place,
                    previousEnd: last.end,
                    previousTitle: last.title
                )
            )
        }
        return drafts
    }

    /// 昼休みが予定から離れているとき（午後にしか予定が無い日など）の、昼休みだけの枠
    static func standaloneLunch(lunch: DateInterval, busy: [DayEvent], drafts: [Draft], dayBase: ResolvedPlace?) -> Draft? {
        let overlapsEvent = busy.contains { $0.start < lunch.end && lunch.start < $0.end }
        let overlapsDraft = drafts.contains { draft in
            guard draft.end > draft.start else {
                return false
            }
            let overlap = DateInterval(start: draft.start, end: draft.end).intersection(with: lunch)
            return (overlap?.duration ?? 0) >= 20 * 60
        }
        guard !overlapsEvent, !overlapsDraft else {
            return nil
        }
        let previous = busy.last { $0.end <= lunch.start }
        let next = busy.first { $0.start >= lunch.end }
        let nearPrevious = previous.flatMap { lunch.start.timeIntervalSince($0.end) <= 120 * 60 ? $0 : nil }
        if nearPrevious?.suppressesSuggestions == true {
            return nil
        }
        guard let place = nearPrevious?.place ?? dayBase else {
            return nil
        }
        var end = lunch.end
        if let next, let margin = travelMarginMinutes(from: place, to: next.place) {
            end = min(end, next.start.addingTimeInterval(TimeInterval(-margin * 60)))
        }
        return Draft(
            kind: .lunch,
            start: lunch.start,
            end: end,
            place: place,
            previousEnd: nearPrevious?.end,
            previousTitle: nearPrevious?.title,
            nextStart: next?.start
        )
    }

    static func identifier(start: Date, kind: SlotKind, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        return String(
            format: "%04d%02d%02d-%02d%02d-%@",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            kind.rawValue
        )
    }
}
