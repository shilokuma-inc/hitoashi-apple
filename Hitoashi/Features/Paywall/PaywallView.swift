//
//  PaywallView.swift
//  Hitoashi
//
//  ペイウォール（仕様書 §4-6）。請求額をいちばん大きく。無料体験の期間と、終わったあとの請求額をボタンの下に書く。
//  閉じるボタンは常に見せる。朱は使わない（朱はひと足だけ）。
//

import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Plan = .yearly

    enum Plan {
        case yearly
        case monthly
    }

    private let features: [(String, String)] = [
        ("空き時間", "すべてに提案"),
        ("先の日", "3日目から先も"),
        ("今週", "歩きどき"),
        ("ほかの画面", "ウィジェットとメニューバー"),
        ("拠点", "3つ目から")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image("PhotoWalker")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 180, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("先の予定まで、ひと足を。")
                        .type(.heading)
                        .foregroundStyle(Palette.ink)
                        .padding(.bottom, 10)
                    ForEach(features, id: \.0) { feature in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(LocalizedStringKey(feature.0))
                                .type(.captionStrong)
                                .foregroundStyle(Palette.ink2)
                                .frame(width: 70, alignment: .leading)
                            Text(LocalizedStringKey(feature.1))
                                .type(.body)
                                .foregroundStyle(Palette.ink)
                        }
                        .ruledRow()
                    }
                    plans
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        }
        .background(Palette.ground)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.65), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .padding(.top, 10)
            .accessibilityLabel("閉じる")
            .accessibilityIdentifier("paywall.close")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .accessibilityIdentifier("paywall")
    }

    private var plans: some View {
        VStack(spacing: 0) {
            planRow(.yearly, price: "¥2,800", unit: "/ 年", note: "月あたり約 ¥233・14日間無料")
            planRow(.monthly, price: "¥400", unit: "/ 月", note: "無料体験なし")
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    private func planRow(_ plan: Plan, price: String, unit: LocalizedStringKey, note: LocalizedStringKey) -> some View {
        Button {
            selected = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected == plan ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected == plan ? Palette.ink : Palette.faint)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(price)
                            .type(plan == .yearly ? .heading : .title)
                            .monospacedDigit()
                        Text(unit)
                            .type(.captionStrong)
                            .foregroundStyle(Palette.ink2)
                    }
                    Text(note)
                        .type(.caption)
                        .foregroundStyle(Palette.ink2)
                }
                .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.vertical, 8)
            .ruledRow()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == plan ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(selected == .yearly ? "14日間無料ではじめる" : "月額 ¥400 ではじめる") {
                // 見本のデータのときは、購入したことにして画面を見せる（実際の購入は StoreKit の実装で入れる）
                if model.isDemo {
                    model.isPro = true
                    dismiss()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("paywall.start")
            Group {
                if selected == .yearly {
                    Text("15日目に ¥2,800 が請求され、その後は 1年ごとに自動更新。無料期間が終わる 24時間前までに解約すれば請求されません。")
                } else {
                    Text("今日 ¥400 が請求され、その後は 1か月ごとに自動更新。期間が終わる 24時間前までに解約すれば、次の請求はありません。")
                }
            }
            .type(.note)
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Button("購入を復元") {}
                    .frame(maxWidth: .infinity)
                Button("利用規約") {}
                    .frame(maxWidth: .infinity)
                Button("プライバシー") {}
                    .frame(maxWidth: .infinity)
            }
            .type(.captionStrong)
            .buttonStyle(PlainRowButtonStyle(color: Palette.ink))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .barBackground()
    }
}
