//
//  PlaceFinder.swift
//  Hitoashi
//
//  場所を調べる（MapKit）。予定の場所の文字列から位置を引く、近くのスポットを探す、拠点の候補を探す。
//  送るのは、ふるい分けを通った場所の文字列と座標だけ（仕様書 §5-3、§5-13）。
//

import CoreLocation
import HitoashiKit
import MapKit

/// 文字列から引いた場所
struct GeocodeHit: Codable, Hashable, Sendable {
    var coordinate: Coordinate
    var name: String
    /// 都道府県・市区町村の名前（遠くに当たった結果を捨てるかの判断に使う）
    var placeNames: [String]
}

/// 場所の文字列から位置を引いた結果。「見つからなかった」と「調べられなかった」を分ける
/// （通信の失敗を「見つからなかった」として覚えてしまわないため）
enum GeocodeOutcome: Sendable {
    /// 候補（MapKit が返した順。先頭が遠すぎることがあるので、使えるものを呼び出し側で選ぶ）
    case found([GeocodeHit])
    case notFound
    case failed
}

struct PlaceFinder {
    /// 場所の文字列から位置を引く。拠点の周辺を優先する
    func geocode(_ text: String, near base: Coordinate?) async -> GeocodeOutcome {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let base {
            request.region = MKCoordinateRegion(center: base.clLocation, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        guard let items = await Self.mapItems(MKLocalSearch(request: request)) else {
            return .failed
        }
        guard !items.isEmpty else {
            return .notFound
        }
        return .found(items.prefix(5).map { Self.hit($0, fallbackName: text) })
    }

    /// 拠点の登録のための検索（住所・駅名・建物の名前）
    func search(_ query: String, near base: Coordinate?) async -> [GeocodeHit] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let base {
            request.region = MKCoordinateRegion(center: base.clLocation, latitudinalMeters: 100_000, longitudinalMeters: 100_000)
        }
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return items.prefix(8).map { Self.hit($0, fallbackName: query) }
    }

    /// 座標から、地名（「世田谷区 代沢」のような短い名前）を引く
    func placeName(at coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else {
            return nil
        }
        return item.addressRepresentations?.cityWithContext ?? item.address?.shortAddress ?? item.name
    }

    /// 近くのスポット（種類ごと。近い順）。
    /// `margin` は、探す範囲に足す余裕（m）。升目の中心から探して升目のどこからでも使えるようにするとき、升目の半分の対角を渡す。
    /// `isComplete` が false のときは、どれかの検索が通信の失敗などで終わっている（結果を保存しないこと）
    func spots(
        around origin: Coordinate,
        margin: CLLocationDistance = 0,
        preferences: Preferences
    ) async -> (spots: NearbySpots, isComplete: Bool) {
        let parkRadius = 1300 + margin
        let farRadius = 1500 + margin
        let coveredRadius = 450 + margin
        var result = NearbySpots()
        var isComplete = true
        // 失敗した検索は、空として扱いつつ、失敗したことを覚えておく
        func take(_ found: [Spot]?) -> [Spot] {
            if found == nil {
                isComplete = false
            }
            return found ?? []
        }
        result.parks = take(await points(around: origin, radius: parkRadius, categories: [.park, .nationalPark, .beach], as: .park))
        // 駅は「駅」という言葉で探す。種類（公共交通）だけで探すと、件数の上限までバス停とタクシー乗り場で埋まり、
        // 街なかでは駅が 1 件も返らない
        let stations = take(await named(Self.stationQuery, around: origin, radius: farRadius, as: .station, filter: [.publicTransport]))
        result.stations = Self.tidy(stations.filter { Self.isStationName($0.name) }, origin: origin, radius: farRadius)
        if preferences.coveredWalkEnabled {
            let halls: [MKPointOfInterestCategory] = [.museum, .library, .aquarium]
            var covered = take(await points(around: origin, radius: coveredRadius, categories: halls, as: .covered))
            for query in Self.coveredQueries {
                covered += take(await named(query, around: origin, radius: coveredRadius, as: .covered))
            }
            result.covered = Self.tidy(covered, origin: origin, radius: coveredRadius)
        }
        if preferences.gymEnabled {
            var gyms: [Spot] = []
            if preferences.gymNames.isEmpty {
                gyms = take(await points(around: origin, radius: farRadius, categories: [.fitnessCenter], as: .gym))
            } else {
                for name in preferences.gymNames.prefix(3) {
                    gyms += take(await named(name, around: origin, radius: farRadius, as: .gym))
                }
            }
            result.gyms = Self.tidy(gyms, origin: origin, radius: farRadius)
        }
        return (result, isComplete)
    }

    // MARK: - 中身

    private static var isJapanese: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    private static var coveredQueries: [String] {
        isJapanese ? ["ショッピングモール", "地下街"] : ["shopping mall"]
    }

    private static var stationQuery: String {
        isJapanese ? "駅" : "train station"
    }

    /// 駅の名前か。同じ検索で返るバス停・タクシー乗り場（「渋谷駅 - 3番のりば」「Shibuya Station Taxi」）を外す
    static func isStationName(_ name: String) -> Bool {
        let lower = name.lowercased()
        guard lower.contains("駅") || lower.contains("station") else {
            return false
        }
        return !["のりば", "乗り場", "乗場", "バス", "タクシー", "taxi", "bus"].contains(where: lower.contains)
    }

    /// MapKit の検索を走らせる。1 件も無いとき（`placemarkNotFound`）は空、通信の失敗などで調べられなかったときは nil
    private static func mapItems(_ search: MKLocalSearch) async -> [MKMapItem]? {
        do {
            return try await search.start().mapItems
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            return nil
        }
    }

    /// 種類で探す。調べられなかったときは nil
    private func points(
        around origin: Coordinate,
        radius: CLLocationDistance,
        categories: [MKPointOfInterestCategory],
        as category: SpotCategory
    ) async -> [Spot]? {
        let request = MKLocalPointsOfInterestRequest(center: origin.clLocation, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        guard let items = await Self.mapItems(MKLocalSearch(request: request)) else {
            return nil
        }
        return Self.tidy(items.compactMap { Self.spot($0, category: category) }, origin: origin, radius: radius)
    }

    /// 名前で探す（`filter` があれば、その種類の中から）。調べられなかったときは nil
    private func named(
        _ query: String,
        around origin: Coordinate,
        radius: CLLocationDistance,
        as category: SpotCategory,
        filter: [MKPointOfInterestCategory]? = nil
    ) async -> [Spot]? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let filter {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: filter)
        }
        request.region = MKCoordinateRegion(center: origin.clLocation, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        guard let items = await Self.mapItems(MKLocalSearch(request: request)) else {
            return nil
        }
        return items.compactMap { Self.spot($0, category: category) }
    }

    private static func spot(_ item: MKMapItem, category: SpotCategory) -> Spot? {
        guard let name = item.name, !name.isEmpty else {
            return nil
        }
        let coordinate = Coordinate(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
        let identifier = item.identifier?.rawValue ?? "\(name)@\(coordinate.latitude),\(coordinate.longitude)"
        return Spot(id: identifier, name: name, coordinate: coordinate, category: category)
    }

    /// 半径の外と重複を外し、近い順に 12 件まで
    private static func tidy(_ spots: [Spot], origin: Coordinate, radius: CLLocationDistance) -> [Spot] {
        var seen: Set<String> = []
        return spots
            .filter { origin.distance(to: $0.coordinate) <= radius && seen.insert($0.name).inserted }
            .sorted { origin.distance(to: $0.coordinate) < origin.distance(to: $1.coordinate) }
            .prefix(12)
            .map(\.self)
    }

    private static func hit(_ item: MKMapItem, fallbackName: String) -> GeocodeHit {
        let representations = item.addressRepresentations
        return GeocodeHit(
            coordinate: Coordinate(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude),
            name: item.name ?? fallbackName,
            placeNames: [representations?.regionName, representations?.cityName].compactMap(\.self)
        )
    }
}
