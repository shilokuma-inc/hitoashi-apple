//
//  PlaceFinderTests.swift
//  HitoashiTests
//
//  駅の検索で返る名前から、駅だけを残すふるい分けを確かめる（MapKit が実際に返した名前を使う）。
//

@testable import Hitoashi
import HitoashiKit
import Testing

@MainActor
struct PlaceFinderTests {
    @Test(arguments: ["渋谷駅", "明治神宮前 <原宿>駅", "東京駅丸の内南口", "Shibuya Station"])
    func keepsStations(name: String) {
        #expect(PlaceFinder.isStationName(name))
    }

    @Test(arguments: [
        "渋谷駅 - 3番のりば",
        "渋谷駅 東口 タクシー乗り場",
        "西武渋谷店A館前 タクシー乗り場",
        "Shibuya Station Taxi",
        "バスターミナル東京八重洲地下B",
        "宮下公園前"
    ])
    func dropsBusStopsAndTaxiStands(name: String) {
        #expect(!PlaceFinder.isStationName(name))
    }

    /// 升目の中心から探した結果は、升目の端の地点でも使う。中心に近い順で件数を切ると、端の近くの場所を落とす
    @Test
    func tidyKeepsEveryPlaceInRangeSoTheEdgeOfTheCellStillHasNearbyPlaces() {
        let center = Coordinate(latitude: 35.6625, longitude: 139.7025)
        // 中心のすぐそばに 20 件、升目の端の近く（中心から約 330m）に 1 件、範囲の外に 1 件
        var spots = (0..<20).map { index in
            Spot(
                id: "near-\(index)",
                name: "中心のそば \(index)",
                coordinate: Coordinate(latitude: center.latitude + Double(index) * 0.00002, longitude: center.longitude),
                category: .park
            )
        }
        let edge = Coordinate(latitude: center.latitude + 0.003, longitude: center.longitude)
        spots.append(Spot(id: "edge", name: "端のそば", coordinate: edge, category: .park))
        // 同じ名前で遠いほう（入口が 2 つある公園など）は、近いほうだけを残す
        spots.append(Spot(id: "near-0-far-gate", name: "中心のそば 0", coordinate: edge, category: .park))
        let far = Coordinate(latitude: center.latitude + 0.03, longitude: center.longitude)
        spots.append(Spot(id: "far", name: "遠く", coordinate: far, category: .park))

        let tidied = PlaceFinder.tidy(spots, origin: center, radius: 850)

        // 範囲の中は 1 件も落とさない（同じ名前は近いほうだけ）。範囲の外は外す
        #expect(tidied.count == 21)
        #expect(tidied.contains { $0.id == "edge" })
        #expect(!tidied.contains { $0.id == "near-0-far-gate" })
        #expect(!tidied.contains { $0.id == "far" })
        #expect(tidied.first?.id == "near-0")
    }
}
