//
//  WeatherRail.swift
//  Hitoashi
//
//  天気の帯（仕様書 §4-0）。時刻の軸に沿って通す細い帯で、雨の時間は斜線、日没後は灰の塗り。
//  晴れの時間も「白い帯」として見せる。色に頼らないので、白黒でも読める。
//

import HitoashiKit
import SwiftUI

/// 帯の 1 区間（時間で比例分割したもの）
struct RailSegment: Hashable {
    /// 行の中での割合（合計 1）
    var fraction: Double
    var isRain: Bool
    var isDark: Bool
}

/// 帯の変わり目の注記（「雨 15時まで」「日没 16:38」）
struct RailNote: Hashable {
    var text: String
}

enum RailBuilder {
    /// 時間帯を 5 分刻みで見て、雨・日没後の区間に分ける
    static func segments(for interval: DateInterval, forecast: PlaceForecast?, day: DayForecast?) -> [RailSegment] {
        guard let forecast, interval.duration > 0 else {
            return [RailSegment(fraction: 1, isRain: false, isDark: false)]
        }
        let step: TimeInterval = 5 * 60
        var result: [RailSegment] = []
        var cursor = interval.start
        while cursor < interval.end {
            let length = min(step, interval.end.timeIntervalSince(cursor))
            let hour = forecast.hour(at: cursor)
            let rain = hour.map(Comfort.isRainy) ?? false
            let dark = isDark(cursor, hour: hour, day: day)
            let fraction = length / interval.duration
            if let last = result.last, last.isRain == rain, last.isDark == dark {
                result[result.count - 1].fraction += fraction
            } else {
                result.append(RailSegment(fraction: fraction, isRain: rain, isDark: dark))
            }
            cursor = cursor.addingTimeInterval(step)
        }
        return result
    }

    static func isDark(_ date: Date, hour: HourForecast?, day: DayForecast?) -> Bool {
        if let sunset = day?.sunset, let sunrise = day?.sunrise {
            return date >= sunset || date < sunrise
        }
        return hour.map { !$0.isDaylight } ?? false
    }

    /// 時間帯の中で起きる変わり目（雨の始まり・終わり、日没）
    static func notes(for interval: DateInterval, forecast: PlaceForecast?, day: DayForecast?, book: Phrasebook) -> [RailNote] {
        guard let forecast else {
            return []
        }
        var notes: [RailNote] = []
        let calendar = book.calendar
        var hourStart = WindowPickerSupport.floorToHour(interval.start)
        while hourStart < interval.end {
            let next = hourStart.addingTimeInterval(3600)
            // 時間の境目（next）が、この行の中（start < next <= end）にあるときだけ見る
            if next > interval.start, next <= interval.end,
               let current = forecast.hour(at: hourStart), let following = forecast.hour(at: next) {
                let hour = calendar.component(.hour, from: next)
                if Comfort.isRainy(current), !Comfort.isRainy(following) {
                    notes.append(RailNote(text: String(localized: "雨 〜\(book.hour(hour))")))
                } else if !Comfort.isRainy(current), Comfort.isRainy(following) {
                    notes.append(RailNote(text: String(localized: "雨 \(book.hour(hour))〜")))
                }
            }
            hourStart = next
        }
        if let sunset = day?.sunset, sunset >= interval.start, sunset < interval.end {
            notes.append(RailNote(text: String(localized: "日没 \(book.time(sunset))")))
        }
        return notes
    }
}

enum WindowPickerSupport {
    static func floorToHour(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 3600).rounded(.down) * 3600)
    }
}

/// 縦の天気の帯（タイムラインの 1 行ぶん）。幅 12pt
struct WeatherRail: View {
    static let width: CGFloat = 12

    /// タイムライン全体の座標の名前。行をまたいで斜線がつながるよう、帯はこの座標での位置を見る
    static let space = "timeline"

    var segments: [RailSegment]

    var body: some View {
        GeometryReader { proxy in
            let originY = proxy.frame(in: .named(Self.space)).minY
            Canvas { context, size in
                var offset: CGFloat = 0
                for segment in segments {
                    let height = size.height * segment.fraction
                    let rect = CGRect(x: 0, y: offset, width: size.width, height: height)
                    RailPainter.fill(rect, segment: segment, originY: originY, in: &context)
                    offset += height
                }
                // 枠は左右とも 1pt の実線
                for x in [0.5, size.width - 0.5] {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(Palette.faint), lineWidth: 1)
                }
            }
        }
        .frame(width: Self.width)
        .accessibilityHidden(true)
    }
}

/// 横の天気の帯（詳細の画面）。ひと足の時間を朱の枠で囲む
struct HourBand: View {
    var segments: [RailSegment]
    /// ひと足の時間の位置（0〜1）と幅（0〜1）
    var window: (start: Double, width: Double)

    var body: some View {
        Canvas { context, size in
            var offset: CGFloat = 0
            for segment in segments {
                let width = size.width * segment.fraction
                let rect = CGRect(x: offset, y: 0, width: width, height: size.height)
                RailPainter.fill(rect, segment: segment, in: &context)
                offset += width
            }
            context.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.faint), lineWidth: 1)
        }
        .frame(height: 18)
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .strokeBorder(Palette.shu, lineWidth: 2)
                    .frame(width: max(8, proxy.size.width * window.width), height: proxy.size.height + 8)
                    .offset(x: proxy.size.width * window.start, y: -4)
            }
        }
        .accessibilityHidden(true)
    }
}

enum RailPainter {
    /// 区間を塗る。日没後は灰の塗り、雨は 45° の斜線（1.5pt 線・5pt ピッチ）
    /// - Parameter originY: この Canvas の上端が、タイムライン全体の座標でどこにあるか（斜線の位相をそろえる）
    static func fill(_ rect: CGRect, segment: RailSegment, originY: CGFloat = 0, in context: inout GraphicsContext) {
        if segment.isDark {
            context.fill(Path(rect), with: .color(Palette.night))
        }
        guard segment.isRain else {
            return
        }
        var clipped = context
        clipped.clip(to: Path(rect))
        let pitch: CGFloat = 5
        var path = Path()
        // 線は x + y が一定の点の集まり。タイムライン全体の座標で位相をそろえると、行をまたいでつながる
        let phase = (rect.maxY + originY).truncatingRemainder(dividingBy: pitch)
        var start = ((rect.minX - rect.height) / pitch).rounded(.down) * pitch - phase
        while start < rect.maxX {
            path.move(to: CGPoint(x: start, y: rect.maxY))
            path.addLine(to: CGPoint(x: start + rect.height, y: rect.minY))
            start += pitch
        }
        clipped.stroke(path, with: .color(Palette.ink), lineWidth: 1.5)
    }
}

/// 凡例に使う小さな見本
struct RailSwatch: View {
    var segment: RailSegment

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            RailPainter.fill(rect, segment: segment, in: &context)
            context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.faint), lineWidth: 1)
        }
        .frame(width: 14, height: 9)
        .accessibilityHidden(true)
    }
}
