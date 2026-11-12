import Foundation

/// 予定・拠点・予報・スポットから、今日から数日ぶんの計画を作る（仕様書 §5-1 の流れを通す入口）
public enum WeekPlanner {
    public struct Input: Sendable {
        /// カレンダーから読んだ予定（対象のカレンダーのもの）
        public var events: [PlanEvent]
        /// 予定の id ごとの、解決した場所（仕様書 §5-3 の手順 1〜3 の結果）
        public var places: [String: ResolvedPlace]
        public var bases: [BasePlace]
        public var forecasts: [PlaceCell: PlaceForecast]
        public var spots: [PlaceCell: NearbySpots]
        public var preferences: Preferences
        public var isPro: Bool
        public var now: Date
        public var calendar: Calendar
        public var dayCount: Int
        public var rejectedSpotIDs: Set<String>
        public var recentSpotID: String?
        public var doneCounts: [SlotKind: Int]

        public init(
            events: [PlanEvent],
            places: [String: ResolvedPlace],
            bases: [BasePlace],
            forecasts: [PlaceCell: PlaceForecast] = [:],
            spots: [PlaceCell: NearbySpots] = [:],
            preferences: Preferences = Preferences(),
            isPro: Bool = false,
            now: Date,
            calendar: Calendar,
            dayCount: Int = 10,
            rejectedSpotIDs: Set<String> = [],
            recentSpotID: String? = nil,
            doneCounts: [SlotKind: Int] = [:]
        ) {
            self.events = events
            self.places = places
            self.bases = bases
            self.forecasts = forecasts
            self.spots = spots
            self.preferences = preferences
            self.isPro = isPro
            self.now = now
            self.calendar = calendar
            self.dayCount = dayCount
            self.rejectedSpotIDs = rejectedSpotIDs
            self.recentSpotID = recentSpotID
            self.doneCounts = doneCounts
        }
    }

    /// 1 日ぶんの、場所まで決めた予定と拠点
    struct ResolvedDay {
        var day: Date
        var index: Int
        var events: [DayEvent]
        var base: ResolvedPlace?
    }

    public static func plans(_ input: Input) -> [DayPlan] {
        resolvedDays(input).map { day in
            DayPlanner.plan(
                DayPlanner.Input(
                    day: day.day,
                    dayIndex: day.index,
                    events: day.events,
                    dayBase: day.base,
                    forecasts: input.forecasts,
                    spots: input.spots,
                    preferences: input.preferences,
                    isPro: input.isPro,
                    now: input.now,
                    calendar: input.calendar,
                    rejectedSpotIDs: input.rejectedSpotIDs,
                    recentSpotID: input.recentSpotID,
                    doneCounts: input.doneCounts
                )
            )
        }
    }

    /// 天気とスポットを取りに行く場所（地点ごとに 1 つ。今日に近い順）
    public static func requiredPlaces(_ input: Input) -> [ResolvedPlace] {
        var seen: Set<PlaceCell> = []
        var result: [ResolvedPlace] = []
        for day in resolvedDays(input) {
            for place in [day.base].compactMap(\.self) + day.events.compactMap(\.place) where seen.insert(place.cell).inserted {
                result.append(place)
            }
        }
        return result
    }

    /// スポットを探しに行く場所（細かい升目ごとに 1 つ）。先の日までは探さない
    public static func requiredSpotPlaces(_ input: Input, dayLimit: Int = 3) -> [ResolvedPlace] {
        var seen: Set<PlaceCell> = []
        var result: [ResolvedPlace] = []
        for day in resolvedDays(input).prefix(dayLimit) {
            for place in [day.base].compactMap(\.self) + day.events.compactMap(\.place)
            where seen.insert(PlaceCell.fine(place.coordinate)).inserted {
                result.append(place)
            }
        }
        return result
    }

    static func resolvedDays(_ input: Input) -> [ResolvedDay] {
        let normalized = EventNormalizer.normalize(input.events, places: input.places, preferences: input.preferences)
        var screens: [String: LocationTextScreener.Result] = [:]
        for event in input.events {
            screens[event.id] = LocationTextScreener.screen(event.locationText)
        }
        let today = input.calendar.startOfDay(for: input.now)
        return (0..<input.dayCount).compactMap { index -> ResolvedDay? in
            guard let day = input.calendar.date(byAdding: .day, value: index, to: today),
                  let next = input.calendar.date(byAdding: .day, value: 1, to: day) else {
                return nil
            }
            let timed = normalized.timed.filter { $0.start >= day && $0.start < next }
            // 終日・複数日の予定に場所があれば、その日の拠点にする
            let trips = normalized.allDay
                .filter { $0.start < next && $0.end > day }
                .compactMap { input.places[$0.id] }
            let base = PlaceFallback.dayBase(on: day, allDayPlaces: trips, bases: input.bases, calendar: input.calendar)
            let events = PlaceFallback.apply(to: timed, screens: screens, dayBase: base)
            return ResolvedDay(day: day, index: index, events: events, base: base)
        }
    }
}
