//
//  Hitoashi.swift
//  Hitoashi
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct Hitoashi: App {
    @State private var session = AppSession.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session.model)
                // 環境（実データ / 見本）を切り替えたら、画面を作り直す
                .id(ObjectIdentifier(session.model))
                .task(id: ObjectIdentifier(session.model)) {
                    #if DEBUG
                    await WeatherProbe.runIfRequested()
                    #endif
                    #if DEBUG && targetEnvironment(simulator)
                    await DebugCalendarSeeder.seedIfRequested()
                    #endif
                    await session.model.refresh()
                    AppLaunch.applyScene(to: session.model)
                    #if DEBUG && os(macOS)
                    await WindowSnapshot.exportIfRequested()
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    // 前面に戻ったら、必ず判定し直す（仕様書 §5-1）
                    if phase == .active {
                        Task { await session.model.refresh() }
                    } else if phase == .background {
                        BackgroundRefresh.schedule()
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        #else
        // バックグラウンド更新。走れば予報と通知が新しくなる（走る頻度は OS しだいで、保証は無い。仕様書 §5-1）
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
        #endif
    }
}

/// 撮影モード（ScreenshotDemo）で開く画面に合わせて、状態を整える
enum AppLaunch {
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
