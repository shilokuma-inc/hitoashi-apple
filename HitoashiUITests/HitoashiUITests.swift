//
//  HitoashiUITests.swift
//  HitoashiUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

/// 見本のデータ（撮影モード）で、主な流れが通ることを確かめる
final class HitoashiUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        // Mac では「-キー 値」の組で渡す（組になっていない引数は、ファイルを開く要求として扱われる）
        app.launchArguments = ["-screenshot-demo", "YES", "-screenshot-scene", scene, "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        return app
    }

    @MainActor
    func testTodayShowsTheStepAndOpensTheDetail() throws {
        let app = launch(scene: "home")
        let step = app.buttons["today.topStep"]
        XCTAssertTrue(step.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["見本を表示中"].exists)
        step.tap()
        XCTAssertTrue(app.buttons["detail.go"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.skip"].exists)
    }

    @MainActor
    func testOnboardingLeadsToToday() throws {
        let app = launch(scene: "onboarding")
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        // はじめに → カレンダー → 拠点 → 安全についての注意 → きょう
        for _ in 0..<4 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        XCTAssertTrue(app.buttons["today.topStep"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testMoreStepsRowOpensThePaywall() throws {
        let app = launch(scene: "home")
        let more = app.buttons["today.more"]
        XCTAssertTrue(app.buttons["today.topStep"].waitForExistence(timeout: 10))
        if !more.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        XCTAssertTrue(app.buttons["paywall.start"].waitForExistence(timeout: 5))
        app.buttons["paywall.close"].tap()
        XCTAssertFalse(app.buttons["paywall.start"].waitForExistence(timeout: 2))
    }
}
