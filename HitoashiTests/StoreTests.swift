//
//  StoreTests.swift
//  HitoashiTests
//
//  StoreKit の設定ファイル（Hitoashi.storekit）で、商品を取得できることと、価格・無料体験の設定を確かめる。
//

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
        #expect(yearly.price == 2800)
        #expect(monthly.price == 400)
    }
}
