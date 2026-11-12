//
//  TimelineRows.swift
//  Hitoashi
//
//  タイムラインの行。左から 時刻 / 天気の帯 / 朱の線（ひと足だけ）/ 中身。
//  朱は帯を塗りつぶさない。ひと足の行でも天気の帯は通し、その右に朱の線を添える（仕様書 §4-0）。
//

import HitoashiKit
import SwiftUI

/// 行の骨組み
struct TimelineRowFrame<Time: View, Content: View>: View {
    var segments: [RailSegment]
    var notes: [RailNote]
    var isStep = false
    @ViewBuilder var time: Time
    @ViewBuilder var content: Content

    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 68

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 2) {
                time
                ForEach(notes, id: \.self) { note in
                    Text(note.text)
                        .type(.micro)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: timeWidth - 10, alignment: .trailing)
            .padding(.trailing, 10)

            WeatherRail(segments: segments)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(isStep ? Palette.shu : .clear)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 予定の行。太字にしない（主役はひと足）
struct EventRowContent: View {
    var event: DayEvent
    var hour: HourForecast?
    var book: Phrasebook
    var showsRule: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .type(.body)
                    .foregroundStyle(Palette.ink)
                let place = PlaceText.line(for: event)
                if !place.isEmpty {
                    Text(place)
                        .type(.sub)
                        .foregroundStyle(Palette.ink2)
                }
            }
            Spacer(minLength: 8)
            if let hour {
                HStack(spacing: 4) {
                    WeatherGlyph(kind: hour.kind, isDaylight: hour.isDaylight)
                    Text(book.temperature(hour.temperature))
                        .monospacedDigit()
                }
                .type(.sub)
                .foregroundStyle(Palette.ink2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(book.weatherName(hour.kind)) \(book.temperature(hour.temperature))")
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
        }
    }
}

/// 時刻の 2 段（開始・終了）
struct TimeColumn: View {
    var start: String
    var end: String
    var isStep = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(start)
                .type(.subStrong)
                .foregroundStyle(isStep ? Palette.shu : Palette.ink)
            Text(end)
                .type(.caption)
                .foregroundStyle(Palette.ink2)
        }
        .monospacedDigit()
        .padding(.top, 12)
    }
}

/// ひと足の行。見出しがいちばん大きい
struct StepRowContent: View {
    var suggestion: Suggestion
    var label: String
    var book: Phrasebook

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .type(.label)
                .foregroundStyle(Palette.shu)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(book.title(for: suggestion.plan))
                    .type(.heading)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(book.minutes(suggestion.plan.minutes))
                    .type(.heading)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .fixedSize()
            }
            Text(book.headlineLine(for: suggestion))
                .type(.sub)
                .foregroundStyle(Palette.ink2)
            if let alternate = suggestion.alternate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(book.alternateLabel(alternate.label))
                        .type(.captionStrong)
                    Text(book.alternateText(alternate))
                        .type(.caption)
                }
                .foregroundStyle(Palette.ink2)
                .padding(.top, 2)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .accessibilityElement(children: .combine)
    }
}
