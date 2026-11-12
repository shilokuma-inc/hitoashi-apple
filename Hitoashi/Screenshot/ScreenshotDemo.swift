//
//  ScreenshotDemo.swift
//  Hitoashi
//
//  App Store 用スクリーンショットの撮影モード。
//  Tools/capture_screenshots.sh が次の起動引数でアプリを起動し、目的の画面をデモデータで開かせる。
//
//    -screenshot-demo -screenshot-scene <Scene の rawValue> -AppleLanguages (<言語>) -AppleLocale <ロケール>
//
//  画面を足すときは、Scene に case を足し、Hitoashi.swift の AppLaunch.applyScene で状態を整え、
//  AppStore/screenshots.json の scenes に同じ rawValue を足す（突き合わせは Tools/app_store_config.py が行う）。
//  デモデータは実データと混ざらないよう、撮影モードのときだけメモリ上やインメモリのストアに用意する。
//

import Foundation

enum ScreenshotDemo {
    /// 撮る画面。rawValue が AppStore/screenshots.json の scene と対応する
    enum Scene: String {
        /// きょう（昼の雨が上がったあとに、ひと足がある日）
        case home
        /// きょう（一日じゅう雨の日。屋根のあるところを歩く案）
        case rainyDay
        /// きょう（警報が出ている日。休む日）
        case restDay
        /// きょう（Pro。すべての空き時間の提案と、今週の歩きどき）
        case pro
        /// ひと足の詳細
        case detail
        /// 記録
        case log
        /// 設定
        case settings
        /// はじめに
        case onboarding
        /// ペイウォール
        case paywall
    }

    /// 撮影モードで起動しているか
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-screenshot-demo")

    /// 撮影モードで開く画面。撮影モードでないときと、知らない値を渡されたときは nil
    static let scene: Scene? = {
        guard isEnabled else {
            return nil
        }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshot-scene"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return Scene(rawValue: arguments[index + 1])
    }()
}
