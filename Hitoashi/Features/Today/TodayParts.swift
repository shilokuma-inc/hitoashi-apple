//
//  TodayParts.swift
//  Hitoashi
//
//  きょうの画面の部品（日付の帯・休む日・今週の歩きどき・天気の帰属表示）。
//

import HitoashiKit
import SwiftUI

/// 日付の帯。今日から 10 日ぶん。天気記号は無料で全部見せる（WeatherKit の天気そのものには課金しない）
struct DayStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(model.plans, id: \.dayIndex) { plan in
                    Button {
                        model.selectedDay = plan.dayIndex
                    } label: {
                        DayCell(plan: plan, isSelected: plan.dayIndex == model.selectedDay)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.day.\(plan.dayIndex)")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        // 文字が大きくなりすぎると崩れるので、ここだけ上限を置く
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    var plan: DayPlan
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(plan.dayIndex == 0 ? String(localized: "今日") : weekday)
                .type(.micro)
                .foregroundStyle(Palette.ink2)
            Text(dayNumber)
                .type(.bodyStrong)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Palette.onInk : Palette.ink)
                .frame(width: 32, height: 32)
                .background(isSelected ? Palette.ink : .clear, in: Circle())
            // ひと足のある日の印は、数字の下の朱の横棒
            Rectangle()
                .fill(plan.candidates.isEmpty ? .clear : Palette.shu)
                .frame(width: 14, height: 3)
            if let forecast = plan.forecast {
                WeatherGlyph(kind: forecast.kind)
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .frame(height: 16)
            }
        }
        .frame(width: 50)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekday: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = model.calendar.timeZone
        return plan.day.formatted(style)
    }

    private var dayNumber: String {
        "\(model.calendar.component(.day, from: plan.day))"
    }

    private var accessibilityText: String {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.wide)
        style.timeZone = model.calendar.timeZone
        var parts = [plan.day.formatted(style)]
        if let forecast = plan.forecast {
            parts.append(model.book.weatherName(forecast.kind))
        }
        if !plan.candidates.isEmpty {
            parts.append(String(localized: "ひと足あり"))
        }
        return parts.joined(separator: "、")
    }
}

/// 休む日（仕様書 §4-3、§5-5）。警報は原文のまま出し、発表機関のページへのリンクを付ける。写真は使わない
struct RestDayBlock: View {
    var rest: RestDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let alert = rest.alerts.first {
                Text(alert.summary)
                    .type(.bodyStrong)
                    .foregroundStyle(Palette.ink)
                Text(alert.source)
                    .type(.caption)
                    .foregroundStyle(Palette.ink2)
                    .padding(.top, 2)
            }
            Text("きょうは休む日")
                .type(.heading)
                .foregroundStyle(Palette.ink)
                .padding(.top, rest.alerts.isEmpty ? 0 : 12)
            Text(rest.alerts.isEmpty ? "天気が荒れているので、外へ出る案は出しません。" : "警報が出ているので、外へ出る案は出しません。")
                .type(.sub)
                .foregroundStyle(Palette.ink2)
                .padding(.top, 6)
            Text("動きたくなったら、その場でストレッチを5分。")
                .type(.sub)
                .foregroundStyle(Palette.ink2)
            if let alert = rest.alerts.first, let url = alert.detailsURL {
                Link(destination: url) {
                    HStack {
                        Text("\(alert.source)の発表を見る")
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .type(.body)
                    .foregroundStyle(Palette.ink)
                    .ruledRow()
                }
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .accessibilityIdentifier("today.restDay")
    }
}

/// 今週の歩きどき（Pro）。7 日ぶんの外の窓から、快適さの順に 3 つ
struct OutlookSection: View {
    @Environment(AppModel.self) private var model
    var onOpen: (Suggestion) -> Void

    var body: some View {
        let best = model.outlook
        if !best.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("今週の歩きどき")
                    .type(.captionStrong)
                    .foregroundStyle(Palette.ink2)
                    .padding(.bottom, 6)
                ForEach(best) { suggestion in
                    Button {
                        onOpen(suggestion)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(dayText(suggestion.window.start))
                                .type(.captionStrong)
                                .foregroundStyle(Palette.ink2)
                                .frame(width: 54, alignment: .leading)
                            Text("\(model.book.time(suggestion.window.start)) \(model.book.title(for: suggestion.plan))")
                                .type(.sub)
                                .foregroundStyle(Palette.ink)
                                .monospacedDigit()
                            Spacer(minLength: 4)
                        }
                        .ruledRow()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
        }
    }

    private func dayText(_ date: Date) -> String {
        if model.calendar.isDate(date, inSameDayAs: model.now) {
            return String(localized: "今日")
        }
        var style = Date.FormatStyle.dateTime.day().weekday(.abbreviated)
        style.timeZone = model.calendar.timeZone
        return date.formatted(style)
    }
}

/// 天気データの帰属表示と、「加工したデータです」の一文（仕様書 §5-13）。
/// 見本を表示しているときは帰属表示を出さず、「見本のデータです」と出す
struct AttributionFooter: View {
    @Environment(AppModel.self) private var model
    var plan: DayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if model.isDemo {
                Text("見本のデータです。実際の天気ではありません。")
            } else {
                WeatherAttributionView()
                Text("Apple Weather のデータをもとに、ひとあしが判定しています。")
                if let fetched = plan.forecastFetchedAt {
                    Text("\(model.book.time(fetched))時点の予報です。")
                }
            }
        }
        .type(.note)
        .foregroundStyle(Palette.ink2)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

/// 予定を読めない・拠点が無い・予定が 1 件も無いときの案内（実データのときだけ）
struct SetupHints: View {
    @Environment(AppModel.self) private var model
    var plan: DayPlan
    @State private var editing: BaseKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.hasCalendarAccess {
                hint(
                    "予定を読めていません",
                    detail: model.canAskCalendar
                        ? "カレンダーを読むと、予定の前後の空き時間にひと足を出せます。"
                        : "端末の設定アプリで、ひとあしのカレンダーを「フルアクセス」にすると、予定を読めます。"
                ) {
                    if model.canAskCalendar {
                        Button("カレンダーを読ませる") {
                            Task { await model.requestCalendarAccess() }
                        }
                    }
                }
            } else if model.refreshedAt != nil, !model.hasUpcomingEvents {
                hint("この先 7 日の予定がありません", detail: "Google などのカレンダーは、端末の設定でアカウントを追加すると読めます。") {
                    EmptyView()
                }
            }
            if model.weatherFailed(on: plan) {
                hint("天気を取得できなかった場所があります", detail: "通信の状態を確かめて、引っぱって更新してください。天気が無い場所では、提案を出しません。") {
                    Button("もう一度試す") {
                        Task { await model.refresh() }
                    }
                }
            }
            if model.bases.isEmpty {
                hint("拠点がまだありません", detail: "自宅か職場を登録すると、場所の入っていない予定や、予定のない日にも提案できます。") {
                    Button("自宅を登録する") {
                        editing = .home
                    }
                }
            }
            if plan.events.isEmpty, plan.candidates.isEmpty, plan.restDay == nil, !model.hasCalendarAccess || model.bases.isEmpty {
                hint("見本で試せます", detail: "見本の予定と天気で、画面を見てみることができます。") {
                    Button("見本を表示") {
                        model.onToggleDemo?(true)
                    }
                }
            }
        }
        .sheet(item: $editing) { kind in
            BaseSearchSheet(kind: kind)
        }
    }

    private func hint(_ title: LocalizedStringKey, detail: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .type(.bodyStrong)
                .foregroundStyle(Palette.ink)
            Text(detail)
                .type(.sub)
                .foregroundStyle(Palette.ink2)
            action()
                .type(.subStrong)
                .buttonStyle(PlainRowButtonStyle(color: Palette.ink))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }
}
