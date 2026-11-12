//
//  LiveWorldProvider.swift
//  Hitoashi
//
//  実データで材料を集める（仕様書 §5-1）。
//  予定の取り込み → 場所の解決 → 地点ごとに天気を取得（保存は最長 24 時間）→ スポットの検索。
//

import Foundation
import HitoashiKit

final class LiveWorldProvider: WorldProviding {
    private let calendarService: CalendarService
    private let settings: SettingsStore
    private let weather = WeatherFetcher()
    private let finder = PlaceFinder()
    /// 予報。取得から 24 時間で必ず捨てる
    private let forecasts = JSONFileCache<PlaceForecast>(name: "forecasts", lifetime: 24 * 3600)
    /// スポット。7 日保存する
    private let spots = JSONFileCache<NearbySpots>(name: "spots", lifetime: 7 * 24 * 3600)
    /// 場所の文字列ごとの位置。90 日保存する（見つからなかった文字列も覚えて、調べ直さない）
    private let geocodes = JSONFileCache<GeocodeHit?>(name: "geocodes", lifetime: 90 * 24 * 3600)

    init(calendarService: CalendarService, settings: SettingsStore) {
        self.calendarService = calendarService
        self.settings = settings
    }

    func snapshot(for request: WorldRequest) async -> WorldSnapshot {
        let today = request.calendar.startOfDay(for: request.now)
        let end = request.calendar.date(byAdding: .day, value: 10, to: today) ?? today
        let events = calendarService.events(from: today, to: end, calendarIDs: settings.calendarIDs)
        let places = await resolvePlaces(of: events, bases: request.bases)

        var input = WeekPlanner.Input(
            events: events,
            places: places,
            bases: request.bases,
            preferences: request.preferences,
            isPro: request.isPro,
            now: request.now,
            calendar: request.calendar
        )
        var snapshot = WorldSnapshot(events: events, places: places, forecasts: [:], spots: [:], isDemo: false)

        // 天気: 地点ごとに 1 回。今日の地点は 2 時間、それ以外は 6 時間たったら取り直す
        let todayCells = Set(WeekPlanner.requiredPlaces({ var one = input; one.dayCount = 1; return one }()).map(\.cell))
        for place in WeekPlanner.requiredPlaces(input) {
            let cell = place.cell
            let saved = forecasts.entry(for: cell.key, now: request.now)
            let refreshAfter: TimeInterval = todayCells.contains(cell) ? 2 * 3600 : 6 * 3600
            if let saved, request.now.timeIntervalSince(saved.savedAt) < refreshAfter {
                snapshot.forecasts[cell] = saved.value
            } else if let fresh = try? await weather.forecast(for: cell, now: request.now) {
                forecasts.set(fresh, for: cell.key, now: request.now)
                snapshot.forecasts[cell] = fresh
            } else if let saved {
                // 取れなかったら、古いまま使う（画面に取得の時刻を出す）
                snapshot.forecasts[cell] = saved.value
            } else {
                snapshot.weatherFailed = true
                #if DEBUG
                // 確認用: 天気だけ見本にして、予定と場所は実データで流す（-debug-sample-weather YES）
                if ProcessInfo.processInfo.arguments.contains("-debug-sample-weather") {
                    snapshot.forecasts[cell] = DemoData.sampleForecast(for: cell, fetchedAt: request.now, calendar: request.calendar)
                }
                #endif
            }
        }

        // スポット: 近い日の場所だけ（先の日は、その日を開いたときに探す）
        input.forecasts = snapshot.forecasts
        for place in WeekPlanner.requiredSpotPlaces(input) {
            snapshot.spots[PlaceCell.fine(place.coordinate)] = await spots(around: place.coordinate, request: request)
        }
        return snapshot
    }

    /// 近くのスポット。設定（屋根のあるところ・ジム）が変わったら探し直す
    func spots(around coordinate: Coordinate, request: WorldRequest) async -> NearbySpots {
        let preferences = request.preferences
        let signature = "\(preferences.coveredWalkEnabled)-\(preferences.gymEnabled)-\(preferences.gymNames.joined(separator: ","))"
        let key = "\(PlaceCell.fine(coordinate).key)|\(signature)"
        if let saved = spots.entry(for: key, now: request.now) {
            return saved.value
        }
        let found = await finder.spots(around: coordinate, preferences: preferences)
        spots.set(found, for: key, now: request.now)
        return found
    }

    /// 予定の場所の解決（仕様書 §5-3 の手順 1〜3）。前後の予定や拠点からの引き継ぎは HitoashiKit が行う
    private func resolvePlaces(of events: [PlanEvent], bases: [BasePlace]) async -> [String: ResolvedPlace] {
        var places: [String: ResolvedPlace] = [:]
        let baseCoordinates = bases.map(\.coordinate)
        var lookups = 0
        for event in events {
            if let coordinate = event.coordinate {
                let name = (event.locationText ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                places[event.id] = ResolvedPlace(coordinate: coordinate, name: name, source: .eventCoordinate)
                continue
            }
            // URL・電話番号・会議室名などは、ここで止めて送らない
            guard case .geocodable(let text) = LocationTextScreener.screen(event.locationText) else {
                continue
            }
            let hit: GeocodeHit?
            if let saved = geocodes.entry(for: text, now: .now) {
                hit = saved.value
            } else if lookups < 10 {
                lookups += 1
                hit = await finder.geocode(text, near: baseCoordinates.first)
                geocodes.set(hit, for: text, now: .now)
            } else {
                hit = nil
            }
            guard let hit, LocationTextScreener.acceptsGeocode(
                text: text,
                result: hit.coordinate,
                resultPlaceNames: hit.placeNames,
                bases: baseCoordinates
            ) else {
                continue
            }
            places[event.id] = ResolvedPlace(coordinate: hit.coordinate, name: text, source: .geocoded)
        }
        return places
    }

    /// 保存したもの（予報・スポット・場所）をすべて消す
    func eraseAll() {
        forecasts.removeAll()
        spots.removeAll()
        geocodes.removeAll()
    }
}
