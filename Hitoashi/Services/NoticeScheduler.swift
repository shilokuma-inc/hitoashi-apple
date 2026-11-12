//
//  NoticeScheduler.swift
//  Hitoashi
//
//  通知を予約する（UserNotifications）。何をいつ出すかは HitoashiKit の NotificationPlanner が決め、ここは予約するだけ。
//  予約は 48 時間先までで、更新のたびに作り直す（仕様書 §5-9）。
//

import Foundation
import HitoashiKit
import UserNotifications

final class NoticeScheduler: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let category = "step"
    private nonisolated static let openAction = "open"
    private nonisolated static let skipAction = "skip"
    private nonisolated static let suggestionKey = "suggestionID"

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
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let suggestionID = response.notification.request.content.userInfo[Self.suggestionKey] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            guard let suggestionID else {
                return
            }
            if action == Self.skipAction {
                onSkip?(suggestionID)
            } else {
                onOpen?(suggestionID)
            }
        }
    }
}
