//
//  AppEnvironment.swift
//  Hitoashi
//
//  アプリが使う外の世界（材料の取り方・時計・保存先）をまとめたもの。
//  撮影モードと UI テストでは、見本のデータと固定の時刻に差し替える。
//

import Foundation
import HitoashiKit

struct AppEnvironment {
    var provider: any WorldProviding
    var settings: SettingsStore
    var logs: LogStore
    var calendar: Calendar
    /// いまの時刻（見本では固定）
    var clock: @Sendable () -> Date
    /// 見本のデータで動いているか
    var isDemo: Bool

    /// 見本のデータで動かす（撮影モード・UI テスト・プレビュー）
    static func demo(alertToday: Bool = false, settings: SettingsStore = .ephemeral()) -> AppEnvironment {
        let logs = LogStore(inMemory: true)
        logs.seedDemo()
        if settings.bases.isEmpty {
            settings.bases = DemoData.world().bases
        }
        return AppEnvironment(
            provider: DemoWorldProvider(alertToday: alertToday),
            settings: settings,
            logs: logs,
            calendar: DemoData.calendar,
            clock: { DemoData.now },
            isDemo: true
        )
    }
}
