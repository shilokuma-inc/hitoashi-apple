import Foundation

/// 予定の「場所」の文字列を、ジオコーディングに送る前にふるい分ける（仕様書 §5-3）。
/// 会議の URL や電話番号を Apple に送らないため、また会議室名を別の街に当てないため。
public enum LocationTextScreener {
    public enum Result: Hashable, Sendable {
        /// ジオコーディングしてよい（送る文字列）
        case geocodable(String)
        /// オンライン会議。前後の予定からは引き継がず、その日の拠点で考える
        case online
        /// 会議室名。その日の拠点が職場なら職場として扱う
        case meetingRoom
        /// 場所として使えない（空・長すぎる・電話番号など）
        case unusable
    }

    private static let onlineWords = ["zoom", "meet", "teams", "webex", "オンライン", "online", "リモート", "remote"]
    private static let roomWords = ["会議室", "room", "rm", "floor"]

    public static func screen(_ text: String?) -> Result {
        guard let text else {
            return .unusable
        }
        // 複数行は 1 行目だけ使う
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unusable
        }
        let lower = trimmed.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") || onlineWords.contains(where: lower.contains) {
            return .online
        }
        if lower.contains("@") || looksLikePhoneNumber(lower) || trimmed.count > 100 {
            return .unusable
        }
        if trimmed.count <= 20, looksLikeMeetingRoom(lower) {
            return .meetingRoom
        }
        return .geocodable(removingTrailingFloor(trimmed))
    }

    /// 「8F Fuji」「3階 大会議室」「会議室 A」「Room 2」など。
    /// 階の表記は、先頭にあるときだけ会議室名とみなす（「渋谷ヒカリエ 11F」は建物の名前で探せる）
    static func looksLikeMeetingRoom(_ lower: String) -> Bool {
        if roomWords.contains(where: lower.contains) {
            return true
        }
        let digits = lower.prefix(while: \.isNumber)
        guard !digits.isEmpty else {
            return false
        }
        let rest = lower.dropFirst(digits.count).drop(while: { $0 == " " })
        return rest.hasPrefix("f") || rest.hasPrefix("階")
    }

    /// 末尾の階の表記を外す（「渋谷ヒカリエ 11F」→「渋谷ヒカリエ」）
    static func removingTrailingFloor(_ text: String) -> String {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2, let last = parts.last else {
            return text
        }
        let lower = last.lowercased()
        let digits = lower.prefix(while: \.isNumber)
        let suffix = lower.dropFirst(digits.count)
        guard !digits.isEmpty, suffix == "f" || suffix == "階" else {
            return text
        }
        return parts.dropLast().joined(separator: " ")
    }

    /// 数字と区切りだけで、数字が 9 桁以上
    static func looksLikePhoneNumber(_ lower: String) -> Bool {
        let allowed = Set("0123456789-+() ")
        guard lower.allSatisfy(allowed.contains) else {
            return false
        }
        return lower.filter(\.isNumber).count >= 9
    }

    /// ジオコーディングの結果を使ってよいか。
    /// 拠点から 50km より遠く、元の文字列に結果の地名（都道府県・市区町村）が含まれなければ捨てる
    public static func acceptsGeocode(
        text: String,
        result: Coordinate,
        resultPlaceNames: [String],
        bases: [Coordinate]
    ) -> Bool {
        guard !bases.isEmpty else {
            return true
        }
        let nearest = bases.map { $0.distance(to: result) }.min() ?? 0
        if nearest <= 50_000 {
            return true
        }
        return resultPlaceNames.contains { !$0.isEmpty && text.contains($0) }
    }
}
