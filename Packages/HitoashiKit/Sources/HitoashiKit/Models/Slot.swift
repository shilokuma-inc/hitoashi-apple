import Foundation

/// 空き時間（仕様書 §5-4）。動ける時間帯から予定を引いた、連続した区間 1 つにつき 1 件
public struct Slot: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: SlotKind
    public var interval: DateInterval
    public var place: ResolvedPlace
    /// 昼食のために先に引く分（昼休みのとき 30 分）。窓の位置は縛らず、長さの条件にだけ使う
    public var reservedMinutes: Int
    /// 直前の予定の終了（「15:00 に終わる予定のあと」の表示と、通知の時刻に使う）
    public var previousEventEnd: Date?
    public var previousEventTitle: String?
    /// 次の予定の開始
    public var nextEventStart: Date?

    public init(
        id: String,
        kind: SlotKind,
        interval: DateInterval,
        place: ResolvedPlace,
        reservedMinutes: Int = 0,
        previousEventEnd: Date? = nil,
        previousEventTitle: String? = nil,
        nextEventStart: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.interval = interval
        self.place = place
        self.reservedMinutes = reservedMinutes
        self.previousEventEnd = previousEventEnd
        self.previousEventTitle = previousEventTitle
        self.nextEventStart = nextEventStart
    }

    /// 動くのに使える長さ（分）
    public var usableMinutes: Int {
        Int(interval.duration / 60) - reservedMinutes
    }
}
