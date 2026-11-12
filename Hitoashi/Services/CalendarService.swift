//
//  CalendarService.swift
//  Hitoashi
//
//  カレンダーの予定を読む（EventKit）。読むだけで、予定の作成・変更・削除はしない（仕様書 §2）。
//  EKEventStore と EKEvent は Sendable ではないので、ここで値の型（PlanEvent）に写して渡す。
//

import EventKit
import HitoashiKit

/// 対象に選べるカレンダー
struct CalendarInfo: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// アカウントの名前（iCloud・Google など）
    var sourceTitle: String
    /// 既定でオンにするか（自分で編集できるカレンダーだけ。祝日・誕生日・購読はオフ）
    var isOnByDefault: Bool
}

final class CalendarService {
    private let store = EKEventStore()

    /// 予定を読めるか（フルアクセス。読み取りだけの許可は用意されていない）
    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// まだ許可を求めていないか
    var canAsk: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        guard hasAccess else {
            return []
        }
        return store.calendars(for: .event)
            .map { calendar in
                let isSpecial = calendar.type == .subscription || calendar.type == .birthday
                return CalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source?.title ?? "",
                    isOnByDefault: calendar.allowsContentModifications && !isSpecial
                )
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    /// 期間の中の予定。`calendarIDs` が nil なら、既定でオンのカレンダー
    func events(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [PlanEvent] {
        guard hasAccess else {
            return []
        }
        let wanted = calendarIDs ?? Set(calendars().filter(\.isOnByDefault).map(\.id))
        let calendars = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(Self.planEvent)
    }

    private static func planEvent(_ event: EKEvent) -> PlanEvent {
        // 繰り返しの予定は eventIdentifier が全回で同じなので、開始の時刻を足して区別する
        let identifier = "\(event.eventIdentifier ?? UUID().uuidString)@\(Int(event.startDate.timeIntervalSince1970))"
        let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        let coordinate = event.structuredLocation?.geoLocation.map { location in
            Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        return PlanEvent(
            id: identifier,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            locationText: event.location ?? event.structuredLocation?.title,
            coordinate: coordinate,
            isCanceled: event.status == .canceled,
            isDeclined: declined,
            calendarID: event.calendar?.calendarIdentifier ?? ""
        )
    }
}
