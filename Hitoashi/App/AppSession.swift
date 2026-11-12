//
//  AppSession.swift
//  Hitoashi
//
//  アプリの環境（実データか、見本のデータか）を持ち、切り替える。
//  撮影モードと「設定 → 見本を表示」では、見本のデータで動かす。
//

import EventKit
import Foundation
import Observation

@Observable
final class AppSession {
    /// アプリに 1 つだけ（バックグラウンド更新からも同じものを使う）
    static let shared = AppSession()

    private(set) var model: AppModel
    private let store = Store()
    private let notices = NoticeScheduler()
    private var calendarObserver: (any NSObjectProtocol)?

    private init() {
        model = AppModel(environment: Self.makeEnvironment(store: store, notices: notices))
        notices.activate()
        connect()
        if !model.environment.isDemo {
            store.start()
        }
        // カレンダーが変わったら、取り込み直す
        let center = NotificationCenter.default
        calendarObserver = center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh()
            }
        }
    }

    /// 「見本を表示」の切り替え
    func setDemo(_ isOn: Bool) {
        SettingsStore().showsDemo = isOn
        model = AppModel(environment: Self.makeEnvironment(store: store, notices: notices))
        connect()
        if !isOn {
            store.start()
        }
        Task { await model.refresh() }
    }

    private func connect() {
        model.onToggleDemo = { [weak self] isOn in
            self?.setDemo(isOn)
        }
        notices.onOpen = { [weak self] suggestionID in
            self?.model.selectedTab = .today
            self?.model.routeToOpen = suggestionID
        }
        notices.onSkip = { [weak self] suggestionID in
            guard let model = self?.model, let suggestion = model.suggestion(id: suggestionID) else {
                return
            }
            model.record(suggestion, outcome: .skipped)
        }
    }

    private static func makeEnvironment(store: Store, notices: NoticeScheduler) -> AppEnvironment {
        if ScreenshotDemo.isEnabled {
            let environment = AppEnvironment.demo(alertToday: ScreenshotDemo.scene == .restDay)
            environment.settings.hasOnboarded = ScreenshotDemo.scene != .onboarding
            return environment
        }
        if SettingsStore().showsDemo {
            // 見本は、利用者の設定や記録とは別の、まっさらな保存先で動かす
            let environment = AppEnvironment.demo()
            environment.settings.hasOnboarded = true
            return environment
        }
        return .live(notices: notices, store: store)
    }
}
