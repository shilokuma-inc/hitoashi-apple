//
//  JSONFileCache.swift
//  Hitoashi
//
//  小さな保存（予報・スポット・ジオコーディングの結果）。キーごとの値と保存した時刻を、JSON の 1 ファイルに入れる。
//  期限を過ぎたものは返さず、開いたとき・書くとき・`removeExpired` を呼んだときにファイルからも消す。
//  予報は最長 24 時間で必ず消す（WeatherKit の規約。仕様書 §5-10）。
//

import Foundation

final class JSONFileCache<Value: Codable> {
    private struct Entry: Codable {
        var savedAt: Date
        var value: Value
    }

    private let url: URL
    /// これを過ぎたものは捨てる（秒）
    private let lifetime: TimeInterval
    private var entries: [String: Entry]

    /// - Parameter now: 開いたときの時刻（期限切れを捨てる基準。テストでは固定の時刻を渡す）
    init(name: String, lifetime: TimeInterval, now: Date = Date()) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = directory.appendingPathComponent("\(name).json")
        self.lifetime = lifetime
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        removeExpired(now: now)
    }

    /// 期限の切れたものを、ファイルからも消す
    func removeExpired(now: Date) {
        let kept = entries.filter { now.timeIntervalSince($0.value.savedAt) < lifetime }
        guard kept.count != entries.count else {
            return
        }
        entries = kept
        save()
    }

    private func save() {
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 保存した値と、保存した時刻。期限を過ぎていれば nil
    func entry(for key: String, now: Date) -> (value: Value, savedAt: Date)? {
        guard let entry = entries[key], now.timeIntervalSince(entry.savedAt) < lifetime else {
            return nil
        }
        return (entry.value, entry.savedAt)
    }

    func set(_ value: Value, for key: String, now: Date) {
        entries[key] = Entry(savedAt: now, value: value)
        // 期限の切れたものは、書くときにも消す
        entries = entries.filter { now.timeIntervalSince($0.value.savedAt) < lifetime }
        save()
    }

    func removeAll() {
        entries = [:]
        try? FileManager.default.removeItem(at: url)
    }
}
