//
//  TimelineBuilder.swift
//  Hitoashi
//
//  1 日の計画を、タイムラインの行（予定・ひと足・その間）に並べる。
//

import Foundation
import HitoashiKit

/// タイムラインの 1 行
struct TimelineRow: Identifiable {
    enum Content {
        case event(DayEvent)
        case step(Suggestion, isTop: Bool)
        /// 行と行の間（天気の帯だけが通る）
        case gap
    }

    var id: String
    var content: Content
    /// この行が受け持つ時間（天気の帯を比例分割するのに使う）
    var interval: DateInterval
    /// 天気を見る地点
    var cell: PlaceCell?
}

enum TimelineBuilder {
    static func rows(for plan: DayPlan, resolve: (Suggestion) -> Suggestion) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        var previous: TimelineRow?
        for item in plan.items {
            let row: TimelineRow
            switch item {
            case .event(let event):
                row = TimelineRow(
                    id: item.id,
                    content: .event(event),
                    interval: DateInterval(start: event.start, end: max(event.end, event.start)),
                    cell: event.place?.cell
                )
            case .suggestion(let suggestion):
                let resolved = resolve(suggestion)
                row = TimelineRow(
                    id: item.id,
                    content: .step(resolved, isTop: suggestion.id == plan.top?.id),
                    interval: resolved.window,
                    cell: suggestion.slot.place.cell
                )
            }
            if let previous, row.interval.start > previous.interval.end {
                rows.append(
                    TimelineRow(
                        id: "gap-\(previous.id)",
                        content: .gap,
                        interval: DateInterval(start: previous.interval.end, end: row.interval.start),
                        cell: previous.cell ?? row.cell
                    )
                )
            }
            rows.append(row)
            previous = row
        }
        return rows
    }

    /// 行と行の間の余白。空いた時間に比例させる（分 × 0.2、6〜28pt）
    static func gapHeight(for interval: DateInterval) -> CGFloat {
        min(28, max(6, interval.duration / 60 * 0.2))
    }
}

enum PlaceText {
    /// 予定の場所の 1 行（「渋谷 神南オフィス」「オンライン（職場）」）。
    /// 拠点として扱っている場所は、丸かっこで添える
    static func line(for event: DayEvent) -> String {
        let firstLine = (event.locationText ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let shown: String
        switch LocationTextScreener.screen(event.locationText) {
        case .online:
            shown = String(localized: "オンライン")
        case .meetingRoom, .geocodable:
            shown = firstLine
        case .unusable:
            shown = ""
        }
        guard let place = event.place else {
            return shown
        }
        let treatedAs: String?
        switch place.source {
        case .base(.work):
            treatedAs = String(localized: "職場")
        case .base(.home):
            treatedAs = String(localized: "自宅")
        case .base(.extra), .dayBase:
            treatedAs = place.name
        case .inherited:
            treatedAs = String(localized: "\(place.name)の近く")
        case .eventCoordinate, .remembered, .geocoded:
            treatedAs = nil
        }
        guard let treatedAs else {
            return shown
        }
        return shown.isEmpty ? treatedAs : "\(shown)（\(treatedAs)）"
    }
}
