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
    /// 使い捨ての保存先の名前（見本・テスト用。nil なら、ふつうの保存先）
    private let ephemeralName: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ephemeralName = nil
    }

    private init(ephemeralName: String) {
        defaults = UserDefaults(suiteName: ephemeralName) ?? .standard
        self.ephemeralName = ephemeralName
        defaults.removePersistentDomain(forName: ephemeralName)
    }

    deinit {
        // 使い捨ての保存先は、使い終わったら消す
        if let ephemeralName {
            UserDefaults.standard.removePersistentDomain(forName: ephemeralName)
        }
    }

    /// テストと見本用の、空の保存先。呼ぶたびに別の保存先を作る（見本の環境が複数あっても、互いの設定を消さない）
    static func ephemeral() -> SettingsStore {
        SettingsStore(ephemeralName: "jp.shilokuma.Hitoashi.ephemeral.\(UUID().uuidString)")
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
