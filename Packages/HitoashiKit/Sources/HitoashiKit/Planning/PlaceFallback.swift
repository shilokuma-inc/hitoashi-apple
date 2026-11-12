import Foundation

/// 場所が決まらなかった予定に、前後の予定かその日の拠点を当てる（仕様書 §5-3 の手順 4・5）
public enum PlaceFallback {
    /// その日の拠点。終日の予定の場所 → 平日は職場・休日は自宅（片方しか無ければそれ）
    public static func dayBase(
        on day: Date,
        allDayPlaces: [ResolvedPlace],
        bases: [BasePlace],
        calendar: Calendar
    ) -> ResolvedPlace? {
        if let trip = allDayPlaces.first {
            return ResolvedPlace(coordinate: trip.coordinate, name: trip.name, source: .dayBase)
        }
        let home = bases.first { $0.kind == .home }
        let work = bases.first { $0.kind == .work }
        let isWeekend = calendar.isDateInWeekend(day)
        let chosen = isWeekend ? (home ?? work) : (work ?? home)
        return (chosen ?? bases.first).map { base in
            ResolvedPlace(coordinate: base.coordinate, name: base.name, source: .base(base.kind))
        }
    }

    /// - Parameters:
    ///   - screens: 予定の id ごとの、場所の文字列のふるい分けの結果
    public static func apply(
        to events: [DayEvent],
        screens: [String: LocationTextScreener.Result],
        dayBase: ResolvedPlace?
    ) -> [DayEvent] {
        var result = events
        let limit: TimeInterval = 120 * 60
        for index in result.indices where result[index].place == nil {
            let screen = screens[result[index].id] ?? .unusable
            let dayBaseIsWork = dayBase.map { $0.source == .base(.work) } ?? false
            // オンライン会議は前後から引き継がない。会議室名は、その日の拠点が職場なら職場
            if screen == .online || (screen == .meetingRoom && dayBaseIsWork) {
                result[index].place = dayBase
                continue
            }
            // 前の予定の終了から、または次の予定の開始まで 120 分以下。前を優先
            let previous = events[..<index].last { $0.place != nil }
            let next = events[(index + 1)...].first { $0.place != nil }
            if let previous, let place = previous.place, result[index].start.timeIntervalSince(previous.end) <= limit {
                result[index].place = ResolvedPlace(coordinate: place.coordinate, name: place.name, source: .inherited)
            } else if let next, let place = next.place, next.start.timeIntervalSince(result[index].end) <= limit {
                result[index].place = ResolvedPlace(coordinate: place.coordinate, name: place.name, source: .inherited)
            } else {
                result[index].place = dayBase
            }
        }
        return result
    }
}
