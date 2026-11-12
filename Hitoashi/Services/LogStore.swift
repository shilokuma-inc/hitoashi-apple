//
//  LogStore.swift
//  Hitoashi
//
//  記録（仕様書 §5-11）。1 件 = 日時・動き方・分数・場所の名前・外 / 屋内の別・やった / やらなかった。
//  気温・天気・判定は保存しない（WeatherKit の規約）。予定の題名も入れない。
//

import Foundation
import HitoashiKit
import SwiftData

@Model
final class StepLog {
    /// 始めた・やった・やらなかった
    enum Outcome: String, Codable {
        /// 「行く」を押した（まだ答えていない）
        case started
        case done
        case skipped
    }

    var id: UUID
    /// ひと足の時刻
    var date: Date
    /// 「代々木公園まで歩く」
    var title: String
    var minutes: Int
    var isOutdoor: Bool
    var outcomeRaw: String
    /// もとの提案（空き時間）の id
    var suggestionID: String
    /// 空き時間の種類（次の提案の順位に使う）
    var slotKindRaw: String

    init(date: Date, title: String, minutes: Int, isOutdoor: Bool, outcome: Outcome, suggestionID: String, slotKind: SlotKind) {
        id = UUID()
        self.date = date
        self.title = title
        self.minutes = minutes
        self.isOutdoor = isOutdoor
        outcomeRaw = outcome.rawValue
        self.suggestionID = suggestionID
        slotKindRaw = slotKind.rawValue
    }

    var outcome: Outcome {
        get { Outcome(rawValue: outcomeRaw) ?? .started }
        set { outcomeRaw = newValue.rawValue }
    }
}

/// 記録の読み書き
final class LogStore {
    let container: ModelContainer

    init(inMemory: Bool) {
        // App Group や iCloud の entitlement を足しても保存先が変わらないよう、明示する
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: StepLog.self, configurations: configuration)
        } catch {
            fatalError("記録の保存先を開けません: \(error)")
        }
    }

    private var context: ModelContext { container.mainContext }

    func all() -> [StepLog] {
        let descriptor = FetchDescriptor<StepLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func log(for suggestionID: String) -> StepLog? {
        all().first { $0.suggestionID == suggestionID }
    }

    /// 「行く」「きょうはやめておく」「やった」を記録する（同じ提案は上書き）
    func record(_ suggestion: Suggestion, title: String, outcome: StepLog.Outcome) {
        if let existing = log(for: suggestion.id) {
            existing.outcome = outcome
            existing.title = title
            existing.minutes = suggestion.plan.minutes
            existing.isOutdoor = suggestion.plan.activity.isOutdoor
        } else {
            context.insert(
                StepLog(
                    date: suggestion.window.start,
                    title: title,
                    minutes: suggestion.plan.minutes,
                    isOutdoor: suggestion.plan.activity.isOutdoor,
                    outcome: outcome,
                    suggestionID: suggestion.id,
                    slotKind: suggestion.slot.kind
                )
            )
        }
        try? context.save()
    }

    func setOutcome(_ outcome: StepLog.Outcome, for log: StepLog) {
        log.outcome = outcome
        try? context.save()
    }

    func eraseAll() {
        try? context.delete(model: StepLog.self)
        try? context.save()
    }

    /// 見本の記録を入れる（見本の表示・撮影モード）
    func seedDemo() {
        guard all().isEmpty else {
            return
        }
        let samples: [DemoLog] = [
            DemoLog(day: -1, hour: 12, minute: 10, title: "日比谷公園まで歩く", minutes: 20, isOutdoor: true),
            DemoLog(day: -2, hour: 12, minute: 0, title: "和田倉噴水公園まで歩く", minutes: 20, isOutdoor: true),
            DemoLog(day: -3, hour: 12, minute: 10, title: "丸ビルの中を歩く", minutes: 15, isOutdoor: false),
            DemoLog(day: -6, hour: 18, minute: 5, title: "有楽町駅まで歩く", minutes: 15, isOutdoor: true),
            DemoLog(day: -8, hour: 12, minute: 0, title: "和田倉噴水公園まで歩く", minutes: 20, isOutdoor: true)
        ]
        for (index, sample) in samples.enumerated() {
            let log = StepLog(
                date: DemoData.date(day: sample.day, hour: sample.hour, minute: sample.minute),
                title: sample.title,
                minutes: sample.minutes,
                isOutdoor: sample.isOutdoor,
                outcome: index == 0 ? .started : .done,
                suggestionID: "demo-\(index)",
                slotKind: .lunch
            )
            context.insert(log)
        }
        try? context.save()
    }
}

/// 見本の記録 1 件
private struct DemoLog {
    var day: Int
    var hour: Int
    var minute: Int
    var title: String
    var minutes: Int
    var isOutdoor: Bool
}
