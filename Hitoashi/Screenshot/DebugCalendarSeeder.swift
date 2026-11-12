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
        let samples = [
            Sample(title: "定例ミーティング", day: 0, start: 10, end: 11, location: "https://example.com/meeting/000"),
            Sample(title: "打ち合わせ", day: 0, start: 13, end: 14.5, location: "渋谷 神南オフィス", coordinate: shibuya),
            Sample(title: "1on1", day: 0, start: 16, end: 17, location: "8F Fuji"),
            Sample(title: "会食", day: 0, start: 19, end: 21, location: "恵比寿ガーデンプレイス"),
            Sample(title: "朝会", day: 1, start: 9.5, end: 10, location: nil),
            Sample(title: "レビュー会", day: 1, start: 14, end: 15.5, location: "東京都千代田区丸の内 2-4-1")
        ]
        for sample in samples {
            add(sample, to: calendar, in: store)
        }
        try? store.commit()
    }

    private struct Sample {
        var title: String
        var day: Int
        /// 開始・終了（その日の 0 時からの時間）
        var start: Double
        var end: Double
        var location: String?
        var coordinate: CLLocation?
    }

    private static func add(_ sample: Sample, to calendar: EKCalendar, in store: EKEventStore) {
        let today = Calendar.current.startOfDay(for: .now)
        let event = EKEvent(eventStore: store)
        event.title = sample.title
        event.notes = marker
        event.calendar = calendar
        event.startDate = today.addingTimeInterval(Double(sample.day) * 24 * 3600 + sample.start * 3600)
        event.endDate = today.addingTimeInterval(Double(sample.day) * 24 * 3600 + sample.end * 3600)
        if let coordinate = sample.coordinate, let location = sample.location {
            let structured = EKStructuredLocation(title: location)
            structured.geoLocation = coordinate
            event.structuredLocation = structured
        } else {
            event.location = sample.location
        }
        try? store.save(event, span: .thisEvent, commit: false)
    }
}
#endif
