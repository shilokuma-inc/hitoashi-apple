import Foundation

/// 読んだ予定を、1 日の計算に使う形に整える（仕様書 §5-2）
public enum EventNormalizer {
    public struct Output: Sendable {
        /// 時刻つきの予定（重なりをまとめ、開始の早い順）
        public var timed: [DayEvent]
        /// 終日・複数日の予定（空き時間の計算には使わない。場所があれば、その日の拠点になる）
        public var allDay: [PlanEvent]
    }

    private static let transitWords = ["移動", "新幹線", "のぞみ", "フライト", "flight"]
    private static let lunchWords = ["昼", "ランチ", "lunch"]

    /// - Parameter places: 予定の id ごとの、解決した場所（仕様書 §5-3 の手順 1〜3 の結果）
    public static func normalize(
        _ events: [PlanEvent],
        places: [String: ResolvedPlace],
        preferences: Preferences
    ) -> Output {
        var timed: [DayEvent] = []
        var allDay: [PlanEvent] = []
        for event in events where !event.isCanceled && !event.isDeclined {
            let length = event.end.timeIntervalSince(event.start)
            if event.isAllDay || length >= 24 * 3600 {
                allDay.append(event)
                continue
            }
            guard length >= 15 * 60 else {
                continue
            }
            let hasLocation = !(event.locationText ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            timed.append(
                DayEvent(
                    id: event.id,
                    title: event.title,
                    start: event.start,
                    end: event.end,
                    locationText: event.locationText,
                    place: places[event.id],
                    suppressesSuggestions: matches(event.title, words: preferences.excludedTitleWords),
                    isTransit: isTransit(event.title),
                    isLunchBreak: !hasLocation && event.coordinate == nil && matches(event.title, words: lunchWords)
                )
            )
        }
        timed.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        return Output(timed: merge(timed), allDay: allDay)
    }

    static func matches(_ title: String, words: [String]) -> Bool {
        let lower = title.lowercased()
        return words.contains { !$0.isEmpty && lower.contains($0.lowercased()) }
    }

    /// 移動の予定か。「便」は数字に続くときだけ（「123 便」。「郵便局」に当てない）
    static func isTransit(_ title: String) -> Bool {
        if matches(title, words: transitWords) {
            return true
        }
        let characters = Array(title)
        for (index, character) in characters.enumerated() where character == "便" {
            var cursor = index - 1
            while cursor >= 0, characters[cursor] == " " {
                cursor -= 1
            }
            if cursor >= 0, characters[cursor].isNumber {
                return true
            }
        }
        return false
    }

    /// 重なる予定を 1 本にまとめる。場所は最後に終わる予定のもの
    static func merge(_ sorted: [DayEvent]) -> [DayEvent] {
        var result: [DayEvent] = []
        for event in sorted {
            guard var last = result.last, event.start < last.end, !last.isLunchBreak, !event.isLunchBreak else {
                result.append(event)
                continue
            }
            if event.end >= last.end {
                last.end = event.end
                last.place = event.place ?? last.place
                last.locationText = event.locationText ?? last.locationText
                last.isTransit = event.isTransit
            }
            last.suppressesSuggestions = last.suppressesSuggestions || event.suppressesSuggestions
            result[result.count - 1] = last
        }
        return result
    }
}
