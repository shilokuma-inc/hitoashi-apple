//
//  AppModel+Services.swift
//  Hitoashi
//
//  カレンダーの許可・拠点の登録・通知の予約（実データのとき）。
//

import Foundation
import HitoashiKit

// MARK: - カレンダー

extension AppModel {
    /// 予定を読めるか（見本のデータのときは、読めるものとして扱う）
    var hasCalendarAccess: Bool {
        _ = calendarRevision
        return environment.calendarService?.hasAccess ?? environment.isDemo
    }

    /// まだ許可を求めていないか
    var canAskCalendar: Bool {
        _ = calendarRevision
        return environment.calendarService?.canAsk ?? false
    }

    /// カレンダーの許可を求める。見本のデータのときは何もしない
    @discardableResult
    func requestCalendarAccess() async -> Bool {
        guard let service = environment.calendarService else {
            return true
        }
        let granted = await service.requestAccess()
        calendarRevision += 1
        await refresh()
        return granted
    }

    var calendars: [CalendarInfo] {
        _ = calendarRevision
        return environment.calendarService?.calendars() ?? []
    }

    func isCalendarOn(_ info: CalendarInfo) -> Bool {
        _ = calendarRevision
        return environment.settings.calendarIDs?.contains(info.id) ?? info.isOnByDefault
    }

    func setCalendar(_ info: CalendarInfo, isOn: Bool) {
        var ids = environment.settings.calendarIDs ?? Set(calendars.filter(\.isOnByDefault).map(\.id))
        if isOn {
            ids.insert(info.id)
        } else {
            ids.remove(info.id)
        }
        environment.settings.calendarIDs = ids
        calendarRevision += 1
        Task { await refresh() }
    }

    /// 今日から 7 日のあいだに、読めた予定があるか（無ければ、アカウントの追加の案内を出す）
    var hasUpcomingEvents: Bool {
        plans.prefix(7).contains { !$0.events.isEmpty }
    }
}

// MARK: - 拠点

extension AppModel {
    func base(_ kind: BaseKind) -> BasePlace? {
        bases.first { $0.kind == kind }
    }

    /// 拠点を登録する（同じ種類があれば置き換える）
    func setBase(_ kind: BaseKind, name: String, coordinate: Coordinate) {
        var updated = bases.filter { $0.kind != kind }
        updated.append(BasePlace(id: kind.rawValue, kind: kind, name: name, coordinate: coordinate))
        // 自宅 → 職場 の順に並べる
        bases = updated.sorted { ($0.kind == .home ? 0 : 1) < ($1.kind == .home ? 0 : 1) }
        basesChanged()
    }

    func removeBase(_ kind: BaseKind) {
        bases = bases.filter { $0.kind != kind }
        basesChanged()
    }

    /// 場所の文字列の検索は拠点の周辺を優先するので、拠点が変わったら、覚えた位置を捨てて調べ直す
    private func basesChanged() {
        (environment.provider as? LiveWorldProvider)?.forgetPlaces()
        Task { await refresh() }
    }

    /// 住所・駅名・建物の名前で探す
    func searchPlaces(_ query: String) async -> [GeocodeHit] {
        await finder.search(query, near: bases.first?.coordinate)
    }

    /// 現在地（許可は「使用中のみ」。拠点の登録のときだけ使う）
    func currentPlace() async -> GeocodeHit? {
        guard let coordinate = await locator.current() else {
            return nil
        }
        let name = await finder.placeName(at: coordinate) ?? String(localized: "現在地")
        return GeocodeHit(coordinate: coordinate, name: name, placeNames: [])
    }
}

// MARK: - 通知

extension AppModel {
    /// 「この時刻に知らせる」: 通知の許可を求め、この端末で通知を出すようにする。
    /// `day` を渡すと、その日を週の回数の決まりに関わらず「知らせる日」にする（押したひと足の通知が出ないことを避ける）
    func enableNotices(for day: Date? = nil) async {
        if let notices = environment.notices, !environment.isDemo {
            guard await notices.requestAuthorization() else {
                noticesDenied = true
                return
            }
        }
        noticesDenied = false
        noticesEnabled = true
        environment.settings.noticesEnabled = true
        if let day {
            var ledger = environment.settings.ledger
            ledger.confirmedDays.insert(NotificationPlanner.dayKey(day, calendar: calendar))
            environment.settings.ledger = ledger
        }
        await scheduleNotices()
    }

    func disableNotices() {
        noticesEnabled = false
        environment.settings.noticesEnabled = false
        environment.notices?.cancelAll()
    }

    /// 通知を作り直す（48 時間先まで）。見本のデータのときは予約しない
    func scheduleNotices() async {
        guard noticesEnabled, !environment.isDemo, let notices = environment.notices else {
            return
        }
        let output = NotificationPlanner.plan(
            NotificationPlanner.Input(
                plans: plans,
                ledger: environment.settings.ledger,
                preferences: preferences,
                now: now,
                calendar: calendar,
                phrasebook: book
            )
        )
        environment.settings.ledger = output.ledger
        await notices.schedule(output.notices, calendar: calendar)
    }
}
