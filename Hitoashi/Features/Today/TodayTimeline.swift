//
//  TodayTimeline.swift
//  Hitoashi
//
//  きょう（仕様書 §4-2）。1 日の「しおり」。上から時刻順に、予定と、その間に差し込まれたひと足が並ぶ。
//

import HitoashiKit
import SwiftUI

struct TodayTimeline: View {
    @Environment(AppModel.self) private var model
    /// ひと足を押したとき
    var onOpen: (Suggestion) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.isDemo {
                    DemoBanner()
                }
                if let plan = model.selectedPlan {
                    DayHeader(plan: plan)
                    DayStrip()
                    if plan.dayIndex == 0, let pending = model.pendingLog {
                        PendingLogRow(log: pending)
                    }
                    if let rest = plan.restDay {
                        RestDayBlock(rest: rest)
                    }
                    if model.refreshedAt == nil {
                        // 最初の更新が終わるまで（予定・場所・天気を集めているあいだ）
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("予定と天気を読み込んでいます")
                                .type(.sub)
                                .foregroundStyle(Palette.ink2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    if !model.isDemo {
                        SetupHints(plan: plan)
                    }
                    rows(for: plan)
                    if plan.hiddenCount > 0 {
                        MoreStepsRow(count: plan.hiddenCount)
                    }
                    if model.isPro, plan.dayIndex == 0 {
                        OutlookSection(onOpen: onOpen)
                    }
                    AttributionFooter(plan: plan)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Palette.ground)
        .refreshable {
            await model.refresh()
        }
        .task(id: model.selectedDay) {
            await model.loadSpotsForSelectedDay()
        }
    }

    @ViewBuilder
    private func rows(for plan: DayPlan) -> some View {
        let book = model.book
        let rows = TimelineBuilder.rows(for: plan, resolve: model.resolved)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let forecast = model.forecast(for: row.cell)
                let day = forecast?.day(containing: row.interval.start, calendar: model.calendar)
                let segments = RailBuilder.segments(for: row.interval, forecast: forecast, day: day)
                let notes = RailBuilder.notes(for: row.interval, forecast: forecast, day: day, book: book)
                switch row.content {
                case .event(let event):
                    TimelineRowFrame(segments: segments, notes: notes) {
                        TimeColumn(start: book.time(event.start), end: book.time(event.end))
                    } content: {
                        EventRowContent(event: event, hour: forecast?.hour(at: event.start), book: book, showsRule: index > 0)
                    }
                case .step(let suggestion, let isTop):
                    TimelineRowFrame(segments: segments, notes: notes, isStep: true) {
                        TimeColumn(start: book.time(suggestion.window.start), end: book.time(suggestion.window.end), isStep: true)
                    } content: {
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                onOpen(suggestion)
                            } label: {
                                StepRowContent(suggestion: suggestion, label: stepLabel(isTop: isTop, plan: plan), book: book)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(isTop ? "today.topStep" : "today.step")
                            if isTop, plan.dayIndex == 0, !model.noticesEnabled {
                                NotifyRow(suggestion: suggestion)
                            }
                        }
                    }
                case .gap:
                    TimelineRowFrame(segments: segments, notes: notes) {
                        EmptyView()
                    } content: {
                        Color.clear.frame(height: max(TimelineBuilder.gapHeight(for: row.interval), notes.isEmpty ? 0 : 20))
                    }
                }
            }
        }
        .padding(.top, 6)
        .coordinateSpace(name: WeatherRail.space)
    }

    private func stepLabel(isTop: Bool, plan: DayPlan) -> String {
        guard isTop else {
            return String(localized: "ひと足")
        }
        return plan.dayIndex == 0 ? String(localized: "きょうのひと足") : String(localized: "この日のひと足")
    }
}

/// 見本を表示しているときの帯（仕様書 §4-2）
struct DemoBanner: View {
    var body: some View {
        Text("見本を表示中")
            .type(.captionStrong)
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Palette.ink)
            .accessibilityIdentifier("today.demoBanner")
    }
}

/// 日付と、その日の天気の一行（WeatherKit の日ごとの値をそのまま出す）
struct DayHeader: View {
    @Environment(AppModel.self) private var model
    var plan: DayPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateText)
                .type(.title)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let forecast = plan.forecast {
                HStack(spacing: 6) {
                    WeatherGlyph(kind: forecast.kind)
                    Text(model.book.weatherName(forecast.kind))
                    Text("\(model.book.temperature(forecast.high)) / \(model.book.temperature(forecast.low))")
                        .monospacedDigit()
                        .padding(.leading, 6)
                }
                .type(.sub)
                .foregroundStyle(Palette.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var dateText: String {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.wide)
        style.timeZone = model.calendar.timeZone
        style.locale = Locale.current
        return plan.day.formatted(style)
    }
}

/// 「この時刻に知らせる」（通知が未許可のとき。押したときに許可を求める）
struct NotifyRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var suggestion: Suggestion

    /// 通知の設定を開く URL（許可されなかったあとは、押し直しても OS の確認は出ないので、ここへ案内する）
    private static var settingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #else
        URL(string: UIApplication.openNotificationSettingsURLString)
        #endif
    }

    var body: some View {
        Button {
            if model.noticesDenied, let url = Self.settingsURL {
                openURL(url)
            } else {
                Task { await model.enableNotices(for: suggestion.window.start) }
            }
        } label: {
            Label(model.noticesDenied ? "通知が許可されていません。設定を開く" : "この時刻に知らせる", systemImage: "bell")
                .type(.subStrong)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .ruledRow()
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .accessibilityIdentifier("today.notify")
    }
}

/// 「きのう 12:10 のひと足 — やった / やらなかった」
struct PendingLogRow: View {
    @Environment(AppModel.self) private var model
    var log: StepLog

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                question
                Spacer(minLength: 8)
                answers
            }
            VStack(alignment: .leading, spacing: 0) {
                question
                answers
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    private var question: some View {
        Text("きのう \(model.book.time(log.date)) のひと足")
            .type(.sub)
            .foregroundStyle(Palette.ink2)
    }

    private var answers: some View {
        HStack(spacing: 16) {
            Button("やった") {
                model.setOutcome(.done, for: log)
            }
            Button("やらなかった") {
                model.setOutcome(.skipped, for: log)
            }
        }
        .type(.subStrong)
        .buttonStyle(PlainRowButtonStyle(color: Palette.ink))
    }
}

/// 「ほかに 1つ、ひと足の候補があります」→ ペイウォール。鍵マークは並べない
struct MoreStepsRow: View {
    @Environment(AppModel.self) private var model
    var count: Int

    var body: some View {
        Button {
            model.showsPaywall = true
        } label: {
            HStack {
                Text("ほかに \(count)つ、ひと足の候補があります")
                    .type(.sub)
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.faint)
            }
            .ruledRow()
        }
        .buttonStyle(.plain)
        .padding(.leading, 96)
        .padding(.trailing, 20)
        .padding(.top, 4)
        .accessibilityIdentifier("today.more")
    }
}
