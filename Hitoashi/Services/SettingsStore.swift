//
//  SettingsStore.swift
//  Hitoashi
//
//  設定と小さな状態を UserDefaults に保存する。値は JSON にして 1 つのキーに入れる。
//

import Foundation
import HitoashiKit

final class SettingsStore {
    private enum Key: String {
        case preferences
        case bases
        case ledger
        case rejectedSpots
        case hasOnboarded
        case showsDemo
        case noticesEnabled
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// テストと撮影モード用の、空の保存先
    static func ephemeral() -> SettingsStore {
        let name = "jp.shilokuma.Hitoashi.ephemeral"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return SettingsStore(defaults: defaults)
    }

    var preferences: Preferences {
        get { load(.preferences) ?? Preferences() }
        set { save(newValue, .preferences) }
    }

    var bases: [BasePlace] {
        get { load(.bases) ?? [] }
        set { save(newValue, .bases) }
    }

    var ledger: NoticeLedger {
        get { load(.ledger) ?? NoticeLedger() }
        set { save(newValue, .ledger) }
    }

    /// 「この場所は出さない」としたスポット
    var rejectedSpotIDs: Set<String> {
        get { load(.rejectedSpots) ?? [] }
        set { save(newValue, .rejectedSpots) }
    }

    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded.rawValue) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded.rawValue) }
    }

    /// 見本を表示するか
    var showsDemo: Bool {
        get { defaults.bool(forKey: Key.showsDemo.rawValue) }
        set { defaults.set(newValue, forKey: Key.showsDemo.rawValue) }
    }

    /// この端末で通知を出すか（「この時刻に知らせる」を押した端末だけ）
    var noticesEnabled: Bool {
        get { defaults.bool(forKey: Key.noticesEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.noticesEnabled.rawValue) }
    }

    /// 保存したものをすべて消す
    func eraseAll() {
        for key in [Key.preferences, .bases, .ledger, .rejectedSpots, .hasOnboarded, .showsDemo, .noticesEnabled] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private func load<Value: Decodable>(_ key: Key) -> Value? {
        guard let data = defaults.data(forKey: key.rawValue) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, _ key: Key) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key.rawValue)
        }
    }
}
