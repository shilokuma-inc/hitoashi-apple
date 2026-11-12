import Foundation

/// カレンダーから読んだ予定（EventKit の値を写したもの）
public struct PlanEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// 場所の欄の文字列
    public var locationText: String?
    /// 予定が持っている座標（「マップ」から場所を選んだ予定）
    public var coordinate: Coordinate?
    public var isCanceled: Bool
    /// 自分が辞退した予定
    public var isDeclined: Bool
    public var calendarID: String

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        locationText: String? = nil,
        coordinate: Coordinate? = nil,
        isCanceled: Bool = false,
        isDeclined: Bool = false,
        calendarID: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.locationText = locationText
        self.coordinate = coordinate
        self.isCanceled = isCanceled
        self.isDeclined = isDeclined
        self.calendarID = calendarID
    }
}

/// 拠点の種類
public enum BaseKind: String, Hashable, Sendable, Codable, CaseIterable {
    case home
    case work
    case extra
}

/// 利用者が登録した拠点（仕様書 §5-3）
public struct BasePlace: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var kind: BaseKind
    public var name: String
    public var coordinate: Coordinate

    public init(id: String, kind: BaseKind, name: String, coordinate: Coordinate) {
        self.id = id
        self.kind = kind
        self.name = name
        self.coordinate = coordinate
    }
}

/// 場所がどうやって決まったか（仕様書 §5-3 の手順）
public enum PlaceSource: Hashable, Sendable {
    /// 予定の座標
    case eventCoordinate
    /// 利用者が教えた場所
    case remembered
    /// 文字列のジオコーディング
    case geocoded
    /// 前後の予定から引き継いだ
    case inherited
    /// 終日の予定の場所（その日の拠点）
    case dayBase
    /// 登録した拠点
    case base(BaseKind)
}

/// 予定や空き時間の「場所」
public struct ResolvedPlace: Hashable, Sendable {
    public var coordinate: Coordinate
    public var name: String
    public var source: PlaceSource

    public init(coordinate: Coordinate, name: String, source: PlaceSource) {
        self.coordinate = coordinate
        self.name = name
        self.source = source
    }

    public var cell: PlaceCell { PlaceCell(coordinate) }
}

/// 1 日の計算に使う、整えた予定（重なりをまとめ、除外や移動の印を付けたもの）
public struct DayEvent: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var locationText: String?
    public var place: ResolvedPlace?
    /// 題名が除外語に当たった（前後に提案しない）
    public var suppressesSuggestions: Bool
    /// 移動の予定（そのあとの空き時間は次の予定の場所で考える）
    public var isTransit: Bool
    /// 場所なしの「昼」「ランチ」の予定（昼休みそのものとして扱う）
    public var isLunchBreak: Bool

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        locationText: String? = nil,
        place: ResolvedPlace? = nil,
        suppressesSuggestions: Bool = false,
        isTransit: Bool = false,
        isLunchBreak: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.locationText = locationText
        self.place = place
        self.suppressesSuggestions = suppressesSuggestions
        self.isTransit = isTransit
        self.isLunchBreak = isLunchBreak
    }
}
