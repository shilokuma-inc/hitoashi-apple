//
//  LogScreen.swift
//  Hitoashi
//
//  記録（仕様書 §4-4）。今週の回数と、本人が決めた目標。達成の演出はしない。天気の値は残さない。
//

import HitoashiKit
import SwiftUI

struct LogScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let logs = model.logs
        let week = WeekSummary(logs: logs, now: model.now, calendar: model.calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("記録")
                    .type(.display)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("今週")
                    .type(.captionStrong)
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 14)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(week.doneCount)")
                        .type(.display)
                    Text("/ \(model.preferences.weeklyTarget.rawValue)回")
                        .type(.title)
                        .foregroundStyle(Palette.ink2)
                }
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "今週 \(week.doneCount)回、目標 \(model.preferences.weeklyTarget.rawValue)回"))
                WeekBand(week: week)
                    .padding(.top, 14)
                legend(week)
                    .padding(.top, 10)
                if logs.isEmpty {
                    Text("まだ記録がありません。ひと足の「行く」を押すと、ここに残ります。")
                        .type(.sub)
                        .foregroundStyle(Palette.ink2)
                        .padding(.top, 28)
                } else {
                    list(logs)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.ground)
    }

    private func legend(_ week: WeekSummary) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Rectangle().fill(Palette.ink).frame(width: 10, height: 10)
                Text("外 \(week.outdoorCount)回")
            }
            HStack(spacing: 4) {
                Rectangle().strokeBorder(Palette.ink, lineWidth: 2).frame(width: 10, height: 10)
                Text("屋内 \(week.indoorCount)回")
            }
            Text("あわせて\(model.book.minutes(week.totalMinutes))")
        }
        .type(.caption)
        .monospacedDigit()
        .foregroundStyle(Palette.ink2)
    }

    @ViewBuilder
    private func list(_ logs: [StepLog]) -> some View {
        let thisWeek = logs.filter { model.calendar.isDate($0.date, equalTo: model.now, toGranularity: .weekOfYear) }
        let earlier = logs.filter { !model.calendar.isDate($0.date, equalTo: model.now, toGranularity: .weekOfYear) }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(thisWeek) { log in
                LogRow(log: log)
            }
            if !earlier.isEmpty {
                Text("それより前")
                    .type(.captionStrong)
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 20)
                    .padding(.bottom, 6)
                ForEach(earlier) { log in
                    LogRow(log: log)
                }
            }
        }
        .padding(.top, 18)
    }
}

/// 今週（月〜日）のまとめ
struct WeekSummary {
    struct Day {
        var label: String
        var isToday: Bool
        var hasOutdoor: Bool
        var hasIndoor: Bool
    }

    var days: [Day] = []
    var doneCount = 0
    var outdoorCount = 0
    var indoorCount = 0
    var totalMinutes = 0

    init(logs: [StepLog], now: Date, calendar: Calendar) {
        var monday = calendar
        monday.firstWeekday = 2
        guard let week = monday.dateInterval(of: .weekOfYear, for: now) else {
            return
        }
        let done = logs.filter { $0.outcome == .done && week.contains($0.date) }
        doneCount = done.count
        outdoorCount = done.filter(\.isOutdoor).count
        indoorCount = done.count - outdoorCount
        totalMinutes = done.map(\.minutes).reduce(0, +)
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = calendar.timeZone
        for offset in 0..<7 {
            guard let day = monday.date(byAdding: .day, value: offset, to: week.start) else {
                continue
            }
            let ofDay = done.filter { monday.isDate($0.date, inSameDayAs: day) }
            days.append(
                Day(
                    label: day.formatted(style),
                    isToday: monday.isDate(day, inSameDayAs: now),
                    hasOutdoor: ofDay.contains(where: \.isOutdoor),
                    hasIndoor: ofDay.contains { !$0.isOutdoor }
                )
            )
        }
    }
}

/// 週の帯。1 本の帯を 7 つに区切る。外は黒の塗り、屋内は黒い枠（斜線は「雨」の意味だけに使う）
struct WeekBand: View {
    var week: WeekSummary

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(week.days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 5) {
                    ZStack {
                        Rectangle().strokeBorder(Palette.faint, lineWidth: 0.5)
                        if day.hasOutdoor {
                            Rectangle().fill(Palette.ink)
                        } else if day.hasIndoor {
                            Rectangle().strokeBorder(Palette.ink, lineWidth: 2)
                        }
                    }
                    .frame(height: 18)
                    Text(day.label)
                        .type(.micro)
                        .fontWeight(day.isToday ? .bold : .regular)
                        .foregroundStyle(day.isToday ? Palette.ink : Palette.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LogRow: View {
    @Environment(AppModel.self) private var model
    var log: StepLog

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(dateText)
                .type(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.ink2)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(log.title)
                    .type(.body)
                    .foregroundStyle(log.outcome == .skipped ? Palette.ink2 : Palette.ink)
                Text(statusText)
                    .type(.caption)
                    .foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Text(model.book.minutes(log.minutes))
                .type(.sub)
                .monospacedDigit()
                .foregroundStyle(log.outcome == .skipped ? Palette.ink2 : Palette.ink)
        }
        .padding(.vertical, 8)
        .ruledRow()
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        var style = Date.FormatStyle.dateTime.day().weekday(.abbreviated)
        style.timeZone = model.calendar.timeZone
        return log.date.formatted(style)
    }

    private var statusText: String {
        let place = log.isOutdoor ? String(localized: "外") : String(localized: "屋内")
        switch log.outcome {
        case .done:
            return place
        case .started:
            return String(localized: "\(place)・まだ答えていません")
        case .skipped:
            return String(localized: "\(place)・やらなかった")
        }
    }
}
