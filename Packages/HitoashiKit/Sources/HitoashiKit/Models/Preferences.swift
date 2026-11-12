import Foundation

/// 空き時間の種類（仕様書 §5-4）
public enum SlotKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// 昼休み
    case lunch
    /// 予定の合間
    case between
    /// 最後の予定のあと
    case afterLast
    /// 朝いちばんの予定の前
    case beforeFirst
    /// 予定のない日
    case freeDay
}

/// 週に何回知らせるか（通知の回数と、記録の目標に使う）
public enum WeeklyTarget: Int, Hashable, Sendable, Codable, CaseIterable {
    case two = 2
    case three = 3
    case five = 5
    case everyday = 7
}

/// 暗くなったあとの扱い
public enum AfterDarkPolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// 駅までの道を歩く
    case walkToStation
    /// 屋内にする
    case indoor
}

/// 前夜のお知らせ
public enum EveningNoticePolicy: String, Hashable, Sendable, Codable, CaseIterable {
    /// 準備が要るときだけ
    case whenPreparationNeeded
    case always
    case never
}

/// 利用者の設定
public struct Preferences: Hashable, Sendable, Codable {
    public var weeklyTarget: WeeklyTarget
    /// 1 回の長さ（分）
    public var durationMinutes: Int
    /// 提案してよい空き時間の種類
    public var allowedSlots: Set<SlotKind>
    /// 昼休み（0 時からの分）
    public var lunchStartMinutes: Int
    public var lunchEndMinutes: Int
    /// 動ける時間帯（0 時からの分）
    public var activeStartMinutes: Int
    public var activeEndMinutes: Int
    public var coveredWalkEnabled: Bool
    public var jogEnabled: Bool
    public var gymEnabled: Bool
    /// いつものジムの名前（チェーン名など）
    public var gymNames: [String]
    public var afterDark: AfterDarkPolicy
    /// 提案しない題名（除外語）
    public var excludedTitleWords: [String]
    public var dayNoticeEnabled: Bool
    public var eveningNotice: EveningNoticePolicy
    /// 前夜のお知らせの時刻（0 時からの分）
    public var eveningNoticeMinutes: Int
    /// 通知に予定の題名を入れる
    public var includesEventTitleInNotice: Bool

    public init(
        weeklyTarget: WeeklyTarget = .three,
        durationMinutes: Int = 20,
        allowedSlots: Set<SlotKind> = [.lunch, .between, .afterLast, .freeDay],
        lunchStartMinutes: Int = 12 * 60,
        lunchEndMinutes: Int = 13 * 60,
        activeStartMinutes: Int = 6 * 60 + 30,
        activeEndMinutes: Int = 21 * 60 + 30,
        coveredWalkEnabled: Bool = true,
        jogEnabled: Bool = false,
        gymEnabled: Bool = false,
        gymNames: [String] = [],
        afterDark: AfterDarkPolicy = .walkToStation,
        excludedTitleWords: [String] = Preferences.defaultExcludedTitleWords,
        dayNoticeEnabled: Bool = true,
        eveningNotice: EveningNoticePolicy = .whenPreparationNeeded,
        eveningNoticeMinutes: Int = 21 * 60,
        includesEventTitleInNotice: Bool = false
    ) {
        self.weeklyTarget = weeklyTarget
        self.durationMinutes = durationMinutes
        self.allowedSlots = allowedSlots
        self.lunchStartMinutes = lunchStartMinutes
        self.lunchEndMinutes = lunchEndMinutes
        self.activeStartMinutes = activeStartMinutes
        self.activeEndMinutes = activeEndMinutes
        self.coveredWalkEnabled = coveredWalkEnabled
        self.jogEnabled = jogEnabled
        self.gymEnabled = gymEnabled
        self.gymNames = gymNames
        self.afterDark = afterDark
        self.excludedTitleWords = excludedTitleWords
        self.dayNoticeEnabled = dayNoticeEnabled
        self.eveningNotice = eveningNotice
        self.eveningNoticeMinutes = eveningNoticeMinutes
        self.includesEventTitleInNotice = includesEventTitleInNotice
    }

    /// 既定の除外語（仕様書 §5-2）。当たった予定の前後には提案しない
    public static let defaultExcludedTitleWords: [String] = [
        "通夜", "葬儀", "告別式", "法事", "病院", "クリニック", "歯科", "歯医者", "健診", "人間ドック", "献血", "手術",
        "飲み会", "忘年会", "新年会", "送別会", "歓迎会", "懇親会", "会食", "送り", "迎え",
        "funeral", "hospital", "clinic", "dentist", "surgery"
    ]
}
