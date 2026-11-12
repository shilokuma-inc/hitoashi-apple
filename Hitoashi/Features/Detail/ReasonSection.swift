//
//  ReasonSection.swift
//  Hitoashi
//
//  決め手（仕様書 §4-3）。1 文と、横向きの天気の帯。朱の枠が「ひと足の時間」で、斜線（雨）を避けているのが分かる。
//  「くわしく」を開くと、判定に使った値の表と、天気データの帰属表示が出る。
//

import HitoashiKit
import SwiftUI

struct ReasonSection: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion

    private let hourCount = 6

    var body: some View {
        let book = model.book
        let forecast = model.forecast(for: suggestion.slot.place.cell)
        let hours = shownHours(forecast: forecast)
        VStack(alignment: .leading, spacing: 0) {
            Text("決め手")
                .type(.captionStrong)
                .foregroundStyle(Palette.ink2)
            Text(book.headlineLine(for: suggestion))
                .type(.body)
                .foregroundStyle(Palette.ink)
                .padding(.top, 6)
            if !hours.isEmpty, let first = hours.first {
                band(hours: hours, start: first.date, forecast: forecast, book: book)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// ひと足の 2 時間前から、6 時間ぶん
    private func shownHours(forecast: PlaceForecast?) -> [HourForecast] {
        ReasonHours.shown(for: suggestion, forecast: forecast, count: hourCount)
    }

    private func band(hours: [HourForecast], start: Date, forecast: PlaceForecast?, book: Phrasebook) -> some View {
        let interval = DateInterval(start: start, duration: TimeInterval(hours.count * 3600))
        let day = forecast?.day(containing: suggestion.window.start, calendar: model.calendar)
        let segments = RailBuilder.segments(for: interval, forecast: forecast, day: day)
        let offset = suggestion.window.start.timeIntervalSince(start) / interval.duration
        let width = suggestion.window.duration / interval.duration
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                ForEach(hours, id: \.date) { hour in
                    Text(book.hour(model.calendar.component(.hour, from: hour.date)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .type(.micro)
            .foregroundStyle(Palette.ink2)
            HourBand(segments: segments, window: (start: offset, width: width))
                .padding(.vertical, 4)
            HStack(spacing: 0) {
                ForEach(hours, id: \.date) { hour in
                    Text(book.percent(hour.precipitationChance))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .type(.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
            HStack(spacing: 14) {
                legend(RailSegment(fraction: 1, isRain: true, isDark: false), String(localized: "雨"))
                legend(RailSegment(fraction: 1, isRain: false, isDark: true), String(localized: "日没後"))
                HStack(spacing: 4) {
                    Rectangle()
                        .strokeBorder(Palette.shu, lineWidth: 2)
                        .frame(width: 14, height: 9)
                    Text("ひと足の時間")
                }
            }
            .type(.micro)
            .foregroundStyle(Palette.ink2)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "時間ごとの降水確率"))
    }

    private func legend(_ segment: RailSegment, _ text: String) -> some View {
        HStack(spacing: 4) {
            RailSwatch(segment: segment)
            Text(text)
        }
    }
}

enum ReasonHours {
    /// ひと足の 2 時間前から、数時間ぶんの予報
    static func shown(for suggestion: Suggestion, forecast: PlaceForecast?, count: Int) -> [HourForecast] {
        guard let forecast else {
            return []
        }
        let start = WindowPickerSupport.floorToHour(suggestion.window.start).addingTimeInterval(-2 * 3600)
        let interval = DateInterval(start: start, duration: TimeInterval(count * 3600))
        return Array(forecast.hours(overlapping: interval).prefix(count))
    }
}

/// 「くわしく」。その場で開く。判定に使った値の表と、注記
struct ReasonDetails: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion
    @State private var isExpanded = false

    var body: some View {
        let forecast = model.forecast(for: suggestion.slot.place.cell)
        let hours = ReasonHours.shown(for: suggestion, forecast: forecast, count: 6)
        DisclosureGroup(isExpanded: $isExpanded) {
            if !hours.isEmpty {
                HourTable(hours: hours, windowStart: suggestion.window.start, book: model.book)
            }
            DetailNotes(suggestion: suggestion, forecast: forecast)
        } label: {
            Text("くわしく")
                .type(.sub)
                .foregroundStyle(Palette.ink)
                .frame(minHeight: 44)
        }
        .tint(Palette.faint)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .accessibilityIdentifier("detail.more")
    }
}

/// 判定に使った値の表。ひと足の時刻の列は太字にする
struct HourTable: View {
    @Environment(AppModel.self) private var model
    var hours: [HourForecast]
    var windowStart: Date
    var book: Phrasebook

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 0) {
            row(String(localized: "")) { hour in
                book.hour(model.calendar.component(.hour, from: hour.date))
            }
            .foregroundStyle(Palette.ink2)
            ruled(String(localized: "天気")) { book.weatherName($0.kind) }
            ruled(String(localized: "気温")) { book.temperature($0.temperature) }
            ruled(String(localized: "体感")) { book.temperature($0.apparentTemperature) }
            ruled(String(localized: "降水確率")) { book.percent($0.precipitationChance) }
            ruled(String(localized: "風")) { book.wind($0.windSpeed) }
            ruled("UV") { "\($0.uvIndex)" }
        }
        .type(.caption)
        .monospacedDigit()
        .padding(.top, 2)
    }

    private func isWindow(_ hour: HourForecast) -> Bool {
        hour.date <= windowStart && windowStart < hour.date.addingTimeInterval(3600)
    }

    private func row(_ title: String, value: @escaping (HourForecast) -> String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(Palette.ink2)
                .gridColumnAlignment(.leading)
            ForEach(hours, id: \.date) { hour in
                Text(value(hour))
                    .fontWeight(isWindow(hour) ? .bold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private func ruled(_ title: String, value: @escaping (HourForecast) -> String) -> some View {
        Rectangle().fill(Palette.line).frame(height: 1)
        row(title, value: value)
            .foregroundStyle(Palette.ink)
    }
}

/// 表の下の注記（日没・帰属表示・加工したデータであること・見ていないもの）
struct DetailNotes: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion
    var forecast: PlaceForecast?

    var body: some View {
        let book = model.book
        VStack(alignment: .leading, spacing: 3) {
            if let sunset = forecast?.day(containing: suggestion.window.start, calendar: model.calendar)?.sunset {
                Text("日没 \(book.time(sunset))")
                    .foregroundStyle(Palette.ink)
                    .padding(.bottom, 6)
            }
            if model.isDemo {
                Text("見本のデータです。実際の天気ではありません。")
            } else {
                WeatherAttributionView()
                Text("Apple Weather のデータをもとに、ひとあしが判定しています（加工したデータです）。")
                Text("\(book.time(suggestion.forecastFetchedAt))時点の予報です。")
                if forecast?.alertsAvailable == false {
                    Text("この地域では警報の情報を取得できません。")
                }
            }
            Text("大気の状態（煙・PM2.5・花粉）は見ていません。")
            Text("提案は目安です。出かける前に、空と体調を確かめてください。")
        }
        .type(.note)
        .foregroundStyle(Palette.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

/// 天気データの帰属表示（Apple Weather の印と、データソースへのリンク）
struct WeatherAttributionView: View {
    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: " Weather")
                .fontWeight(.semibold)
            if let url = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/") {
                Link("ほかのデータソース", destination: url)
                    .underline()
            }
        }
        .foregroundStyle(Palette.ink2)
    }
}
