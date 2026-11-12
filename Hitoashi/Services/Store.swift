//
//  Store.swift
//  Hitoashi
//
//  ひとあし Pro（サブスク）。StoreKit 2 で商品の取得・権利の確認・復元を行う（仕様書 §6）。
//  購入そのものは、画面から @Environment(\.purchase) で行う（Vision Pro では product.purchase() が使えないため）。
//

import Foundation
import Observation
import StoreKit

@Observable
final class Store {
    static let yearlyID = "jp.shilokuma.Hitoashi.pro.yearly"
    static let monthlyID = "jp.shilokuma.Hitoashi.pro.monthly"
    private static let productIDs = [yearlyID, monthlyID]

    private(set) var yearly: Product?
    private(set) var monthly: Product?
    /// Pro の権利があるか
    private(set) var isPro = false
    /// 年額の無料体験を使えるか（すでに使った人は使えない。ペイウォールの文面を変える）
    private(set) var isEligibleForTrial = true
    /// 権利が変わったとき
    var onChange: ((Bool) -> Void)?

    private var updates: Task<Void, Never>?

    /// 購入の結果
    enum PurchaseOutcome {
        case purchased
        /// 承認待ち（ファミリー共有の承認など）
        case pending
        case cancelled
        /// 購入は通ったが、取引を検証できなかった（権利は付けない）
        case unverified
    }

    /// 商品を取り、権利を確かめ、変化を見張る
    func start() {
        guard updates == nil else {
            return
        }
        // 権利の確認と取引の見張りは、商品の取得を待たずに始める（取得が遅いあいだ、Pro の人を無料扱いにしない）
        Task { await load() }
        updates = Task {
            await refresh()
            // 更新・承認待ちの購入など、アプリの外で起きた取引もここに届く。受け取ったら完了にする
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refresh()
            }
        }
    }

    /// 商品を取る。取れなかったとき（通信の失敗など）は、前に取れた商品を残す
    @discardableResult
    func load() async -> Bool {
        guard let products = try? await Product.products(for: Self.productIDs) else {
            return false
        }
        let yearlyProduct = products.first { $0.id == Self.yearlyID }
        // 無料体験を使えるかを確かめてから、年額を買えるようにする（確かめる前に「無料」と出さない）
        if let subscription = yearlyProduct?.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
        yearly = yearlyProduct
        monthly = products.first { $0.id == Self.monthlyID }
        return yearly != nil && monthly != nil
    }

    private func checkTrial() async {
        if let subscription = yearly?.subscription {
            isEligibleForTrial = await subscription.isEligibleForIntroOffer
        }
    }

    /// いま有効な権利を確かめる
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        if active != isPro {
            isPro = active
            onChange?(active)
        }
        await checkTrial()
    }

    /// 購入の結果を受け取る
    func handle(_ result: Product.PurchaseResult) async -> PurchaseOutcome {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                return .unverified
            }
            await transaction.finish()
            await refresh()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// 購入を復元する。App Store と同期できなかったら false（自分でやめたときは true）
    @discardableResult
    func restore() async -> Bool {
        var synced = true
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            synced = true
        } catch {
            synced = false
        }
        await refresh()
        return synced
    }
}

extension Product {
    /// 無料体験の日数（無ければ nil）
    var freeTrialDays: Int? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return nil
        }
        let period = offer.period
        switch period.unit {
        case .day:
            return period.value
        case .week:
            return period.value * 7
        case .month:
            return period.value * 30
        case .year:
            return period.value * 365
        @unknown default:
            return nil
        }
    }
}
