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

struct PlaceFinder {
    /// 場所の文字列から位置を引く。拠点の周辺を優先する
    func geocode(_ text: String, near base: Coordinate?) async -> GeocodeHit? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let base {
            request.region = MKCoordinateRegion(center: base.clLocation, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            return nil
        }
        return Self.hit(item, fallbackName: text)
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

    /// 近くのスポット（種類ごと。近い順）
    func spots(around origin: Coordinate, preferences: Preferences) async -> NearbySpots {
        var result = NearbySpots()
        result.parks = await points(around: origin, radius: 1300, categories: [.park, .nationalPark, .beach], as: .park)
        result.stations = await points(around: origin, radius: 1500, categories: [.publicTransport], as: .station)
            .filter { $0.name.hasSuffix("駅") || $0.name.localizedCaseInsensitiveContains("station") }
        if preferences.coveredWalkEnabled {
            var covered = await points(around: origin, radius: 450, categories: [.museum, .library, .aquarium], as: .covered)
            for query in Self.coveredQueries {
                covered += await named(query, around: origin, radius: 450, as: .covered)
            }
            result.covered = Self.tidy(covered, origin: origin, radius: 450)
        }
        if preferences.gymEnabled {
            var gyms: [Spot] = []
            if preferences.gymNames.isEmpty {
                gyms = await points(around: origin, radius: 1500, categories: [.fitnessCenter], as: .gym)
            } else {
                for name in preferences.gymNames.prefix(3) {
                    gyms += await named(name, around: origin, radius: 1500, as: .gym)
                }
            }
            result.gyms = Self.tidy(gyms, origin: origin, radius: 1500)
        }
        return result
    }

    // MARK: - 中身

    private static var coveredQueries: [String] {
        Locale.current.language.languageCode?.identifier == "ja" ? ["ショッピングモール", "地下街"] : ["shopping mall"]
    }

    private func points(
        around origin: Coordinate,
        radius: CLLocationDistance,
        categories: [MKPointOfInterestCategory],
        as category: SpotCategory
    ) async -> [Spot] {
        let request = MKLocalPointsOfInterestRequest(center: origin.clLocation, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return Self.tidy(items.compactMap { Self.spot($0, category: category) }, origin: origin, radius: radius)
    }

    private func named(_ query: String, around origin: Coordinate, radius: CLLocationDistance, as category: SpotCategory) async -> [Spot] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: origin.clLocation, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
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

    /// 半径の外と重複を外し、近い順に 8 件まで
    private static func tidy(_ spots: [Spot], origin: Coordinate, radius: CLLocationDistance) -> [Spot] {
        var seen: Set<String> = []
        return spots
            .filter { origin.distance(to: $0.coordinate) <= radius && seen.insert($0.name).inserted }
            .sorted { origin.distance(to: $0.coordinate) < origin.distance(to: $1.coordinate) }
            .prefix(8)
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
