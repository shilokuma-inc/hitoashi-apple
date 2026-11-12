//
//  JSONFileCacheTests.swift
//  HitoashiTests
//
//  小さな保存（JSONFileCache）が、期限を過ぎた値を返さないことと、作り直しても読めることを確かめる。
//

import Foundation
@testable import Hitoashi
import Testing

@MainActor
struct JSONFileCacheTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeCache(_ name: String, lifetime: TimeInterval = 3600) -> JSONFileCache<String> {
        JSONFileCache<String>(name: name, lifetime: lifetime)
    }

    @Test
    func returnsTheValueUntilItsLifetimeEnds() {
        let cache = makeCache("test-\(UUID().uuidString)")
        defer { cache.removeAll() }
        cache.set("晴れ", for: "tokyo", now: start)

        let fresh = cache.entry(for: "tokyo", now: start.addingTimeInterval(3599))
        #expect(fresh?.value == "晴れ")
        #expect(fresh?.savedAt == start)
        // 期限ちょうどで捨てる
        #expect(cache.entry(for: "tokyo", now: start.addingTimeInterval(3600)) == nil)
        #expect(cache.entry(for: "osaka", now: start) == nil)
    }

    @Test
    func keepsValuesAcrossInstancesAndDropsExpiredOnesOnWrite() {
        let name = "test-\(UUID().uuidString)"
        let first = makeCache(name)
        first.set("古い", for: "old", now: start)
        // 2 時間後に別の値を書くと、期限の切れた値はファイルからも消える
        first.set("新しい", for: "new", now: start.addingTimeInterval(7200))

        let second = makeCache(name)
        defer { second.removeAll() }
        #expect(second.entry(for: "new", now: start.addingTimeInterval(7200))?.value == "新しい")
        #expect(second.entry(for: "old", now: start) == nil)
    }

    @Test
    func removeExpiredDeletesOldValuesFromTheFileWithoutAWrite() {
        let name = "test-\(UUID().uuidString)"
        let cache = makeCache(name)
        cache.set("きのうの予報", for: "tokyo", now: start)
        // 取り直せない（書き込みが起きない）ままでも、期限が来たらファイルから消える
        cache.removeExpired(now: start.addingTimeInterval(3600))

        let reopened = makeCache(name)
        defer { reopened.removeAll() }
        #expect(reopened.entry(for: "tokyo", now: start) == nil)
    }

    @Test
    func removeAllDeletesTheFile() {
        let name = "test-\(UUID().uuidString)"
        let cache = makeCache(name)
        cache.set("値", for: "key", now: start)
        cache.removeAll()

        #expect(cache.entry(for: "key", now: start) == nil)
        #expect(makeCache(name).entry(for: "key", now: start) == nil)
    }
}
