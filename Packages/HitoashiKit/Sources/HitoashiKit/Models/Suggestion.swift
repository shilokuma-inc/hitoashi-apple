import Foundation

/// 動き方（仕様書 §5-6）
public enum Activity: String, Hashable, Sendable, Codable, CaseIterable {
    /// 歩く（外）
    case walk
    /// 屋根のあるところを歩く
    case coveredWalk
    /// 走る
    case jog
    /// いつものジム
    case gym
    /// その場で（ストレッチ・階段）
    case onTheSpot

    public var isOutdoor: Bool { self == .walk || self == .jog }

    /// 着替えなどの支度がいるか
    public var needsGear: Bool { self == .jog || self == .gym }

    public var minimumMinutes: Int {
        switch self {
        case .walk, .coveredWalk:
            10
        case .jog:
            20
        case .gym:
            30
        case .onTheSpot:
            5
        }
    }
}

public enum SpotCategory: String, Hashable, Sendable, Codable {
    case park
    case station
    case covered
    case gym
    case track
}

/// 近くのスポット（MapKit の検索結果を写したもの）
public struct Spot: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var coordinate: Coordinate
    public var category: SpotCategory

    public init(id: String, name: String, coordinate: Coordinate, category: SpotCategory) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.category = category
    }
}

/// 1 つの場所のまわりのスポット（種類ごと。近い順）
public struct NearbySpots: Hashable, Sendable, Codable {
    public var parks: [Spot]
    public var stations: [Spot]
    public var covered: [Spot]
    public var gyms: [Spot]
    public var tracks: [Spot]

    public init(parks: [Spot] = [], stations: [Spot] = [], covered: [Spot] = [], gyms: [Spot] = [], tracks: [Spot] = []) {
        self.parks = parks
        self.stations = stations
        self.covered = covered
        self.gyms = gyms
        self.tracks = tracks
    }

    public static let empty = NearbySpots()
}

/// 歩き方
public enum WalkRoute: String, Hashable, Sendable, Codable {
    /// 行って戻る
    case roundTrip
    /// 片道（駅まで）
    case oneWay
    /// 行き先なし（近くをひと回り）
    case loop
}

/// 何を・どこで・何分
public struct StepPlan: Hashable, Sendable {
    public var activity: Activity
    public var minutes: Int
    public var spot: Spot?
    public var route: WalkRoute
    /// スポットまでの片道の徒歩（分）
    public var walkMinutesToSpot: Int
    /// スポットまでの直線距離（m）
    public var distanceMeters: Double

    public init(
        activity: Activity,
        minutes: Int,
        spot: Spot? = nil,
        route: WalkRoute = .loop,
        walkMinutesToSpot: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.activity = activity
        self.minutes = minutes
        self.spot = spot
        self.route = route
        self.walkMinutesToSpot = walkMinutesToSpot
        self.distanceMeters = distanceMeters
    }

    /// 動く時間帯の長さ（分）。屋内の施設は、行き帰りの徒歩を足す
    public var windowMinutes: Int {
        switch activity {
        case .walk, .onTheSpot:
            minutes
        case .coveredWalk, .jog, .gym:
            minutes + walkMinutesToSpot * 2
        }
    }
}

/// 決め手（「なぜ今か」）。値は内部の単位のまま持ち、文面にするときに直す
public enum Headline: Hashable, Sendable {
    case alert
    case heat(apparent: Double)
    case cold(apparent: Double)
    /// 雨は ◯ 時まで（時は現地時刻の 0〜23）
    case rainUntil(hour: Int)
    /// 雨は ◯ 時から
    case rainFrom(hour: Int)
    /// 降水確率が高い（屋内）
    case rainLikely(chance: Double)
    /// 降るかもしれない（外は気をつけて）
    case rainPossible(chance: Double)
    /// 煙・砂ぼこり（屋内）
    case smoke
    case windy(speed: Double)
    case dark
    case uv(Int)
    /// 日没まで ◯ 分
    case sunsetIn(minutes: Int)
    /// 夕暮れの中を歩ける
    case goldenHour
    /// 歩くのにちょうどいい
    case comfortable(apparent: Double)
}

/// 代わりの案
public struct AlternatePlan: Hashable, Sendable {
    public enum Label: String, Hashable, Sendable {
        /// 雨なら（屋内）
        case ifRain
        /// 晴れたら（外）
        case ifClear
    }

    public var label: Label
    public var plan: StepPlan

    public init(label: Label, plan: StepPlan) {
        self.label = label
        self.plan = plan
    }
}

/// ひと足（提案）
public struct Suggestion: Identifiable, Hashable, Sendable {
    /// 空き時間の id と同じ
    public var id: String
    public var slot: Slot
    public var plan: StepPlan
    /// 動く時間帯（「いつから」）
    public var window: DateInterval
    public var verdict: Verdict
    /// 窓の快適さ（0〜100）
    public var comfort: Double
    /// 決め手（効いた順に 2 つまで）
    public var headlines: [Headline]
    public var alternate: AlternatePlan?
    /// ほかの場所の候補
    public var otherSpots: [Spot]
    /// 判定に使った予報を取得した時刻
    public var forecastFetchedAt: Date
    /// 窓にかかる時間の、降水確率のいちばん高い値（通知で言い切ってよいかの判断に使う）
    public var maxPrecipitationChance: Double

    public init(
        id: String,
        slot: Slot,
        plan: StepPlan,
        window: DateInterval,
        verdict: Verdict,
        comfort: Double,
        headlines: [Headline],
        alternate: AlternatePlan?,
        otherSpots: [Spot],
        forecastFetchedAt: Date,
        maxPrecipitationChance: Double
    ) {
        self.id = id
        self.slot = slot
        self.plan = plan
        self.window = window
        self.verdict = verdict
        self.comfort = comfort
        self.headlines = headlines
        self.alternate = alternate
        self.otherSpots = otherSpots
        self.forecastFetchedAt = forecastFetchedAt
        self.maxPrecipitationChance = maxPrecipitationChance
    }

    /// 休む（外へ出る案を出さない）
    public var isRest: Bool { verdict.level == .rest }
}
