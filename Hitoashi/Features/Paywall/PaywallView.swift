//
//  PaywallView.swift
//  Hitoashi
//
//  ペイウォール（仕様書 §4-6）。請求額をいちばん大きく。無料体験の期間と、終わったあとの請求額をボタンの下に書く。
//  閉じるボタンは常に見せる。朱は使わない（朱はひと足だけ）。
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var selected: Plan = .yearly
    @State private var isBusy = false
    @State private var failed = false

    enum Plan {
        case yearly
        case monthly
    }

    private let features: [(String, String)] = [
        ("空き時間", "すべてに提案"),
        ("先の日", "3日目から先も"),
        ("今週", "歩きどき")
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
    }

    private var store: Store? { model.environment.store }
    private var yearlyPrice: String { store?.yearly?.displayPrice ?? "¥2,800" }
    private var monthlyPrice: String { store?.monthly?.displayPrice ?? "¥400" }

    /// 年額の無料体験の日数。使えないとき（すでに使った人・設定されていない）は nil。
    /// 見本のデータのときは、デザインの見本の値（14 日）を出す
    private var trialDays: Int? {
        guard let store, let yearly = store.yearly else {
            return 14
        }
        return store.isEligibleForTrial ? yearly.freeTrialDays : nil
    }

    private var yearlyNote: LocalizedStringKey {
        if let trialDays {
            return "月あたり約 \(monthlyEquivalent)・\(trialDays)日間無料"
        }
        return "月あたり約 \(monthlyEquivalent)"
    }

    private var startTitle: LocalizedStringKey {
        guard selected == .yearly else {
            return "月額 \(monthlyPrice) ではじめる"
        }
        if let trialDays {
            return "\(trialDays)日間無料ではじめる"
        }
        return "年額 \(yearlyPrice) ではじめる"
    }

    /// ボタンの下の、請求の説明。無料体験を使えない人に「◯日目に請求」と書かない
    private var billingNote: LocalizedStringKey {
        guard selected == .yearly else {
            return "今日 \(monthlyPrice) が請求され、その後は 1か月ごとに自動更新。期間が終わる 24時間前までに解約すれば、次の請求はありません。"
        }
        if let trialDays {
            return "\(trialDays + 1)日目に \(yearlyPrice) が請求され、その後は 1年ごとに自動更新。無料期間が終わる 24時間前までに解約すれば請求されません。"
        }
        return "今日 \(yearlyPrice) が請求され、その後は 1年ごとに自動更新。期間が終わる 24時間前までに解約すれば、次の請求はありません。"
    }

    /// 年額を 12 で割った、月あたりの目安
    private var monthlyEquivalent: String {
        guard let yearly = store?.yearly else {
            return "¥233"
        }
        return (yearly.price / 12).formatted(yearly.priceFormatStyle)
    }

    /// 見本のデータのときは、購入したことにして画面を見せる。実データで商品を取れていないときは、買えない
    private var canPurchase: Bool {
        model.isDemo || (selected == .yearly ? store?.yearly : store?.monthly) != nil
    }

    private var plans: some View {
        VStack(spacing: 0) {
            planRow(.yearly, price: yearlyPrice, unit: "/ 年", note: yearlyNote)
            planRow(.monthly, price: monthlyPrice, unit: "/ 月", note: "無料体験なし")
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
            Button {
                Task { await start() }
            } label: {
                Text(startTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isBusy || !canPurchase)
            .opacity(canPurchase ? 1 : 0.4)
            .accessibilityIdentifier("paywall.start")
            Group {
                if !canPurchase {
                    Text("いまは購入できません（商品の情報を取得できませんでした）。")
                } else if failed {
                    Text("購入を完了できませんでした。")
                } else {
                    Text(billingNote)
                }
            }
            .type(.note)
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Button("購入を復元") {
                    Task {
                        await store?.restore()
                        if model.isPro {
                            dismiss()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                if let terms = URL(string: "https://shilokuma.jp/terms/hitoashi/") {
                    Link("利用規約", destination: terms)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                if let privacy = URL(string: "https://shilokuma.jp/privacy/hitoashi/") {
                    Link("プライバシー", destination: privacy)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .type(.captionStrong)
            .foregroundStyle(Palette.ink)
            .buttonStyle(PlainRowButtonStyle(color: Palette.ink))
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .barBackground()
    }

    private func start() async {
        // 見本のデータのときは、購入したことにして Pro の画面を見せる
        if model.isDemo {
            model.isPro = true
            dismiss()
            return
        }
        guard let store, let product = selected == .yearly ? store.yearly : store.monthly else {
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await purchase(product)
            await store.handle(result)
            failed = false
            if store.isPro {
                dismiss()
            }
        } catch {
            failed = true
        }
    }
}
