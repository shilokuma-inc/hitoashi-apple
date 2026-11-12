//
//  RootView.swift
//  Hitoashi
//
//  画面の入口。タブは iPhone では下、iPad と Mac ではサイドバー、Vision Pro ではウインドウの脇に出る（OS の標準の振る舞い）。
//

import HitoashiKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasOnboarded {
                TabView(selection: $model.selectedTab) {
                    Tab("きょう", systemImage: "calendar", value: AppTab.today) {
                        TodayScreen()
                    }
                    Tab("記録", systemImage: "chart.bar", value: AppTab.log) {
                        LogScreen()
                    }
                    Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                        SettingsScreen()
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                OnboardingView()
            }
        }
        .tint(Palette.ink)
        .sheet(isPresented: $model.showsPaywall) {
            PaywallView()
        }
    }
}

/// きょう。狭い画面（iPhone）は 1 列で、ひと足を押すと詳細へ進む。広い画面は、タイムラインと詳細を横に並べる
struct TodayScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path: [String] = []
    @State private var selectedID: String?

    var body: some View {
        Group {
            if sizeClass == .regular {
                wide
            } else {
                narrow
            }
        }
        .onChange(of: model.selectedDay) {
            // 日を変えたら、前の日のひと足を右に出したままにしない
            selectedID = nil
        }
        .onChange(of: model.routeToOpen, initial: true) { _, route in
            guard let route else {
                return
            }
            path = [route]
            selectedID = route
            model.routeToOpen = nil
        }
    }

    private var narrow: some View {
        NavigationStack(path: $path) {
            TodayTimeline { suggestion in
                path.append(suggestion.id)
            }
            .navigationTitle("きょう")
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(for: String.self) { id in
                StepDetailView(suggestionID: id)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
        }
    }

    private var wide: some View {
        HStack(spacing: 0) {
            TodayTimeline { suggestion in
                selectedID = suggestion.id
            }
            .frame(minWidth: 380, idealWidth: 480, maxWidth: 560)
            Rectangle()
                .fill(Palette.line)
                .frame(width: 1)
                .ignoresSafeArea()
            Group {
                if let id = shownID {
                    StepDetailView(suggestionID: id)
                } else {
                    ContentUnavailableView("ひと足を選ぶと、ここに出ます", systemImage: "figure.walk")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
        }
        .background(Palette.ground)
    }

    /// 広い画面で右に出すひと足。選んでいなければ、表示している日のひと足。
    /// 左のタイムラインに出していない提案（無料のときの 3 日目以降など）は、右にも出さない
    private var shownID: String? {
        if let selectedID, model.isShown(selectedID) {
            return selectedID
        }
        guard let plan = model.selectedPlan else {
            return nil
        }
        return plan.visible.first { $0.id == plan.top?.id }?.id ?? plan.visible.first?.id
    }
}
