//
//  WeatherGlyph.swift
//  Hitoashi
//
//  天気記号。SF Symbols を 1 色で使う（降水を青で塗らない。仕様書 §4-0）。
//

import HitoashiKit
import SwiftUI

extension WeatherKind {
    /// 昼と夜で記号が変わらない天気の、SF Symbols の名前
    private static let symbols: [WeatherKind: String] = [
        .cloudy: "cloud",
        .fog: "cloud.fog",
        .drizzle: "cloud.drizzle",
        .rain: "cloud.rain",
        .heavyRain: "cloud.heavyrain",
        .thunder: "cloud.bolt.rain",
        .snow: "cloud.snow",
        .sleet: "cloud.sleet",
        .windy: "wind",
        .smoke: "smoke",
        .severeStorm: "tropicalstorm"
    ]

    /// SF Symbols の名前
    func symbolName(isDaylight: Bool = true) -> String {
        switch self {
        case .clear:
            isDaylight ? "sun.max" : "moon"
        case .partlyCloudy:
            isDaylight ? "cloud.sun" : "cloud.moon"
        default:
            Self.symbols[self] ?? "cloud"
        }
    }
}

struct WeatherGlyph: View {
    var kind: WeatherKind
    var isDaylight = true

    var body: some View {
        Image(systemName: kind.symbolName(isDaylight: isDaylight))
            .symbolRenderingMode(.monochrome)
            .accessibilityHidden(true)
    }
}
