import Foundation
@testable import HitoashiKit
import Testing

struct SlotFinderTests {
    private func find(
        _ events: [DayEvent],
        base: ResolvedPlace? = Fixture.office,
        preferences: Preferences = Preferences(),
        now: Date? = nil
    ) -> [Slot] {
        SlotFinder.find(day: Fixture.day0, events: events, dayBase: base, preferences: preferences, calendar: Fixture.calendar, now: now)
    }

    @Test func gapBetweenEventsStartsFiveMinutesAfterAndKeepsTravelMargin() {
        // 渋谷 → 職場（約 6km）は、移動の余裕が 30 分
        let slots = find([
            Fixture.event("a", (13, 0), (14, 30), place: Fixture.shibuya),
            Fixture.event("b", (16, 0), (17, 0), place: Fixture.office)
        ])
        let between = slots.first { $0.kind == .between }
        #expect(between?.interval.start == Fixture.at(14, 35))
        #expect(between?.interval.end == Fixture.at(15, 30))
        #expect(between?.place == Fixture.shibuya)
        #expect(between?.previousEventEnd == Fixture.at(14, 30))
    }

    @Test func samePlaceNeedsOnlyTenMinutes() {
        let slots = find([Fixture.event("a", (14, 0), (15, 0)), Fixture.event("b", (16, 0), (17, 0))])
        #expect(slots.first { $0.kind == .between }?.interval.end == Fixture.at(15, 50))
    }

    @Test func farApartEventsHaveNoSlotBetween() {
        let osaka = ResolvedPlace(coordinate: Coordinate(latitude: 34.70, longitude: 135.50), name: "大阪", source: .geocoded)
        let slots = find([Fixture.event("a", (9, 0), (10, 0)), Fixture.event("b", (15, 0), (16, 0), place: osaka)])
        #expect(!slots.contains { $0.kind == .between })
    }

    @Test func afterTransitUsesNextEventPlace() {
        let osaka = ResolvedPlace(coordinate: Coordinate(latitude: 34.70, longitude: 135.50), name: "大阪の客先", source: .geocoded)
        let slots = find([
            Fixture.event("train", (9, 0), (10, 30), place: Fixture.office, title: "新幹線", transit: true),
            Fixture.event("visit", (14, 30), (16, 0), place: osaka)
        ])
        let between = slots.first { $0.interval.start == Fixture.at(10, 35) || $0.kind == .lunch }
        #expect(between?.place == osaka)
    }

    @Test func lunchSlotStaysInsideLunchHourAndReservesMealTime() {
        let slots = find([Fixture.event("a", (10, 0), (11, 0)), Fixture.event("b", (14, 0), (15, 0))])
        let lunch = slots.first { $0.kind == .lunch }
        #expect(lunch?.interval == DateInterval(start: Fixture.at(12), end: Fixture.at(13)))
        #expect(lunch?.reservedMinutes == 30)
        #expect(lunch?.usableMinutes == 30)
    }

    @Test func standaloneLunchWhenEventsAreOnlyInTheAfternoon() {
        let slots = find([Fixture.event("a", (15, 0), (16, 0))])
        let lunch = slots.first { $0.kind == .lunch }
        #expect(lunch?.interval.start == Fixture.at(12))
        #expect(lunch?.place == Fixture.office)
    }

    @Test func excludedEventSuppressesNeighborSlots() {
        let slots = find([
            Fixture.event("a", (15, 0), (16, 0)),
            Fixture.event("dinner", (19, 0), (21, 0), title: "会食", suppresses: true)
        ])
        // 会食の前の合間も、会食のあとも出さない
        #expect(!slots.contains { $0.kind == .between })
        #expect(!slots.contains { $0.kind == .afterLast })
    }

    @Test func afterLastIsCappedAtNinetyMinutes() {
        let slots = find([Fixture.event("a", (15, 0), (16, 0))])
        let after = slots.first { $0.kind == .afterLast }
        #expect(after?.interval == DateInterval(start: Fixture.at(16, 5), end: Fixture.at(17, 35)))
    }

    @Test func beforeFirstIsOffByDefault() {
        let events = [Fixture.event("a", (9, 0), (10, 0))]
        #expect(!find(events).contains { $0.kind == .beforeFirst })
        var preferences = Preferences()
        preferences.allowedSlots.insert(.beforeFirst)
        let before = find(events, preferences: preferences).first { $0.kind == .beforeFirst }
        #expect(before?.interval == DateInterval(start: Fixture.at(8), end: Fixture.at(8, 50)))
    }

    @Test func freeDayHasThreeFrames() {
        let slots = find([], base: Fixture.home)
        #expect(slots.map(\.kind) == [.freeDay, .freeDay, .freeDay])
        #expect(slots.map(\.interval.start) == [Fixture.at(6, 30), Fixture.at(11), Fixture.at(16)])
        #expect(slots.last?.interval.end == Fixture.at(21, 30))
    }

    @Test func noBaseMeansNoFreeDaySlots() {
        #expect(find([], base: nil).isEmpty)
    }

    @Test func longEventOpensOnlyAtLunch() {
        let slots = find([Fixture.event("training", (9, 0), (18, 0), title: "研修")])
        #expect(slots.contains { $0.kind == .lunch })
        #expect(!slots.contains { $0.kind == .between })
    }

    @Test func pastTimeIsCutOffToday() {
        let slots = find([], base: Fixture.home, now: Fixture.at(12, 0))
        #expect(slots.first?.interval.start == Fixture.at(12, 5))
        #expect(slots.count == 2)
    }

    @Test func ownLunchEventDefinesLunchHour() {
        var lunch = Fixture.event("lunch", (12, 30), (13, 30), place: nil, title: "ランチ")
        lunch.isLunchBreak = true
        let slots = find([Fixture.event("a", (10, 0), (11, 0)), lunch, Fixture.event("b", (15, 0), (16, 0))])
        #expect(slots.first { $0.kind == .lunch }?.interval == DateInterval(start: Fixture.at(12, 30), end: Fixture.at(13, 30)))
    }
}

struct ComfortTests {
    @Test func mildDryHourIsNearlyPerfect() {
        #expect(Comfort.score(Fixture.hour(15, temperature: 17, chance: 0.1)) == 96)
    }

    @Test func rainyHourLosesThirtyOrMore() {
        #expect(Comfort.score(Fixture.hour(13, kind: .rain, temperature: 15, chance: 0.7)) == 70)
    }

    @Test func hotHourIsPenalized() {
        // 体感 38°C は上限の 40 点を引く
        #expect(Comfort.score(Fixture.hour(13, temperature: 34, apparent: 38)) == 60)
        // 体感 27°C は 15 点
        #expect(Comfort.score(Fixture.hour(7, temperature: 27)) == 85)
    }

    @Test func darkHourLosesTen() {
        #expect(Comfort.score(Fixture.hour(19, temperature: 15, daylight: false)) == 90)
    }
}

struct WindowPickerTests {
    @Test func picksDryPartAndWaitsTenMinutesAfterRain() {
        let forecast = Fixture.forecast(for: Fixture.shibuya) { hour in
            (11..<15).contains(hour) ? Fixture.hour(hour, kind: .rain, temperature: 15, chance: 0.75, amount: 1.5) : nil
        }
        let slot = DateInterval(start: Fixture.at(14, 35), end: Fixture.at(15, 30))
        let window = WindowPicker.pick(in: slot, minutes: 20, forecast: forecast)
        #expect(window?.interval == DateInterval(start: Fixture.at(15, 10), end: Fixture.at(15, 30)))
    }

    @Test func tieGoesToEarliestStart() {
        let forecast = Fixture.forecast(for: Fixture.office)
        let slot = DateInterval(start: Fixture.at(12), end: Fixture.at(13))
        #expect(WindowPicker.pick(in: slot, minutes: 20, forecast: forecast)?.interval.start == Fixture.at(12))
    }

    @Test func noForecastMeansNoWindow() {
        let forecast = Fixture.forecast(for: Fixture.office)
        let slot = DateInterval(start: Fixture.at(12, day: 3), end: Fixture.at(13, day: 3))
        #expect(WindowPicker.pick(in: slot, minutes: 20, forecast: forecast) == nil)
    }
}

struct WeatherAssessorTests {
    @Test(arguments: [
        // 休む
        (Fixture.hour(13, temperature: 35), VerdictLevel.rest),
        (Fixture.hour(13, temperature: 33, apparent: 40), .rest),
        (Fixture.hour(13, wind: 15), .rest),
        (Fixture.hour(13, wind: 9, gust: 20), .rest),
        (Fixture.hour(13, kind: .severeStorm), .rest),
        (Fixture.hour(13, temperature: -10, apparent: -16), .rest),
        // 屋内
        (Fixture.hour(13, temperature: 31), .indoor),
        (Fixture.hour(13, temperature: 29, apparent: 31), .indoor),
        (Fixture.hour(13, chance: 0.5), .indoor),
        (Fixture.hour(13, kind: .drizzle, chance: 0.4), .indoor),
        (Fixture.hour(13, amount: 0.5), .indoor),
        (Fixture.hour(13, wind: 10), .indoor),
        (Fixture.hour(13, wind: 5, gust: 15), .indoor),
        (Fixture.hour(13, temperature: -3, apparent: -6), .indoor),
        (Fixture.hour(13, uv: 11), .indoor),
        // 外は気をつけて
        (Fixture.hour(13, temperature: 28), .caution),
        (Fixture.hour(13, chance: 0.3), .caution),
        (Fixture.hour(13, wind: 7), .caution),
        (Fixture.hour(13, temperature: 6, apparent: 4.9), .caution),
        (Fixture.hour(13, uv: 8), .caution),
        // 外がおすすめ（境の手前）
        (Fixture.hour(13, temperature: 27.9, chance: 0.29, wind: 6.9, uv: 7), .great),
        (Fixture.hour(13, temperature: 6, apparent: 5), .great)
    ])
    func classifies(hour: HourForecast, expected: VerdictLevel) {
        #expect(WeatherAssessor.assess(hours: [hour], isDark: false).level == expected)
    }

    @Test func darknessAloneIsCaution() {
        let verdict = WeatherAssessor.assess(hours: [Fixture.hour(18, daylight: false)], isDark: true)
        #expect(verdict.level == .caution)
        #expect(verdict.reasons == [.dark])
    }

    @Test func severeAlertMeansRest() {
        let alert = WeatherAlertInfo(summary: "大雨警報", source: "気象庁", detailsURL: nil, severity: .severe)
        let verdict = WeatherAssessor.assess(hours: [Fixture.hour(13)], severeAlerts: [alert], isDark: false)
        #expect(verdict.level == .rest)
        #expect(verdict.reasons == [.alert(summary: "大雨警報")])
    }

    @Test func worstHourDecides() {
        let verdict = WeatherAssessor.assess(hours: [Fixture.hour(13), Fixture.hour(14, kind: .rain, chance: 0.8)], isDark: false)
        #expect(verdict.level == .indoor)
        #expect(verdict.isIndoorBecauseOfRain)
    }
}
