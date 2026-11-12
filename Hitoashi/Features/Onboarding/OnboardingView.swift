//
//  OnboardingView.swift
//  Hitoashi
//
//  はじめに（仕様書 §4-1）。見本のタイムライン → カレンダーの説明 → 拠点 → 安全についての注意。
//  通知の許可はここでは求めない（きょうの「この時刻に知らせる」から）。
//

import HitoashiKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = Step.intro

    enum Step: Int {
        case intro
        case calendar
        case bases
        case safety
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                switch step {
                case .intro:
                    IntroPage()
                case .calendar:
                    page(title: "予定を読ませて\nください。", lead: "予定の時刻と場所から、\n前後の空き時間を見つけます。") {
                        fact("読むだけです", "予定の作成・変更・削除はしません。")
                        fact("題名とメモは、端末の外に出ません", "場所の名前だけ、位置を調べるために Apple に送ります。開発者には届きません。")
                        fact("このあと「フルアクセス」と表示されます", "読み取りだけの許可が用意されていないためです。")
                    }
                case .bases:
                    page(title: "ふだん、\nどこにいますか。", lead: "場所の入っていない予定は、\nここにいるものとして提案します。") {
                        VStack(spacing: 0) {
                            BaseRows()
                                .type(.body)
                                .padding(.vertical, 12)
                                .ruledRow()
                        }
                        Text("どちらか 1 つでも大丈夫です。平日は職場、休日は自宅を使います。")
                            .type(.note)
                            .foregroundStyle(Palette.ink2)
                            .padding(.top, 12)
                    }
                case .safety:
                    page(title: "はじめる前に。", lead: "") {
                        SafetyNote()
                            .padding(.top, 4)
                    }
                }
            }
            Button(buttonTitle) {
                Task { await advance() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .accessibilityIdentifier("onboarding.next")
        }
        .ignoresSafeArea(edges: step == .intro ? .top : [])
        .background(Palette.ground)
        .accessibilityIdentifier("onboarding")
    }

    private var buttonTitle: LocalizedStringKey {
        switch step {
        case .intro, .safety:
            "はじめる"
        case .calendar, .bases:
            "続ける"
        }
    }

    private func advance() async {
        // カレンダーの説明のあとで、OS の確認を出す（見本のデータのときは出さない）
        if step == .calendar {
            await model.requestCalendarAccess()
        }
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            model.hasOnboarded = true
            await model.refresh()
        }
    }

    private func page(title: LocalizedStringKey, lead: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .type(.display)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(lead)
                .type(.body)
                .foregroundStyle(Palette.ink2)
                .padding(.top, 10)
                .padding(.bottom, 18)
            content()
        }
        .padding(.horizontal, 24)
        .padding(.top, 48)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func fact(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .type(.body)
                .foregroundStyle(Palette.ink)
            Text(detail)
                .type(.caption)
                .foregroundStyle(Palette.ink2)
        }
        .padding(.vertical, 12)
        .ruledRow()
    }
}

/// 最初の 1 枚。撮られた写真（白黒）と、見本のタイムラインをそのまま見せる
private struct IntroPage: View {
    var body: some View {
        let world = DemoData.world()
        let book = Phrasebook(calendar: world.calendar)
        let plan = WeekPlanner.plans(world.plannerInput()).first
        VStack(alignment: .leading, spacing: 0) {
            Image("PhotoPath")
                .resizable()
                .scaledToFill()
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("予定のついでに、\nひと足のばす。")
                    .type(.display)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("予定の場所と時刻の天気を見て、\n空いた時間にひと足を出します。")
                    .type(.body)
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            if let plan, let top = plan.top {
                sample(plan: plan, top: top, world: world, book: book)
                    .padding(.top, 18)
            }
        }
    }

    /// 見本の 1 日から、ひと足の前後の予定だけを抜き出して見せる
    private func sample(plan: DayPlan, top: Suggestion, world: DemoWorld, book: Phrasebook) -> some View {
        let before = plan.events.last { $0.end <= top.window.start }
        let after = plan.events.first { $0.start >= top.window.end }
        let forecast = world.forecasts[top.slot.place.cell]
        let day = forecast?.day(containing: top.window.start, calendar: world.calendar)
        return VStack(spacing: 0) {
            if let before {
                eventRow(before, forecast: forecast, day: day, book: book)
            }
            TimelineRowFrame(
                segments: RailBuilder.segments(for: top.window, forecast: forecast, day: day),
                notes: [],
                isStep: true
            ) {
                TimeColumn(start: book.time(top.window.start), end: book.time(top.window.end), isStep: true)
            } content: {
                StepRowContent(suggestion: top, label: String(localized: "きょうのひと足"), book: book)
            }
            if let after {
                eventRow(after, forecast: forecast, day: day, book: book)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
        .accessibilityHidden(true)
    }

    private func eventRow(_ event: DayEvent, forecast: PlaceForecast?, day: DayForecast?, book: Phrasebook) -> some View {
        let interval = DateInterval(start: event.start, end: event.end)
        return TimelineRowFrame(segments: RailBuilder.segments(for: interval, forecast: forecast, day: day), notes: []) {
            TimeColumn(start: book.time(event.start), end: book.time(event.end))
        } content: {
            EventRowContent(event: event, hour: forecast?.hour(at: event.start), book: book, showsRule: false)
        }
    }
}
