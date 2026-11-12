//
//  Theme.swift
//  Hitoashi
//
//  色と文字の決まり（仕様書 §4-0、画面デザイン v2）。
//  UI は白・黒・グレー。色が付くのは「ひと足」（提案）だけで、その色は朱。
//

import SwiftUI

/// 色。値は Assets.xcassets（ライト / ダーク）。
/// Vision Pro ではウインドウがガラスなので、地は透明にし、文字は OS の標準の色に任せる
enum Palette {
    #if os(visionOS)
    static let ink = Color.primary
    static let ink2 = Color.secondary
    static let faint = Color.secondary
    static let line = Color.primary.opacity(0.18)
    static let night = Color.primary.opacity(0.4)
    static let ground = Color.clear
    static let surface = Color.clear
    static let onInk = Color.black
    #else
    /// 文字
    static let ink = Color("Ink")
    /// 補助の文字（地とのコントラスト比 4.5:1 以上）。文字の灰色はこれだけを使う
    static let ink2 = Color("Ink2")
    /// 文字以外の灰（矢印・天気の帯の枠）
    static let faint = Color("Faint")
    /// 罫
    static let line = Color("Line")
    /// 天気の帯の「日没後」
    static let night = Color("Night")
    /// 地
    static let ground = Color("Ground")
    /// 一段上の面
    static let surface = Color("Surface")
    /// 黒い面（主ボタン・選んだ日）の上の文字、地図の上の小さな札の地
    static let onInk = Color("Ground")
    #endif
    /// 朱。ひと足の時間・場所にだけ使う
    static let shu = Color("Shu")
}

/// 文字の大きさは 34 / 24 / 20 / 17 / 15 / 13 / 11 の 7 段（注意書きだけ 12）
enum TypeRole {
    /// 34 太字（画面の題）
    case display
    /// 24 太字（ひと足の見出し）
    case heading
    /// 20 セミボールド（日付）
    case title
    /// 17
    case body
    /// 17 セミボールド
    case bodyStrong
    /// 15
    case sub
    /// 15 ミディアム（時刻）
    case subStrong
    /// 13
    case caption
    /// 13 セミボールド
    case captionStrong
    /// 12（注意書き）
    case note
    /// 12 太字（「きょうのひと足」）
    case label
    /// 11
    case micro

    var size: CGFloat {
        switch self {
        case .display:
            34
        case .heading:
            24
        case .title:
            20
        case .body, .bodyStrong:
            17
        case .sub, .subStrong:
            15
        case .caption, .captionStrong:
            13
        case .note, .label:
            12
        case .micro:
            11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .heading, .label:
            .bold
        case .title, .bodyStrong, .captionStrong:
            .semibold
        case .subStrong:
            .medium
        case .body, .sub, .caption, .note, .micro:
            .regular
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .display:
            .largeTitle
        case .heading:
            .title2
        case .title:
            .title3
        case .body, .bodyStrong:
            .body
        case .sub, .subStrong:
            .subheadline
        case .caption, .captionStrong:
            .footnote
        case .note, .label:
            .caption
        case .micro:
            .caption2
        }
    }
}

/// システムフォントを、決めた大きさのまま Dynamic Type に合わせて拡大する
private struct ScaledType: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(_ role: TypeRole) {
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
        weight = role.weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// 文字の役割を指定する（大きさと太さ）
    func type(_ role: TypeRole) -> some View {
        modifier(ScaledType(role))
    }

    /// 画面の下に固定する操作の帯の地。Vision Pro ではガラスを重ねる
    @ViewBuilder
    func barBackground() -> some View {
        #if os(visionOS)
        background(.regularMaterial)
        #else
        background(Palette.ground)
        #endif
    }

    /// 罫線つきの 1 行（高さ 44pt 以上）。自作の部品は丸めない
    func ruledRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.line).frame(height: 1)
            }
    }
}

/// 主ボタン（黒地に白。ダークでは明るい地に黒文字）。丸いのは OS の部品と主ボタンだけ
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        // Mac では、OS のボタンに近い大きさと角にする
        configuration.label
            .type(.subStrong)
            .foregroundStyle(Palette.onInk)
            .frame(minWidth: 180, minHeight: 36)
            .padding(.horizontal, 16)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        #else
        configuration.label
            .type(.bodyStrong)
            .foregroundStyle(Palette.onInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.ink.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
        #endif
    }
}

/// 文字だけのボタン（高さ 44pt）
struct PlainRowButtonStyle: ButtonStyle {
    var color: Color = Palette.ink2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.5 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
