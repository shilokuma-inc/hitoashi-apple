//
//  NoticeScheduler.swift
//  Hitoashi
//
//  通知を予約する（UserNotifications）。何をいつ出すかは HitoashiKit の NotificationPlanner が決め、ここは予約するだけ。
//  予約は 48 時間先までで、更新のたびに作り直す（仕様書 §5-9）。
//

import Foundation
import HitoashiKit
import OSLog
import UserNotifications

final class NoticeScheduler: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let category = "step"
    nonisolated private static let openAction = "open"
    nonisolated private static let skipAction = "skip"
    nonisolated private static let suggestionKey = "suggestionID"
    nonisolated private static let logger = Logger(subsystem: "jp.shilokuma.Hitoashi", category: "notices")

    /// 通知を押した・「行く」を選んだとき（提案の id）
    var onOpen: ((String) -> Void)?
    /// 「きょうはやめておく」を選んだとき
    var onSkip: ((String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    /// アプリの起動時に 1 回呼ぶ（通知の操作を受け取れるようにする）
    func activate() {
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openAction, title: String(localized: "行く"), options: [.foreground])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: String(localized: "きょうはやめておく"), options: [])
        let category = UNNotificationCategory(identifier: Self.category, actions: [open, skip], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 予約済みの通知を消して、作り直す
    func schedule(_ notices: [PlannedNotice], calendar: Calendar) async {
        center.removeAllPendingNotificationRequests()
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            if let suggestionID = notice.suggestionID {
                content.userInfo = [Self.suggestionKey: suggestionID]
                content.categoryIdentifier = Self.category
            }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notice.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: trigger))
        }
        // 件数と種類だけを記録する（文面や予定の中身は書かない）
        let kinds = notices.map(\.kind.rawValue).joined(separator: ",")
        Self.logger.info("scheduled \(notices.count, privacy: .public) [\(kinds, privacy: .public)]")
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - UNUserNotificationCenterDelegate

    // どちらもメインで受ける（この型はメインに属する）。OS への完了の合図もメインから返る。
    // メイン以外から完了を返すと、通知を押したときに落ちることがある

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let suggestionID = response.notification.request.content.userInfo[Self.suggestionKey] as? String else {
            return
        }
        if response.actionIdentifier == Self.skipAction {
            onSkip?(suggestionID)
        } else {
            onOpen?(suggestionID)
        }
    }
}
