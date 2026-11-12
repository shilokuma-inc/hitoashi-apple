//
//  BackgroundRefresh.swift
//  Hitoashi
//
//  バックグラウンド更新（iOS・visionOS）。走れば、予報を取り直して通知を作り直す。
//  走る頻度は OS しだいで、まったく走らないこともある。だから通知は、予報が古ければ天気を書かない文面にしてある（仕様書 §5-9）。
//  Mac には、この仕組みが無い。
//

import Foundation

#if !os(macOS)
import BackgroundTasks
#endif

enum BackgroundRefresh {
    static let identifier = "jp.shilokuma.Hitoashi.refresh"

    /// 次の更新を頼む（2 時間後以降）。アプリが背面に回るたびに呼ぶ
    static func schedule() {
        #if !os(macOS)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    /// バックグラウンドで起こされたとき
    static func run() async {
        // 次の更新を先に頼んでおく（今回の更新が時間切れで打ち切られても、次が残るように）
        schedule()
        await AppSession.shared.model.refresh()
    }
}
