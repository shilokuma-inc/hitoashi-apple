//
//  DebugCalendarSeeder.swift
//  Hitoashi
//
//  Simulator のカレンダーに、確認用の予定を入れる（DEBUG のビルド・Simulator だけ）。
//  実データ（EventKit・WeatherKit・MapKit）の流れを、Simulator で通して確かめるためのもの。
//  出荷するアプリは、予定を作らない（仕様書 §2）。
//
//    xcrun simctl privacy <udid> grant calendar jp.shilokuma.Hitoashi
//    xcrun simctl launch <udid> jp.shilokuma.Hitoashi -seed-calendar YES
//

#if DEBUG && targetEnvironment(simulator)
import CoreLocation
import EventKit

enum DebugCalendarSeeder {
    private static let marker = "[ひとあし確認用]"

    static func seedIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-seed-calendar") else {
            return
        }
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true, let calendar = store.defaultCalendarForNewEvents else {
            return
        }
        let today = Calendar.current.startOfDay(for: .now)
        let end = today.addingTimeInterval(3 * 24 * 3600)
        let existing = store.events(matching: store.predicateForEvents(withStart: today, end: end, calendars: nil))
        guard !existing.contains(where: { ($0.notes ?? "").contains(marker) }) else {
            return
        }
        let shibuya = CLLocation(latitude: 35.6642, longitude: 139.6997)
        add("定例ミーティング", day: 0, from: 10, to: 11, location: "https://example.com/meeting/000", in: store, calendar)
        add("打ち合わせ", day: 0, from: 13, to: 14.5, location: "渋谷 神南オフィス", at: shibuya, in: store, calendar)
        add("1on1", day: 0, from: 16, to: 17, location: "8F Fuji", in: store, calendar)
        add("会食", day: 0, from: 19, to: 21, location: "恵比寿ガーデンプレイス", in: store, calendar)
        add("朝会", day: 1, from: 9.5, to: 10, location: nil, in: store, calendar)
        add("レビュー会", day: 1, from: 14, to: 15.5, location: "東京都千代田区丸の内 2-4-1", in: store, calendar)
        try? store.commit()
    }

    private static func add(
        _ title: String,
        day: Int,
        from start: Double,
        to end: Double,
        location: String?,
        at coordinate: CLLocation? = nil,
        in store: EKEventStore,
        _ calendar: EKCalendar
    ) {
        let today = Calendar.current.startOfDay(for: .now)
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = marker
        event.calendar = calendar
        event.startDate = today.addingTimeInterval(Double(day) * 24 * 3600 + start * 3600)
        event.endDate = today.addingTimeInterval(Double(day) * 24 * 3600 + end * 3600)
        if let coordinate, let location {
            let structured = EKStructuredLocation(title: location)
            structured.geoLocation = coordinate
            event.structuredLocation = structured
        } else {
            event.location = location
        }
        try? store.save(event, span: .thisEvent, commit: false)
    }
}
#endif
