//
//  PlaceFinderTests.swift
//  HitoashiTests
//
//  駅の検索で返る名前から、駅だけを残すふるい分けを確かめる（MapKit が実際に返した名前を使う）。
//

@testable import Hitoashi
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
}
