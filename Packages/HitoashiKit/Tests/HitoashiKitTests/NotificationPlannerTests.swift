import Foundation
@testable import HitoashiKit
import Testing

struct NotificationPlannerTests {
    let world = DemoData.world()

    private func output(
        preferences: Preferences = Preferences(),
        ledger: NoticeLedger = NoticeLedger(),
        now: Date? = nil,
        mutate: (inout WeekPlanner.Input) -> Void = { _ in }
    ) -> NotificationPlanner.Output {
        var input = world.plannerInput(preferences: preferences)
        if let now {
            input.now = now
        }
        mutate(&input)
        return NotificationPlanner.plan(
            NotificationPlanner.Input(
                plans: WeekPlanner.plans(input),
                ledger: ledger,
                preferences: preferences,
                now: input.now,
                calendar: world.calendar,
                phrasebook: Fixture.book
            )
        )
    }

    @Test func todayFiresFiveMinutesAfterTheEventWithWeatherWhenFresh() throws {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        let notice = try #require(output(preferences: preferences).notices.first { $0.id == "day-2026-11-12" })
        // 予定の終了（14:30）の 5 分後。予報の取得（9:02）から 6 時間以内なので、天気を言い切る
        #expect(notice.fireDate == Fixture.at(14, 35))
        #expect(notice.title == "雨は15時までの予報。15:10から歩けます")
        #expect(notice.body == "20分。代々木公園まで。")
    }

    @Test func staleForecastDoesNotMentionWeather() throws {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        let result = output(preferences: preferences) { input in
            // 予報の取得を、通知の 6 時間より前にする
            for (cell, forecast) in input.forecasts {
                var old = forecast
                old.fetchedAt = Fixture.at(7, 0)
                input.forecasts[cell] = old
            }
        }
        let notice = try #require(result.notices.first { $0.id == "day-2026-11-12" })
        #expect(notice.title == "14:30 に終わる予定のあとに、20分あります")
        #expect(notice.body == "いまの天気を確かめて、ひと足どうですか。")
    }

    @Test func rainyLunchSaysItPlainlyWhenChanceIsHigh() throws {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        // 月曜（一日じゅう雨）の前日の夜に開いたとき
        let result = output(preferences: preferences, now: Fixture.at(8, 0, day: 4)) { input in
            for (cell, forecast) in input.forecasts {
                var fresh = forecast
                fresh.fetchedAt = Fixture.at(8, 0, day: 4)
                input.forecasts[cell] = fresh
            }
        }
        let notice = try #require(result.notices.first { $0.id == "day-2026-11-16" })
        #expect(notice.title == "降水確率80%。屋根のあるところで")
        #expect(notice.body == "12:00から20分。丸ビルの中を歩く。")
        // 昼休み（予定の直後ではない）は、窓の 10 分前
        #expect(notice.fireDate == Fixture.at(11, 50, day: 4))
    }

    @Test func nudgeIsScheduledThreeDaysAhead() throws {
        let nudge = try #require(output().notices.first { $0.kind == .nudge })
        #expect(nudge.fireDate == Fixture.at(12, 0, day: 3))
        #expect(nudge.title == "ひと足、どうですか")
    }

    @Test func noDayNoticesWhenTurnedOff() {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        preferences.dayNoticeEnabled = false
        #expect(output(preferences: preferences).notices.isEmpty)
    }

    @Test func weeklyTargetLimitsConfirmedDays() {
        // 今週（月〜日）は木曜から 4 日残っている。週 2 回なら、良い日の上位 2 つだけ確定する
        var preferences = Preferences()
        preferences.weeklyTarget = .two
        let result = output(preferences: preferences)
        // 今日（雨あがりの外・98 点）と明日（晴れ・98 点）は、土日と同点。早い日が先なので確定する
        #expect(result.ledger.confirmedDays == ["2026-11-12", "2026-11-13"])
    }

    @Test func alreadyUsedQuotaMeansNoMoreThisWeek() {
        var preferences = Preferences()
        preferences.weeklyTarget = .two
        let ledger = NoticeLedger(confirmedDays: ["2026-11-09", "2026-11-10"])
        let result = output(preferences: preferences, ledger: ledger)
        #expect(!result.ledger.confirmedDays.contains("2026-11-12"))
        #expect(!result.notices.contains { $0.kind == .day })
    }

    @Test func confirmedDayStaysConfirmed() {
        var preferences = Preferences()
        preferences.weeklyTarget = .two
        let ledger = NoticeLedger(confirmedDays: ["2026-11-10", "2026-11-12"])
        let result = output(preferences: preferences, ledger: ledger)
        #expect(result.ledger.confirmedDays.contains("2026-11-12"))
        #expect(result.notices.contains { $0.id == "day-2026-11-12" })
    }

    @Test func restDayIsNotNotifiedAndGivesTheQuotaBack() {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        let alertWorld = DemoData.world(alertToday: true)
        let result = NotificationPlanner.plan(
            NotificationPlanner.Input(
                plans: WeekPlanner.plans(alertWorld.plannerInput(preferences: preferences)),
                ledger: NoticeLedger(confirmedDays: ["2026-11-12"]),
                preferences: preferences,
                now: alertWorld.now,
                calendar: alertWorld.calendar,
                phrasebook: Fixture.book
            )
        )
        #expect(!result.ledger.confirmedDays.contains("2026-11-12"))
        #expect(!result.notices.contains { $0.id == "day-2026-11-12" })
    }

    @Test func eveningNoticeOnlyWhenPreparationIsNeeded() {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        // 既定（準備が要るときだけ）: 明日は歩くだけなので出ない
        #expect(!output(preferences: preferences).notices.contains { $0.kind == .evening })
        preferences.eveningNotice = .always
        let evening = output(preferences: preferences).notices.first { $0.kind == .evening }
        #expect(evening?.fireDate == Fixture.at(21, 0))
        #expect(evening?.title == "あしたは歩きやすい靴で")
        #expect(evening?.body == "昼すぎに、20分のひと足があります。")
    }

    @Test func eventTitleAppearsOnlyWhenAllowed() throws {
        var preferences = Preferences()
        preferences.weeklyTarget = .everyday
        preferences.includesEventTitleInNotice = true
        let result = output(preferences: preferences) { input in
            for (cell, forecast) in input.forecasts {
                var old = forecast
                old.fetchedAt = Fixture.at(7, 0)
                input.forecasts[cell] = old
            }
        }
        let notice = try #require(result.notices.first { $0.id == "day-2026-11-12" })
        #expect(notice.title == "「打ち合わせ」のあとに、20分あります")
    }
}

struct PhrasebookTests {
    @Test func japaneseHasNoSpaceBetweenNumberAndCounter() {
        let book = Fixture.book
        #expect(book.minutes(20) == "20分")
        #expect(book.duration(minutes: 88) == "1時間28分")
        #expect(book.hour(15) == "15時")
        #expect(book.percent(0.75) == "75%")
        #expect(book.temperature(15.6) == "16°")
    }

    @Test func englishUsesFahrenheitWhenAsked() {
        let book = Phrasebook(language: .english, usesFahrenheit: true, calendar: Fixture.calendar, uses24Hour: false)
        #expect(book.temperature(20) == "68°")
        #expect(book.time(Fixture.at(15, 10)) == "3:10 PM")
        #expect(book.minutes(20) == "20 min")
        #expect(book.headline(.rainUntil(hour: 15), level: .great) == "Rain until 3 PM")
    }

    @Test func distanceRoundsToTenMeters() {
        #expect(Fixture.book.distance(meters: 574) == "570m")
        #expect(Fixture.book.distance(meters: 1430) == "1.4km")
    }
}
