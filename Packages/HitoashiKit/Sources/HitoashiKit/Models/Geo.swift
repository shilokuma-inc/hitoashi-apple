import Foundation

/// 緯度・経度
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 2 点の間の直線距離（m）
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(haversine)))
    }

    /// 歩く時間の見積もり（分）。直線距離 × 1.3 ÷ 分速 80m（仕様書 §5-7）
    public func walkingMinutes(to other: Coordinate) -> Int {
        Int((distance(to: other) * 1.3 / 80).rounded(.up))
    }
}

/// 天気の取得と保存の単位。座標を 0.02°（約 2km）の升目に丸めたもの（仕様書 §5-3）
public struct PlaceCell: Hashable, Sendable, Codable {
    public static let size = 0.02

    public var latIndex: Int
    public var lonIndex: Int

    public init(_ coordinate: Coordinate) {
        latIndex = Int((coordinate.latitude / Self.size).rounded(.down))
        lonIndex = Int((coordinate.longitude / Self.size).rounded(.down))
    }

    /// スポットの検索と保存の単位。0.005°（約 500m）の細かい升目。
    /// 天気は 2km の升目で足りるが、近くのスポットは場所が 1km ずれると変わるので、細かく持つ
    public static func fine(_ coordinate: Coordinate) -> PlaceCell {
        var cell = PlaceCell(coordinate)
        cell.latIndex = Int((coordinate.latitude / fineSize).rounded(.down))
        cell.lonIndex = Int((coordinate.longitude / fineSize).rounded(.down))
        return cell
    }

    public static let fineSize = 0.005

    /// 升目の中心
    public var center: Coordinate {
        Coordinate(
            latitude: (Double(latIndex) + 0.5) * Self.size,
            longitude: (Double(lonIndex) + 0.5) * Self.size
        )
    }

    /// 保存のキーに使う文字列
    public var key: String { "\(latIndex)_\(lonIndex)" }
}
