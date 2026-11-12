//
//  StoreTests.swift
//  HitoashiTests
//
//  StoreKit の設定ファイル（Hitoashi.storekit）で、商品の取得（価格・無料体験の設定）と、
//  購入して Pro に切り替わるまでを確かめる。
//
//  Mac でだけ走らせる。CI の iOS Simulator では、SKTestSession が設定ファイルを保存できず
//  （`Error saving configuration file: SKInternalErrorDomain Code=3`）、商品が空で返る。原因は分かっていない。
//  CI は Mac のテストを走らせないので、このテストは手元で
//  `-destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO` を付けて確かめる。
//  並列のままだと、複数のプロセスが同じ StoreKit のテスト環境を使い、片方の clearTransactions() が
//  もう片方の購入を消す（失敗したり、購入が返らずに固まったりする）。
//

#if os(macOS)

import Foundation
@testable import Hitoashi
import StoreKit
import StoreKitTest
import Testing

@MainActor
@Suite(.serialized)
struct StoreTests {
    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Hitoashi")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    @Test
    func loadsBothPlansWithATwoWeekTrialOnTheYearlyPlan() async throws {
        _ = try makeSession()
        let store = Store()
        await store.load()
        let yearly = try #require(store.yearly)
        let monthly = try #require(store.monthly)
        #expect(yearly.id == Store.yearlyID)
        #expect(monthly.id == Store.monthlyID)
        // 無料体験は年額だけ（14 日間）
        #expect(yearly.freeTrialDays == 14)
        #expect(monthly.freeTrialDays == nil)
        // まだ買っていないので、無料体験を使える
        #expect(store.isEligibleForTrial)
        #expect(yearly.price == 2800)
        #expect(monthly.price == 400)
    }

    @Test(.timeLimit(.minutes(1)))
    func purchasingTheYearlyPlanTurnsProOn() async throws {
        _ = try makeSession()
        let store = Store()
        await store.load()
        let yearly = try #require(store.yearly)
        var changes: [Bool] = []
        store.onChange = { changes.append($0) }
        #expect(!store.isPro)

        let outcome = await store.handle(try await yearly.purchase())

        #expect(outcome == .purchased)
        #expect(store.isPro)
        // 画面（AppModel）には、権利が付いたことが 1 回だけ伝わる
        #expect(changes == [true])
        // 買ったあとは、無料体験をもう使えない
        #expect(!store.isEligibleForTrial)
    }

    @Test(.timeLimit(.minutes(1)))
    func aPurchaseMadeBeforeLaunchIsFoundOnRefresh() async throws {
        _ = try makeSession()
        let buyer = Store()
        await buyer.load()
        _ = await buyer.handle(try await #require(buyer.monthly).purchase())

        // 起動し直したつもりで、新しい Store で権利を確かめる
        let store = Store()
        #expect(!store.isPro)
        await store.refresh()
        #expect(store.isPro)
    }
}
#endif
