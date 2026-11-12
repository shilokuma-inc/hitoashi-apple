//
//  AppModelTests.swift
//  HitoashiTests
//
//  見本のデータで、画面が見る状態（計画・選び直し・記録）を確かめる。
//

import Foundation
@testable import Hitoashi
import HitoashiKit
import Testing

@MainActor
struct AppModelTests {
    private func makeModel() async -> AppModel {
        let model = AppModel(environment: .demo())
        await model.refresh()
        return model
    }

    @Test
    func refreshBuildsTenDaysFromTheDemoWorld() async throws {
        let model = await makeModel()
        #expect(model.plans.count == 10)
        #expect(model.isDemo)
        let top = try #require(model.selectedPlan?.top)
        #expect(model.book.title(for: top.plan) == "代々木公園まで歩く")
        // 無料では、今日は 1 件だけ見せて、残りは「ほかに N つ」
        #expect(model.selectedPlan?.visible.count == 1)
        #expect(model.selectedPlan?.hiddenCount == 1)
    }

    @Test
    func proShowsEveryStepAndTheOutlook() async {
        let model = await makeModel()
        model.isPro = true
        #expect(model.selectedPlan?.hiddenCount == 0)
        #expect(model.outlook.count == 3)
    }

    @Test
    func choosingTheAlternateSwapsThePlan() async throws {
        let model = await makeModel()
        let top = try #require(model.selectedPlan?.top)
        let alternate = try #require(top.alternate)
        model.choose(alternate.plan, for: top)
        let resolved = try #require(model.suggestion(id: top.id))
        #expect(resolved.plan.activity == .coveredWalk)
        #expect(model.book.title(for: resolved.plan) == "渋谷パルコの中を歩く")
    }

    @Test
    func choosingAnotherSpotKeepsTheActivity() async throws {
        let model = await makeModel()
        let top = try #require(model.selectedPlan?.top)
        let other = try #require(top.otherSpots.first)
        model.choose(spot: other, for: top)
        let resolved = try #require(model.suggestion(id: top.id))
        #expect(resolved.plan.activity == .walk)
        #expect(resolved.plan.spot?.id == other.id)
    }

    @Test
    func rejectedSpotIsNoLongerSuggested() async throws {
        let model = await makeModel()
        let spot = try #require(model.selectedPlan?.top?.plan.spot)
        model.reject(spot: spot)
        #expect(model.selectedPlan?.top?.plan.spot?.id != spot.id)
    }

    @Test
    func recordingCreatesAndUpdatesOneLog() async throws {
        let model = await makeModel()
        let top = try #require(model.selectedPlan?.top)
        let before = model.logs.count
        model.record(top, outcome: .started)
        #expect(model.logs.count == before + 1)
        #expect(model.log(for: top)?.outcome == .started)
        model.record(top, outcome: .done)
        #expect(model.logs.count == before + 1)
        #expect(model.log(for: top)?.outcome == .done)
        // 記録には天気を残さない（題名・分数・外か屋内かだけ）
        #expect(model.log(for: top)?.title == "代々木公園まで歩く")
        #expect(model.log(for: top)?.isOutdoor == true)
    }

    @Test
    func pendingLogAsksAboutYesterday() async throws {
        let model = await makeModel()
        let pending = try #require(model.pendingLog)
        #expect(pending.title == "日比谷公園まで歩く")
        model.setOutcome(.done, for: pending)
        #expect(model.pendingLog == nil)
    }

    @Test
    func changingPreferencesReplans() async {
        let model = await makeModel()
        model.isPro = true
        var preferences = model.preferences
        preferences.allowedSlots = [.afterLast]
        model.preferences = preferences
        #expect(model.selectedPlan?.candidates.allSatisfy { $0.slot.kind == .afterLast } == true)
    }
}

@MainActor
struct TimelineBuilderTests {
    @Test
    func rowsAlternateEventsStepsAndGaps() async throws {
        let model = AppModel(environment: .demo())
        await model.refresh()
        let plan = try #require(model.selectedPlan)
        let rows = TimelineBuilder.rows(for: plan, resolve: model.resolved)
        let kinds = rows.map { row -> String in
            switch row.content {
            case .event:
                "event"
            case .step:
                "step"
            case .gap:
                "gap"
            }
        }
        #expect(kinds == ["event", "gap", "event", "gap", "step", "gap", "event", "gap", "event"])
        // 行は時刻順で、重ならない
        for (previous, next) in zip(rows, rows.dropFirst()) {
            #expect(previous.interval.end <= next.interval.start)
        }
    }

    @Test
    func gapHeightFollowsTheFreeTime() {
        let short = DateInterval(start: .now, duration: 10 * 60)
        let long = DateInterval(start: .now, duration: 3 * 3600)
        #expect(TimelineBuilder.gapHeight(for: short) == 6)
        #expect(TimelineBuilder.gapHeight(for: long) == 28)
    }

    @Test
    func placeLineShowsHowTheBaseIsTreated() async throws {
        let model = AppModel(environment: .demo())
        await model.refresh()
        let events = try #require(model.selectedPlan?.events)
        let lines = Dictionary(uniqueKeysWithValues: events.map { ($0.title, PlaceText.line(for: $0)) })
        #expect(lines["定例ミーティング"] == "オンライン（職場）")
        #expect(lines["1on1"] == "8F Fuji（職場）")
        #expect(lines["打ち合わせ"] == "渋谷 神南オフィス")
    }
}

@MainActor
struct RailBuilderTests {
    private let world = DemoData.world()

    @Test
    func segmentsSplitRainAndDryByTime() throws {
        let forecast = try #require(world.forecasts.values.first)
        let day = forecast.day(containing: DemoData.date(day: 0, hour: 12), calendar: world.calendar)
        // 14:30〜15:10 は、15 時まで雨
        let interval = DateInterval(start: DemoData.date(day: 0, hour: 14, minute: 30), end: DemoData.date(day: 0, hour: 15, minute: 10))
        let segments = RailBuilder.segments(for: interval, forecast: forecast, day: day)
        #expect(segments.count == 2)
        #expect(segments[0].isRain)
        #expect(!segments[1].isRain)
        #expect(abs(segments[0].fraction - 0.75) < 0.01)
    }

    @Test
    func darkAfterSunset() throws {
        let forecast = try #require(world.forecasts.values.first)
        let day = forecast.day(containing: DemoData.date(day: 0, hour: 12), calendar: world.calendar)
        let interval = DateInterval(start: DemoData.date(day: 0, hour: 16), end: DemoData.date(day: 0, hour: 17))
        let segments = RailBuilder.segments(for: interval, forecast: forecast, day: day)
        #expect(segments.map(\.isDark) == [false, true])
    }

    @Test
    func notesMarkWhereTheWeatherChanges() throws {
        let forecast = try #require(world.forecasts.values.first)
        let day = forecast.day(containing: DemoData.date(day: 0, hour: 12), calendar: world.calendar)
        let book = Phrasebook(calendar: world.calendar)
        let gap = DateInterval(start: DemoData.date(day: 0, hour: 14, minute: 30), end: DemoData.date(day: 0, hour: 15, minute: 10))
        #expect(RailBuilder.notes(for: gap, forecast: forecast, day: day, book: book).map(\.text) == ["雨 〜15時"])
        let evening = DateInterval(start: DemoData.date(day: 0, hour: 16), end: DemoData.date(day: 0, hour: 17))
        #expect(RailBuilder.notes(for: evening, forecast: forecast, day: day, book: book).map(\.text) == ["日没 16:38"])
    }
}
