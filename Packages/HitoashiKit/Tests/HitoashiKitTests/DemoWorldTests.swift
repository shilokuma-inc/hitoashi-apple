import Foundation
@testable import HitoashiKit
import Testing

/// 見本の 10 日間を通したときの結果を確かめる（仕様書 §5 の流れ全体）
struct DemoWorldTests {
    let world = DemoData.world()
    var book: Phrasebook { Fixture.book }

    private func plans(isPro: Bool = false, preferences: Preferences = Preferences()) -> [DayPlan] {
        WeekPlanner.plans(world.plannerInput(preferences: preferences, isPro: isPro))
    }

    @Test func todayPicksTheDryWindowAfterTheRain() throws {
        let today = try #require(plans().first)
        let top = try #require(today.top)
        #expect(book.time(top.window.start) == "15:10")
        #expect(book.time(top.window.end) == "15:30")
        #expect(book.title(for: top.plan) == "代々木公園まで歩く")
        #expect(top.plan.minutes == 20)
        #expect(top.verdict.level == .great)
        #expect(top.headlines == [.rainUntil(hour: 15), .sunsetIn(minutes: 88)])
        #expect(book.headlineLine(for: top) == "雨は15時まで。日没まで1時間28分。")
        #expect(book.slotLabel(top.slot) == "14:30 に終わる予定のあと")
        let alternate = try #require(top.alternate)
        #expect(book.alternateLabel(alternate.label) == "雨なら")
        #expect(book.alternateText(alternate) == "渋谷パルコの中を20分")
    }

    @Test func placesFallBackToBasesForOnlineAndMeetingRooms() throws {
        let today = try #require(plans().first)
        let byTitle = Dictionary(uniqueKeysWithValues: today.events.map { ($0.title, $0.place) })
        #expect(byTitle["定例ミーティング"]??.source == .base(.work))
        #expect(byTitle["1on1"]??.source == .base(.work))
        #expect(byTitle["打ち合わせ"]??.source == .eventCoordinate)
    }

    @Test func freeShowsOnlyTodaysStepAndCountsTheRest() throws {
        let free = plans()
        #expect(free[0].visible.count == 1)
        #expect(free[0].hiddenCount == 1)
        #expect(free[1].visible.count == 1)
        // 3 日目以降の提案は Pro
        #expect(free[2].visible.isEmpty)
        #expect(free[2].hiddenCount == free[2].candidates.count)
        let pro = plans(isPro: true)
        #expect(pro[0].visible.count == 2)
        #expect(pro[0].hiddenCount == 0)
        #expect(pro[2].visible.count == 3)
    }

    @Test func rainyDayGoesIndoorsAtLunch() throws {
        let monday = plans()[4]
        let top = try #require(monday.top)
        #expect(top.slot.kind == .lunch)
        #expect(top.verdict.level == .indoor)
        #expect(book.title(for: top.plan) == "丸ビルの中を歩く")
        #expect(book.alternateLabel(try #require(top.alternate).label) == "晴れたら")
        #expect(book.time(top.window.start) == "12:00")
    }

    @Test func stormyDayIsARestDay() {
        let tuesday = plans()[5]
        #expect(tuesday.top == nil)
        #expect(tuesday.candidates.isEmpty)
        #expect(tuesday.restDay != nil)
    }

    @Test func severeAlertTodayMakesTodayARestDayButNotTomorrow() {
        let alertWorld = DemoData.world(alertToday: true)
        let result = WeekPlanner.plans(alertWorld.plannerInput())
        #expect(result[0].restDay?.alerts.first?.summary == "大雨警報")
        #expect(result[0].top == nil)
        // 警報は翌日には持ち越さない
        #expect(result[1].top != nil)
    }

    @Test func weekendWithoutPlansSuggestsMiddayNearHome() throws {
        let saturday = plans()[2]
        let top = try #require(saturday.top)
        #expect(top.slot.kind == .freeDay)
        #expect(book.title(for: top.plan) == "北沢川緑道まで歩く")
        #expect(book.time(top.window.start) == "11:00")
    }

    @Test func afterDarkWalksToAStationInsteadOfAPark() throws {
        let friday = plans(isPro: true)[1]
        let evening = try #require(friday.candidates.last)
        #expect(evening.verdict.level == .caution)
        #expect(evening.plan.spot?.category == .station)
        #expect(evening.plan.route == .oneWay)
        #expect(evening.headlines.first == .dark)
    }

    @Test func afterDarkCanBeIndoorByPreference() throws {
        var preferences = Preferences()
        preferences.afterDark = .indoor
        let friday = plans(isPro: true, preferences: preferences)[1]
        let evening = try #require(friday.candidates.last)
        #expect(evening.plan.activity == .coveredWalk)
    }

    @Test func joggingIsOfferedOnlyWhenEnabledAndThereIsRoom() throws {
        var preferences = Preferences()
        preferences.jogEnabled = true
        let saturday = plans(isPro: true, preferences: preferences)[2]
        #expect(saturday.candidates.contains { $0.plan.activity == .jog })
        // 既定（オフ）では出ない
        #expect(!plans(isPro: true)[2].candidates.contains { $0.plan.activity == .jog })
        // 予定の合間（今日の 15 時）には出ない
        let today = plans(isPro: true, preferences: preferences)[0]
        #expect(!today.candidates.contains { $0.plan.activity == .jog })
    }

    @Test func rejectedSpotIsNotSuggested() throws {
        var input = world.plannerInput()
        input.rejectedSpotIDs = ["p-yoyogi"]
        let top = try #require(WeekPlanner.plans(input).first?.top)
        #expect(top.plan.spot?.id != "p-yoyogi")
    }

    @Test func requiredPlacesListsEachCellOnce() {
        let places = WeekPlanner.requiredPlaces(world.plannerInput())
        #expect(Set(places.map(\.cell)).count == places.count)
        #expect(places.count == 4)
    }

    @Test func weekOutlookPicksOneWindowPerDay() {
        let best = WeekOutlook.best(in: plans(isPro: true))
        #expect(best.count == 3)
        #expect(Set(best.map { Fixture.calendar.startOfDay(for: $0.window.start) }).count == 3)
        #expect(best.allSatisfy { $0.plan.activity.isOutdoor })
    }
}

/// 仕様の確認に使った「ある 1 日」を固定のテストにしたもの
struct ScenarioTests {
    /// 休日・予定なし・8 月の東京: 日中は気温 34°C / 体感 38°C、朝は 27°C、夕方は 30°C
    @Test func hotSummerHolidayPrefersTheCoolMorning() throws {
        let forecast = Fixture.forecast(for: Fixture.home, sunset: (18, 30)) { hour in
            switch hour {
            case 6...8:
                Fixture.hour(hour, temperature: 27, apparent: 27.5, uv: 3)
            case 9...17:
                Fixture.hour(hour, temperature: 34, apparent: 38, uv: 9)
            default:
                Fixture.hour(hour, temperature: 30, apparent: 32, uv: 0, daylight: hour < 19)
            }
        }
        let plan = DayPlanner.plan(
            DayPlanner.Input(
                day: Fixture.day0,
                dayIndex: 1,
                events: [],
                dayBase: Fixture.home,
                forecasts: [Fixture.home.cell: forecast],
                spots: DemoData.world().spots,
                preferences: Preferences(),
                isPro: true,
                now: Fixture.at(5),
                calendar: Fixture.calendar
            )
        )
        let top = try #require(plan.top)
        // 朝だけが外（「外がおすすめ」）。日中と夕方は屋内
        #expect(top.verdict.level == .great)
        #expect(Fixture.calendar.component(.hour, from: top.window.start) < 9)
        #expect(plan.candidates.filter { $0.verdict.level == .indoor }.count == 2)
    }

    /// 小雨が一日中（降水確率 40%）: 小雨は雨の天気なので屋内
    @Test func allDayDrizzleStaysIndoors() throws {
        let forecast = Fixture.forecast(for: Fixture.office) { hour in
            Fixture.hour(hour, kind: .drizzle, temperature: 14, chance: 0.4, amount: 0.2)
        }
        let plan = DayPlanner.plan(
            DayPlanner.Input(
                day: Fixture.day0,
                dayIndex: 1,
                events: [Fixture.event("a", (10, 0), (11, 0)), Fixture.event("b", (14, 0), (15, 0))],
                dayBase: Fixture.office,
                forecasts: [Fixture.office.cell: forecast],
                spots: DemoData.world().spots,
                preferences: Preferences(),
                isPro: false,
                now: Fixture.at(5),
                calendar: Fixture.calendar
            )
        )
        let top = try #require(plan.top)
        #expect(top.verdict.level == .indoor)
        #expect(top.plan.activity == .coveredWalk)
    }

    /// スポットが何も無い場所でも、歩く案は「近くをひと回り」で成立する
    @Test func walkWorksWithoutAnySpot() throws {
        let forecast = Fixture.forecast(for: Fixture.office)
        let slot = Slot(id: "s", kind: .between, interval: DateInterval(start: Fixture.at(14), end: Fixture.at(15)), place: Fixture.office)
        let suggestion = try #require(
            SuggestionEngine.suggest(
                slot: slot,
                forecast: forecast,
                spots: .empty,
                preferences: Preferences(),
                context: SuggestionEngine.Context(calendar: Fixture.calendar)
            )
        )
        #expect(suggestion.plan.activity == .walk)
        #expect(suggestion.plan.spot == nil)
        #expect(Fixture.book.title(for: suggestion.plan) == "近くをひと回り歩く")
        // 屋内の代わりの案は、場所が無ければその場で
        #expect(suggestion.alternate?.plan.activity == .onTheSpot)
    }

    /// 外は気をつけて、のときは歩くだけ・最長 20 分
    @Test func cautionCapsTheWalkAtTwentyMinutes() throws {
        var preferences = Preferences()
        preferences.durationMinutes = 30
        let forecast = Fixture.forecast(for: Fixture.office) { hour in Fixture.hour(hour, temperature: 29) }
        let interval = DateInterval(start: Fixture.at(13), end: Fixture.at(14, 30))
        let slot = Slot(id: "s", kind: .afterLast, interval: interval, place: Fixture.office)
        let suggestion = try #require(
            SuggestionEngine.suggest(
                slot: slot,
                forecast: forecast,
                spots: .empty,
                preferences: preferences,
                context: SuggestionEngine.Context(calendar: Fixture.calendar)
            )
        )
        #expect(suggestion.verdict.level == .caution)
        #expect(suggestion.plan.minutes == 20)
    }
}
