import Foundation
@testable import HitoashiKit
import Testing

struct LocationTextScreenerTests {
    @Test(arguments: [
        ("https://example.com/j/123", LocationTextScreener.Result.online),
        ("Zoom ミーティング", .online),
        ("オンライン", .online),
        ("8F Fuji", .meetingRoom),
        ("3階 大会議室", .meetingRoom),
        ("会議室 A", .meetingRoom),
        ("Room 2", .meetingRoom),
        ("03-1234-5678", .unusable),
        ("someone@example.com", .unusable),
        ("", .unusable),
        ("渋谷ヒカリエ 11F", .geocodable("渋谷ヒカリエ")),
        ("東京都千代田区丸の内 3-2-1", .geocodable("東京都千代田区丸の内 3-2-1")),
        ("1 Infinite Loop, Cupertino", .geocodable("1 Infinite Loop, Cupertino"))
    ])
    func screens(text: String, expected: LocationTextScreener.Result) {
        #expect(LocationTextScreener.screen(text) == expected)
    }

    @Test func usesOnlyFirstLine() {
        #expect(LocationTextScreener.screen("恵比寿ガーデンプレイス\n東京都渋谷区") == .geocodable("恵比寿ガーデンプレイス"))
    }

    @Test func rejectsFarResultWithoutPlaceNameInText() {
        let osaka = Coordinate(latitude: 34.70, longitude: 135.50)
        // 会議室名のような文字列が大阪に当たっても、拠点（東京）から遠く、文字列に地名が無ければ捨てる
        let names = ["大阪府", "大阪市"]
        let bases = [DemoData.work]
        #expect(!LocationTextScreener.acceptsGeocode(text: "Fuji", result: osaka, resultPlaceNames: names, bases: bases))
        #expect(LocationTextScreener.acceptsGeocode(text: "大阪市北区のホテル", result: osaka, resultPlaceNames: names, bases: bases))
        #expect(LocationTextScreener.acceptsGeocode(text: "Fuji", result: DemoData.shibuya, resultPlaceNames: [], bases: bases))
    }
}

struct EventNormalizerTests {
    private func plan(_ id: String, _ title: String, _ from: (Int, Int), _ end: (Int, Int), location: String? = nil) -> PlanEvent {
        PlanEvent(id: id, title: title, start: Fixture.at(from.0, from.1), end: Fixture.at(end.0, end.1), locationText: location)
    }

    @Test func dropsCanceledDeclinedAndShortEvents() {
        var canceled = plan("a", "中止", (10, 0), (11, 0))
        canceled.isCanceled = true
        var declined = plan("b", "辞退", (11, 0), (12, 0))
        declined.isDeclined = true
        let short = plan("c", "5 分", (12, 0), (12, 10))
        let kept = plan("d", "残る", (13, 0), (14, 0))
        let output = EventNormalizer.normalize([canceled, declined, short, kept], places: [:], preferences: Preferences())
        #expect(output.timed.map(\.id) == ["d"])
    }

    @Test func mergesOverlappingEvents() {
        let output = EventNormalizer.normalize(
            [plan("a", "会議 A", (10, 0), (11, 0)), plan("b", "会議 B", (10, 30), (11, 30))],
            places: ["a": Fixture.office, "b": Fixture.shibuya],
            preferences: Preferences()
        )
        #expect(output.timed.count == 1)
        #expect(output.timed.first?.end == Fixture.at(11, 30))
        // 場所は最後に終わる予定のもの
        #expect(output.timed.first?.place == Fixture.shibuya)
    }

    @Test(arguments: [
        ("会食", true), ("歯医者", true), ("通夜", true), ("定例ミーティング", false), ("Dentist", true)
    ])
    func marksExcludedTitles(title: String, expected: Bool) {
        let output = EventNormalizer.normalize([plan("a", title, (10, 0), (11, 0))], places: [:], preferences: Preferences())
        #expect(output.timed.first?.suppressesSuggestions == expected)
    }

    @Test(arguments: [
        ("新幹線 のぞみ 21 号", true), ("JAL 123便", true), ("移動", true), ("郵便局", false), ("A→B 打ち合わせ", false)
    ])
    func detectsTransit(title: String, expected: Bool) {
        #expect(EventNormalizer.isTransit(title) == expected)
    }

    @Test func treatsLocationlessLunchAsLunchBreak() {
        let output = EventNormalizer.normalize(
            [plan("a", "ランチ", (12, 30), (13, 30)), plan("b", "ランチ会", (12, 0), (13, 0), location: "丸の内")],
            places: [:],
            preferences: Preferences()
        )
        #expect(output.timed.first { $0.id == "a" }?.isLunchBreak == true)
        #expect(output.timed.first { $0.id == "b" }?.isLunchBreak == false)
    }

    @Test func separatesAllDayEvents() {
        var trip = plan("t", "大阪出張", (0, 0), (23, 59))
        trip.isAllDay = true
        let output = EventNormalizer.normalize([trip, plan("a", "会議", (10, 0), (11, 0))], places: [:], preferences: Preferences())
        #expect(output.allDay.map(\.id) == ["t"])
        #expect(output.timed.map(\.id) == ["a"])
    }
}

struct PlaceCellTests {
    @Test func fineCellsKeepTheirOwnSizeAndCenter() throws {
        let shibuya = Coordinate(latitude: 35.6620, longitude: 139.7005)
        let coarse = PlaceCell(shibuya)
        let fine = PlaceCell.fine(shibuya)
        // 中心は、もとの座標から升目の半分の対角より近い（細かい升目でも、正しい緯度・経度に戻る）
        #expect(coarse.center.distance(to: shibuya) < 1600)
        #expect(fine.center.distance(to: shibuya) < 400)
        // 大きさの違う升目は、番号が同じでも別のもの
        #expect(coarse != fine)
        // 大きさを持たない古い保存は、天気の升目として読む
        let old = try JSONDecoder().decode(PlaceCell.self, from: Data(#"{"latIndex":1783,"lonIndex":6985}"#.utf8))
        #expect(old == coarse)
    }
}

struct PlaceForecastTests {
    @Test func readsOlderSavedForecastsWithoutTheSupportedFlag() throws {
        // `alertsSupported` を足す前に保存した予報（対応しているものとして読む）
        let json = #"{"cell":{"latIndex":1783,"lonIndex":6985},"fetchedAt":0,"hours":[],"days":[],"alerts":[],"alertsAvailable":false}"#
        let forecast = try JSONDecoder().decode(PlaceForecast.self, from: Data(json.utf8))
        #expect(!forecast.alertsAvailable)
        #expect(forecast.alertsSupported)
        // 書いて読み直しても、対応していない地域の印は残る
        var unsupported = forecast
        unsupported.alertsSupported = false
        let reread = try JSONDecoder().decode(PlaceForecast.self, from: JSONEncoder().encode(unsupported))
        #expect(!reread.alertsSupported)
    }
}

struct NearbySpotsTests {
    @Test func arrangesFromTheActualPlaceAndKeepsTheNearerOfSameNamedPlaces() {
        // 升目の中心と、端の近くに、同じ名前の施設が 1 つずつある
        let center = Coordinate(latitude: 35.6625, longitude: 139.7025)
        let edge = Coordinate(latitude: 35.6650, longitude: 139.7049)
        let spots = NearbySpots(
            covered: [
                Spot(id: "center-hall", name: "市民ホール", coordinate: center, category: .covered),
                Spot(id: "center-mall", name: "モール", coordinate: center, category: .covered),
                Spot(id: "edge-hall", name: "市民ホール", coordinate: edge, category: .covered)
            ]
        )
        // 端の地点から使うときは、端の近くのほうを残して先頭にする
        let fromEdge = spots.arranged(from: edge)
        #expect(fromEdge.covered.map(\.id) == ["edge-hall", "center-mall"])
        // 中心の地点から使うときは、中心のほう
        let fromCenter = spots.arranged(from: center)
        #expect(fromCenter.covered.first { $0.name == "市民ホール" }?.id == "center-hall")
        #expect(fromCenter.covered.count == 2)
    }
}

struct PlaceFallbackTests {
    @Test func weekdayUsesWorkAndWeekendUsesHome() {
        let bases = DemoData.world().bases
        let thursday = PlaceFallback.dayBase(on: Fixture.at(0), allDayPlaces: [], bases: bases, calendar: Fixture.calendar)
        let saturday = PlaceFallback.dayBase(on: Fixture.at(0, day: 2), allDayPlaces: [], bases: bases, calendar: Fixture.calendar)
        #expect(thursday?.source == .base(.work))
        #expect(saturday?.source == .base(.home))
    }

    @Test func allDayEventPlaceBecomesDayBase() {
        let hotel = ResolvedPlace(coordinate: Coordinate(latitude: 34.70, longitude: 135.50), name: "大阪のホテル", source: .geocoded)
        let bases = DemoData.world().bases
        let base = PlaceFallback.dayBase(on: Fixture.at(0), allDayPlaces: [hotel], bases: bases, calendar: Fixture.calendar)
        #expect(base?.source == .dayBase)
        #expect(base?.coordinate == hotel.coordinate)
    }

    @Test func onlineMeetingDoesNotInheritFromNeighbors() {
        let events = [
            Fixture.event("online", (10, 0), (11, 0), place: nil),
            Fixture.event("visit", (11, 30), (12, 30), place: Fixture.shibuya)
        ]
        let result = PlaceFallback.apply(to: events, screens: ["online": .online], dayBase: Fixture.office)
        #expect(result[0].place == Fixture.office)
    }

    @Test func meetingRoomIsOfficeOnWorkdays() {
        let events = [
            Fixture.event("visit", (13, 0), (14, 30), place: Fixture.shibuya),
            Fixture.event("room", (16, 0), (17, 0), place: nil)
        ]
        let result = PlaceFallback.apply(to: events, screens: ["room": .meetingRoom], dayBase: Fixture.office)
        #expect(result[1].place == Fixture.office)
    }

    @Test func unknownPlaceInheritsWithinTwoHoursPreferringPrevious() {
        let events = [
            Fixture.event("visit", (10, 0), (11, 0), place: Fixture.shibuya),
            Fixture.event("unknown", (13, 0), (14, 0), place: nil),
            Fixture.event("far", (17, 0), (18, 0), place: nil)
        ]
        let result = PlaceFallback.apply(to: events, screens: [:], dayBase: Fixture.office)
        // 前の予定の終了からちょうど 120 分は引き継ぐ
        #expect(result[1].place?.source == .inherited)
        #expect(result[1].place?.coordinate == Fixture.shibuya.coordinate)
        // 120 分を超えたら、その日の拠点
        #expect(result[2].place == Fixture.office)
    }
}
