import Foundation

/// 空き時間 1 つから、ひと足（何を・どこで・何分・いつから）と代わりの案を決める（仕様書 §5-5〜§5-7）
public enum SuggestionEngine {
    public struct Context: Sendable {
        public var calendar: Calendar
        /// 「この場所は出さない」とされたスポット
        public var rejectedSpotIDs: Set<String>
        /// 直近に出した・行ったスポット（続けて先頭にしない）
        public var recentSpotID: String?
        /// 重大な警報をこの日に当てるか（取得した当日だけ。翌日には持ち越さない）
        public var appliesSevereAlerts: Bool

        public init(
            calendar: Calendar,
            rejectedSpotIDs: Set<String> = [],
            recentSpotID: String? = nil,
            appliesSevereAlerts: Bool = false
        ) {
            self.calendar = calendar
            self.rejectedSpotIDs = rejectedSpotIDs
            self.recentSpotID = recentSpotID
            self.appliesSevereAlerts = appliesSevereAlerts
        }
    }

    public static func suggest(
        slot: Slot,
        forecast: PlaceForecast,
        spots: NearbySpots,
        preferences: Preferences,
        context: Context
    ) -> Suggestion? {
        // 動きに使える長さ（5 分のゆとりを残し、5 分単位に切り捨てる）
        let budget = (slot.usableMinutes - 5) / 5 * 5
        guard budget >= Activity.walk.minimumMinutes else {
            return nil
        }
        let target = max(Activity.walk.minimumMinutes, min(preferences.durationMinutes, budget) / 5 * 5)
        guard let first = WindowPicker.pick(in: slot.interval, minutes: target, forecast: forecast) else {
            return nil
        }
        let alerts = context.appliesSevereAlerts ? forecast.alerts.filter { $0.severity >= .severe } : []
        let day = forecast.day(containing: first.interval.start, calendar: context.calendar)
        let dark = isDark(first.interval, forecast: forecast, day: day)
        let verdict = WeatherAssessor.assess(hours: forecast.hours(overlapping: first.interval), severeAlerts: alerts, isDark: dark)
        // スポットは、この空き時間の場所から見て近い順に並べ、同じ名前は近いほうだけにする
        let nearby = spots.arranged(from: slot.place.coordinate)
        let builder = PlanBuilder(slot: slot, spots: nearby, preferences: preferences, context: context, budget: budget, target: target)

        let decision = decide(
            verdict: verdict,
            isDark: dark,
            first: first,
            builder: builder,
            forecast: forecast
        )
        let hours = forecast.hours(overlapping: decision.window.interval)
        let headlines = HeadlineBuilder(
            verdict: verdict,
            plan: decision.choice.plan,
            window: decision.window.interval,
            forecast: forecast,
            day: day,
            calendar: context.calendar
        )
        .build()
        return Suggestion(
            id: slot.id,
            slot: slot,
            plan: decision.choice.plan,
            window: decision.window.interval,
            verdict: verdict,
            comfort: decision.window.comfort,
            headlines: headlines,
            alternate: decision.alternate,
            otherSpots: decision.choice.others,
            forecastFetchedAt: forecast.fetchedAt,
            maxPrecipitationChance: hours.map(\.precipitationChance).max() ?? 0
        )
    }

    struct Decision {
        var choice: PlanBuilder.Choice
        var alternate: AlternatePlan?
        var window: WindowPicker.Window
    }

    /// 判定の段階ごとに、案・代わりの案・動く時間帯を決める
    static func decide(
        verdict: Verdict,
        isDark: Bool,
        first: WindowPicker.Window,
        builder: PlanBuilder,
        forecast: PlaceForecast
    ) -> Decision {
        let slot = builder.slot
        var decision: Decision
        switch verdict.level {
        case .great, .caution:
            let choice = builder.outdoor(level: verdict.level, isDark: isDark)
            // 外の案は、快適さで選んだ窓の始まりをそのまま使う
            let length = TimeInterval(choice.plan.windowMinutes * 60)
            let fits = first.interval.start.addingTimeInterval(length) <= slot.interval.end
            let interval = fits
                ? DateInterval(start: first.interval.start, duration: length)
                : DateInterval(start: slot.interval.end.addingTimeInterval(-length), end: slot.interval.end)
            decision = Decision(
                choice: choice,
                alternate: AlternatePlan(label: .ifRain, plan: builder.indoor(maxWalkMinutes: 5).plan),
                window: WindowPicker.Window(
                    interval: interval,
                    comfort: WindowPicker.comfort(of: interval, forecast: forecast) ?? first.comfort
                )
            )
        case .indoor:
            let choice = builder.indoor(maxWalkMinutes: 5)
            // 屋内の案は、空き時間のいちばん早いところ
            let window = WindowPicker.pick(in: slot.interval, minutes: choice.plan.windowMinutes, forecast: forecast, preferEarliest: true)
            decision = Decision(
                choice: choice,
                alternate: AlternatePlan(label: .ifClear, plan: builder.outdoor(level: .great, isDark: isDark).plan),
                window: window ?? first
            )
        case .rest:
            let window = WindowPicker.pick(in: slot.interval, minutes: 5, forecast: forecast, preferEarliest: true)
            decision = Decision(
                choice: PlanBuilder.Choice(plan: StepPlan(activity: .onTheSpot, minutes: 5), others: []),
                alternate: nil,
                window: window ?? first
            )
        }
        if decision.choice.plan.windowMinutes > slot.usableMinutes {
            decision.window = first
        }
        return decision
    }

    /// 窓が暗い時間にかかるか（日没の 30 分後以降、日の出の 30 分前より前、または予報が「夜」）
    static func isDark(_ window: DateInterval, forecast: PlaceForecast, day: DayForecast?) -> Bool {
        if let sunset = day?.sunset, window.end > sunset.addingTimeInterval(30 * 60) {
            return true
        }
        if let sunrise = day?.sunrise, window.start < sunrise.addingTimeInterval(-30 * 60) {
            return true
        }
        if day?.sunset == nil {
            return forecast.hours(overlapping: window).contains { !$0.isDaylight }
        }
        return false
    }
}

/// スポットと設定から、外の案・屋内の案を組み立てる
struct PlanBuilder {
    struct Choice {
        var plan: StepPlan
        var others: [Spot]
    }

    var slot: Slot
    var spots: NearbySpots
    var preferences: Preferences
    var context: SuggestionEngine.Context
    /// 動きに使える長さ（分）
    var budget: Int
    /// 設定の長さを、空き時間に合わせたもの（分）
    var target: Int

    private var origin: Coordinate { slot.place.coordinate }

    /// 支度のいる動き（走る・ジム）を出してよい空き時間か
    private func allowsGear(minimumSlotMinutes: Int) -> Bool {
        let longEnough = Int(slot.interval.duration / 60) >= minimumSlotMinutes
        return longEnough && [.afterLast, .freeDay, .beforeFirst].contains(slot.kind)
    }

    private func usable(_ list: [Spot]) -> [Spot] {
        var result = list.filter { !context.rejectedSpotIDs.contains($0.id) }
        // 直近と同じ場所を先頭にしない
        if result.count > 1, result.first?.id == context.recentSpotID {
            result.append(result.removeFirst())
        }
        return result
    }

    private func plan(_ activity: Activity, minutes: Int, spot: Spot, route: WalkRoute) -> StepPlan {
        StepPlan(
            activity: activity,
            minutes: minutes,
            spot: spot,
            route: route,
            walkMinutesToSpot: origin.walkingMinutes(to: spot.coordinate),
            distanceMeters: origin.distance(to: spot.coordinate)
        )
    }

    func outdoor(level: VerdictLevel, isDark: Bool) -> Choice {
        // 外は気をつけて、のときは歩くだけ・最長 20 分
        let limit = level == .caution ? min(target, 20) : target
        if level == .great, !isDark, preferences.jogEnabled, allowsGear(minimumSlotMinutes: 60) {
            let tracks = usable(spots.tracks.isEmpty ? spots.parks : spots.tracks)
            let minutes = max(Activity.jog.minimumMinutes, limit)
            if let track = tracks.first(where: { minutes + origin.walkingMinutes(to: $0.coordinate) * 2 <= budget }) {
                return Choice(plan: plan(.jog, minutes: minutes, spot: track, route: .roundTrip), others: others(tracks, except: track))
            }
        }
        if isDark {
            // 暗い時間は公園を行き先にせず、駅までの道にする
            if preferences.afterDark == .indoor {
                return indoor(maxWalkMinutes: 5)
            }
            let stations = usable(spots.stations)
            let reachable = stations
                .map { (spot: $0, minutes: origin.walkingMinutes(to: $0.coordinate)) }
                .filter { $0.minutes >= 8 && $0.minutes <= limit }
                .max { $0.minutes < $1.minutes }
            if let reachable {
                let minutes = max(Activity.walk.minimumMinutes, reachable.minutes)
                return Choice(plan: plan(.walk, minutes: minutes, spot: reachable.spot, route: .oneWay), others: [])
            }
            return Choice(plan: StepPlan(activity: .walk, minutes: limit, route: .loop), others: [])
        }
        let parks = usable(spots.parks)
        // 往復が使える長さに収まる公園のうち、設定の長さにいちばん近いもの
        let fitting = parks.filter { origin.walkingMinutes(to: $0.coordinate) * 2 <= min(budget, max(limit, 10) + 10) }
        let sorted = fitting.enumerated().sorted { lhs, rhs in
            let left = abs(origin.walkingMinutes(to: lhs.element.coordinate) * 2 - limit)
            let right = abs(origin.walkingMinutes(to: rhs.element.coordinate) * 2 - limit)
            return (left, lhs.offset) < (right, rhs.offset)
        }
        let ordered = sorted.map(\.element)
        guard let park = usable(ordered).first else {
            return Choice(plan: StepPlan(activity: .walk, minutes: limit, route: .loop), others: [])
        }
        let roundTrip = origin.walkingMinutes(to: park.coordinate) * 2
        let minutes = min(budget, max(limit, (roundTrip + 4) / 5 * 5))
        return Choice(plan: plan(.walk, minutes: minutes, spot: park, route: .roundTrip), others: others(ordered, except: park))
    }

    /// - Parameter maxWalkMinutes: 屋内の施設まで、外を歩かせてよい片道の分（判定が屋内のときは 5 分）
    func indoor(maxWalkMinutes: Int) -> Choice {
        if preferences.gymEnabled, allowsGear(minimumSlotMinutes: 75) {
            let gyms = usable(spots.gyms)
            let minutes = max(Activity.gym.minimumMinutes, target)
            if let gym = gyms.first(where: { minutes + origin.walkingMinutes(to: $0.coordinate) * 2 <= slot.usableMinutes }) {
                return Choice(plan: plan(.gym, minutes: minutes, spot: gym, route: .roundTrip), others: others(gyms, except: gym))
            }
        }
        if preferences.coveredWalkEnabled {
            let covered = usable(spots.covered).filter { origin.walkingMinutes(to: $0.coordinate) <= maxWalkMinutes }
            if let place = covered.first {
                let walk = origin.walkingMinutes(to: place.coordinate)
                let minutes = max(Activity.coveredWalk.minimumMinutes, min(target, (slot.usableMinutes - walk * 2) / 5 * 5))
                if minutes + walk * 2 <= slot.usableMinutes {
                    return Choice(
                        plan: plan(.coveredWalk, minutes: minutes, spot: place, route: .roundTrip),
                        others: others(covered, except: place)
                    )
                }
            }
        }
        return Choice(plan: StepPlan(activity: .onTheSpot, minutes: 5), others: [])
    }

    private func others(_ list: [Spot], except chosen: Spot) -> [Spot] {
        Array(list.filter { $0.id != chosen.id }.prefix(2))
    }
}
