//
//  StoreTests.swift
//  HitoashiTests
//
//  StoreKit の設定ファイル（Hitoashi.storekit）で、商品を取得できることと、価格・無料体験の設定を確かめる。
//
//  Mac でだけ走らせる。CI の iOS Simulator では、SKTestSession が設定ファイルを保存できず
//  （`Error saving configuration file: SKInternalErrorDomain Code=3`）、商品が空で返る。原因は分かっていない。
//  CI は Mac のテストを走らせないので、このテストは手元で `-destination 'platform=macOS,arch=arm64'` を付けて確かめる。
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
}
#endif
