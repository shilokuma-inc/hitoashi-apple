//
//  AppModel.swift
//  Hitoashi
//
//  画面が見る状態（10 日ぶんの計画・設定・購入の状態）と、更新の流れ（仕様書 §5-1）。
//

import Foundation
import HitoashiKit
import Observation

/// タブ
enum AppTab: Hashable {
    case today
    case log
    case settings
}

@Observable
final class AppModel {
    let environment: AppEnvironment

    /// 今日から 10 日ぶんの計画
    private(set) var plans: [DayPlan] = []
    /// いま表示している日（今日 = 0）
    var selectedDay = 0
    private(set) var snapshot: WorldSnapshot = .empty
    private(set) var refreshedAt: Date?
    private(set) var isRefreshing = false

    var preferences: Preferences {
        didSet {
            environment.settings.preferences = preferences
            replan()
        }
    }

    var bases: [BasePlace] {
        didSet { environment.settings.bases = bases }
    }

    /// Pro（サブスク）が有効か
    var isPro = false {
        didSet { replan() }
    }

    /// 利用者が選び直した案（「これにする」）。提案の id ごと
    private var chosenPlans: [String: StepPlan] = [:]
    /// 記録を変えたら画面を更新するための印
    private(set) var logRevision = 0

    var showsPaywall = false
    var hasOnboarded: Bool {
        didSet { environment.settings.hasOnboarded = hasOnboarded }
    }

    /// いま開いているタブ
    var selectedTab = AppTab.today
    /// 開いてほしいひと足（通知や撮影モードから）。きょうの画面が受け取ったら nil に戻す
    var routeToOpen: String?
    /// この端末で通知を出すか（「この時刻に知らせる」を押した端末だけ）
    private(set) var noticesEnabled: Bool

    init(environment: AppEnvironment) {
        self.environment = environment
        preferences = environment.settings.preferences
        bases = environment.settings.bases
        hasOnboarded = environment.settings.hasOnboarded
        noticesEnabled = environment.settings.noticesEnabled
    }

    var now: Date { environment.clock() }
    var calendar: Calendar { environment.calendar }
    var isDemo: Bool { snapshot.isDemo }

    /// 判定や提案を文にする部品（言語と単位は端末の設定に従う）
    var book: Phrasebook {
        let locale = Locale.current
        let isJapanese = locale.language.languageCode?.identifier == "ja"
        return Phrasebook(
            language: isJapanese ? .japanese : .english,
            usesFahrenheit: locale.measurementSystem == .us,
            calendar: calendar,
            uses24Hour: isJapanese || !Self.usesTwelveHourClock(locale)
        )
    }

    private static func usesTwelveHourClock(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return format.contains("a")
    }

    // MARK: - 更新

    /// 材料を取り直して、計画を作り直す
    func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let request = WorldRequest(bases: bases, preferences: preferences, now: now, calendar: calendar, isPro: isPro)
        snapshot = await environment.provider.snapshot(for: request)
        refreshedAt = now
        replan()
    }

    /// いまある材料で、計画を作り直す
    func replan() {
        let done = environment.logs.all().filter { $0.outcome == .done }
        var doneCounts: [SlotKind: Int] = [:]
        for log in done {
            if let kind = SlotKind(rawValue: log.slotKindRaw) {
                doneCounts[kind, default: 0] += 1
            }
        }
        let input = WeekPlanner.Input(
            events: snapshot.events,
            places: snapshot.places,
            bases: bases,
            forecasts: snapshot.forecasts,
            spots: snapshot.spots,
            preferences: preferences,
            isPro: isPro,
            now: now,
            calendar: calendar,
            rejectedSpotIDs: environment.settings.rejectedSpotIDs,
            doneCounts: doneCounts
        )
        plans = WeekPlanner.plans(input)
        if selectedDay >= plans.count {
            selectedDay = 0
        }
    }

    // MARK: - 計画の読み出し

    var selectedPlan: DayPlan? {
        plans.indices.contains(selectedDay) ? plans[selectedDay] : nil
    }

    /// 提案に、利用者が選び直した案を当てたもの
    func resolved(_ suggestion: Suggestion) -> Suggestion {
        guard let plan = chosenPlans[suggestion.id] else {
            return suggestion
        }
        var result = suggestion
        result.plan = plan
        let length = TimeInterval(plan.windowMinutes * 60)
        result.window = DateInterval(start: suggestion.window.start, duration: length)
        if plan.activity != suggestion.plan.activity {
            // 代わりの案に入れ替えたら、もとの案を「戻す先」にする。
            // 「ほかの場所」は、もとの動き方のための候補なので出さない（屋内の案に公園を当てない）
            let label: AlternatePlan.Label = suggestion.plan.activity.isOutdoor ? .ifClear : .ifRain
            result.alternate = AlternatePlan(label: label, plan: suggestion.plan)
            result.otherSpots = []
        }
        return result
    }

    /// いまの画面に出している提案か（無料では、今日・明日のひと足 1 件ずつだけ）
    func isShown(_ id: String) -> Bool {
        plans.contains { plan in
            plan.visible.contains { $0.id == id }
        }
    }

    func suggestion(id: String) -> Suggestion? {
        for plan in plans {
            if let found = plan.candidates.first(where: { $0.id == id }) {
                return resolved(found)
            }
        }
        return nil
    }

    func forecast(for cell: PlaceCell?) -> PlaceForecast? {
        cell.flatMap { snapshot.forecasts[$0] }
    }

    /// 今週の歩きどき（Pro）
    var outlook: [Suggestion] {
        WeekOutlook.best(in: plans)
    }

    // MARK: - 利用者の操作

    /// 「これにする」: 代わりの案やほかの場所に入れ替える
    func choose(_ plan: StepPlan, for suggestion: Suggestion) {
        chosenPlans[suggestion.id] = plan
    }

    /// ほかの場所を選ぶ（同じ動き方のまま、場所だけ変える）
    func choose(spot: Spot, for suggestion: Suggestion) {
        let origin = suggestion.slot.place.coordinate
        var plan = suggestion.plan
        plan.spot = spot
        plan.walkMinutesToSpot = origin.walkingMinutes(to: spot.coordinate)
        plan.distanceMeters = origin.distance(to: spot.coordinate)
        if plan.activity == .walk, plan.route == .roundTrip {
            plan.minutes = max(plan.minutes, (plan.walkMinutesToSpot * 2 + 4) / 5 * 5)
        }
        chosenPlans[suggestion.id] = plan
    }

    /// 「この場所は出さない」
    func reject(spot: Spot) {
        var rejected = environment.settings.rejectedSpotIDs
        rejected.insert(spot.id)
        environment.settings.rejectedSpotIDs = rejected
        chosenPlans = chosenPlans.filter { $0.value.spot?.id != spot.id }
        replan()
    }

    /// 「この時刻に知らせる」: この端末で通知を出すようにする
    func enableNotices() async {
        noticesEnabled = true
        environment.settings.noticesEnabled = true
    }

    // MARK: - 記録

    var logs: [StepLog] {
        _ = logRevision
        return environment.logs.all()
    }

    func log(for suggestion: Suggestion) -> StepLog? {
        _ = logRevision
        return environment.logs.log(for: suggestion.id)
    }

    func record(_ suggestion: Suggestion, outcome: StepLog.Outcome) {
        environment.logs.record(suggestion, title: book.title(for: suggestion.plan), outcome: outcome)
        logRevision += 1
    }

    func setOutcome(_ outcome: StepLog.Outcome, for log: StepLog) {
        environment.logs.setOutcome(outcome, for: log)
        logRevision += 1
        replan()
    }

    /// まだ答えていない、きのうまでのひと足（「どうでしたか」の問いに使う。24 時間で消える）
    var pendingLog: StepLog? {
        logs.first { log in
            log.outcome == .started && log.date < now && now.timeIntervalSince(log.date) < 36 * 3600
                && !calendar.isDate(log.date, inSameDayAs: now)
        }
    }

    /// 保存したものをすべて消す
    func eraseAll() {
        environment.settings.eraseAll()
        environment.logs.eraseAll()
        preferences = Preferences()
        bases = []
        chosenPlans = [:]
        logRevision += 1
        replan()
    }
}
