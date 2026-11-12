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
    /// 権利が変わったとき
    var onChange: ((Bool) -> Void)?

    private var updates: Task<Void, Never>?

    /// 商品を取り、権利を確かめ、変化を見張る
    func start() {
        guard updates == nil else {
            return
        }
        updates = Task {
            await load()
            await refresh()
            for await _ in Transaction.updates {
                await refresh()
            }
        }
    }

    func load() async {
        let products = (try? await Product.products(for: Self.productIDs)) ?? []
        yearly = products.first { $0.id == Self.yearlyID }
        monthly = products.first { $0.id == Self.monthlyID }
    }

    /// いま有効な権利を確かめる
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        if active != isPro {
            isPro = active
            onChange?(active)
        }
    }

    /// 購入の結果を受け取る
    func handle(_ result: Product.PurchaseResult) async {
        if case .success(let verification) = result, case .verified(let transaction) = verification {
            await transaction.finish()
        }
        await refresh()
    }

    /// 購入を復元する
    func restore() async {
        try? await AppStore.sync()
        await refresh()
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
