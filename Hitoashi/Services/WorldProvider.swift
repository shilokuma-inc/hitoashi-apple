//
//  WorldProvider.swift
//  Hitoashi
//
//  計画を作るための材料（予定・場所・予報・スポット）をまとめて取ってくる入口。
//  実データ（EventKit・WeatherKit・MapKit）と、見本のデータで差し替える。
//

import Foundation
import HitoashiKit

/// 1 回の更新で集めた材料
struct WorldSnapshot: Sendable {
    var events: [PlanEvent]
    /// 予定の id ごとの場所（仕様書 §5-3 の手順 1〜3 の結果）
    var places: [String: ResolvedPlace]
    var forecasts: [PlaceCell: PlaceForecast]
    var spots: [PlaceCell: NearbySpots]
    /// 見本のデータか（天気の帰属表示を出さず、「見本のデータです」と出す）
    var isDemo: Bool
    /// 天気を取れなかった地点
    var failedCells: Set<PlaceCell> = []

    static let empty = WorldSnapshot(events: [], places: [:], forecasts: [:], spots: [:], isDemo: false)
}

/// 更新の条件
struct WorldRequest: Sendable {
    var bases: [BasePlace]
    var preferences: Preferences
    var now: Date
    var calendar: Calendar
    var isPro: Bool
}

protocol WorldProviding: Sendable {
    func snapshot(for request: WorldRequest) async -> WorldSnapshot
}

/// 見本のデータ（仕様書 §3「見本の表示」）
struct DemoWorldProvider: WorldProviding {
    var alertToday = false

    func snapshot(for request: WorldRequest) async -> WorldSnapshot {
        let world = DemoData.world(alertToday: alertToday)
        return WorldSnapshot(events: world.events, places: world.places, forecasts: world.forecasts, spots: world.spots, isDemo: true)
    }
}
