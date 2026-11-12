//
//  JSONFileCache.swift
//  Hitoashi
//
//  小さな保存（予報・スポット・ジオコーディングの結果）。キーごとの値と保存した時刻を、JSON の 1 ファイルに入れる。
//  期限を過ぎたものは読むときに捨てる。予報は最長 24 時間で必ず消す（WeatherKit の規約。仕様書 §5-10）。
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

    init(name: String, lifetime: TimeInterval) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = directory.appendingPathComponent("\(name).json")
        self.lifetime = lifetime
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
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
        // 期限の切れたものは、書くときに消す
        entries = entries.filter { now.timeIntervalSince($0.value.savedAt) < lifetime }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func removeAll() {
        entries = [:]
        try? FileManager.default.removeItem(at: url)
    }
}
