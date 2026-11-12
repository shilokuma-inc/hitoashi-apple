//
//  Hitoashi.swift
//  Hitoashi
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct Hitoashi: App {
    @State private var model = AppModel(environment: AppLaunch.environment())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    await model.refresh()
                    AppLaunch.applyScene(to: model)
                    #if DEBUG && os(macOS)
                    await WindowSnapshot.exportIfRequested()
                    #endif
                }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        #endif
    }
}

/// 起動のしかた。撮影モード（ScreenshotDemo）では、見本のデータで目的の画面を開く
enum AppLaunch {
    static func environment() -> AppEnvironment {
        let environment = AppEnvironment.demo(alertToday: ScreenshotDemo.scene == .restDay)
        if ScreenshotDemo.isEnabled, ScreenshotDemo.scene != .onboarding {
            environment.settings.hasOnboarded = true
        }
        return environment
    }

    /// 撮影モードで開く画面に合わせて、状態を整える
    static func applyScene(to model: AppModel) {
        guard let scene = ScreenshotDemo.scene else {
            return
        }
        switch scene {
        case .home, .restDay, .onboarding:
            break
        case .rainyDay:
            // 3 日目以降の提案は Pro なので、Pro の状態で見せる
            model.isPro = true
            model.selectedDay = 4
        case .pro:
            model.isPro = true
        case .detail:
            model.routeToOpen = model.selectedPlan?.top?.id
        case .log:
            model.selectedTab = .log
        case .settings:
            model.selectedTab = .settings
        case .paywall:
            model.showsPaywall = true
        }
    }
}
