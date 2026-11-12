//
//  SettingsScreen.swift
//  Hitoashi
//
//  設定（仕様書 §4-5）。OS 標準のリストをそのまま使う。
//

import HitoashiKit
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("週に何回", selection: $model.preferences.weeklyTarget) {
                        Text("2回").tag(WeeklyTarget.two)
                        Text("3回").tag(WeeklyTarget.three)
                        Text("5回").tag(WeeklyTarget.five)
                        Text("毎日").tag(WeeklyTarget.everyday)
                    }
                    Picker("1回の長さ", selection: $model.preferences.durationMinutes) {
                        Text("10分").tag(10)
                        Text("20分").tag(20)
                        Text("30分").tag(30)
                    }
                    NavigationLink("提案してよい時間") {
                        AllowedSlotsForm()
                    }
                } footer: {
                    Text("「週に何回」は、お知らせの回数と、記録の目標に使います。")
                }

                Section("動き方") {
                    Toggle("屋根のあるところを歩く", isOn: $model.preferences.coveredWalkEnabled)
                    Toggle("走る", isOn: $model.preferences.jogEnabled)
                    Toggle("いつものジム", isOn: $model.preferences.gymEnabled)
                    if model.preferences.gymEnabled {
                        TextField("ジムの名前（例: ○○フィットネス）", text: gymNames)
                    }
                    Picker("暗くなったら", selection: $model.preferences.afterDark) {
                        Text("駅までの道を歩く").tag(AfterDarkPolicy.walkToStation)
                        Text("屋内にする").tag(AfterDarkPolicy.indoor)
                    }
                }

                Section {
                    ForEach(model.bases) { base in
                        LabeledContent(baseKindName(base.kind), value: base.name)
                    }
                    NavigationLink("提案しない題名") {
                        ExcludedWordsForm()
                    }
                    .badge(model.preferences.excludedTitleWords.count)
                } header: {
                    Text("拠点と予定")
                } footer: {
                    Text("場所の入っていない予定は、拠点にいるものとして提案します。平日は職場、休日は自宅を使います。")
                }

                Section("お知らせ") {
                    Toggle("当日のお知らせ", isOn: $model.preferences.dayNoticeEnabled)
                    Picker("前の晩のお知らせ", selection: $model.preferences.eveningNotice) {
                        Text("準備が要るときだけ").tag(EveningNoticePolicy.whenPreparationNeeded)
                        Text("毎晩").tag(EveningNoticePolicy.always)
                        Text("オフ").tag(EveningNoticePolicy.never)
                    }
                    Toggle("通知に予定の題名を入れる", isOn: $model.preferences.includesEventTitleInNotice)
                }

                Section {
                    Button(model.isPro ? "ひとあし Pro を利用中" : "ひとあし Pro") {
                        model.showsPaywall = true
                    }
                    .disabled(model.isPro)
                }

                AboutSection()
            }
            .tint(Palette.ink2)
            .navigationTitle("設定")
        }
        .accessibilityIdentifier("settings")
    }

    private var gymNames: Binding<String> {
        Binding {
            model.preferences.gymNames.joined(separator: "、")
        } set: { text in
            model.preferences.gymNames = text
                .split(whereSeparator: { "、,".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
    }

    private func baseKindName(_ kind: BaseKind) -> String {
        switch kind {
        case .home:
            String(localized: "自宅")
        case .work:
            String(localized: "職場")
        case .extra:
            String(localized: "そのほか")
        }
    }
}

/// 提案してよい時間（空き時間の種類ごとのオン・オフ）
private struct AllowedSlotsForm: View {
    @Environment(AppModel.self) private var model

    private let kinds: [(SlotKind, LocalizedStringKey)] = [
        (.lunch, "昼休み"),
        (.between, "予定の合間"),
        (.afterLast, "最後の予定のあと"),
        (.beforeFirst, "朝いちばんの予定の前"),
        (.freeDay, "予定のない日")
    ]

    var body: some View {
        Form {
            Section {
                ForEach(kinds, id: \.0) { kind, title in
                    Toggle(title, isOn: binding(for: kind))
                }
            } footer: {
                Text("朝いちばんの予定の前は、当日には知らせず、前の晩にだけお知らせします。")
            }
        }
        .tint(Palette.ink2)
        .navigationTitle("提案してよい時間")
    }

    private func binding(for kind: SlotKind) -> Binding<Bool> {
        Binding {
            model.preferences.allowedSlots.contains(kind)
        } set: { isOn in
            if isOn {
                model.preferences.allowedSlots.insert(kind)
            } else {
                model.preferences.allowedSlots.remove(kind)
            }
        }
    }
}

/// 提案しない題名（除外語）。当たった予定の前後には提案しない
private struct ExcludedWordsForm: View {
    @Environment(AppModel.self) private var model
    @State private var newWord = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("題名に含まれる言葉", text: $newWord)
                        .onSubmit(add)
                    Button("追加", action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("題名にこの言葉を含む予定の前後には、提案しません（通院、会食、送り迎えなど）。")
            }
            Section {
                ForEach(model.preferences.excludedTitleWords, id: \.self) { word in
                    Text(word)
                }
                .onDelete { offsets in
                    model.preferences.excludedTitleWords.remove(atOffsets: offsets)
                }
            }
        }
        .tint(Palette.ink2)
        .navigationTitle("提案しない題名")
    }

    private func add() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !model.preferences.excludedTitleWords.contains(word) else {
            return
        }
        model.preferences.excludedTitleWords.insert(word, at: 0)
        newWord = ""
    }
}

/// このアプリについて（安全についての注意・天気データ・データの消去）
private struct AboutSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsErase = false

    var body: some View {
        Section {
            NavigationLink("安全についての注意") {
                ScrollView {
                    SafetyNote()
                        .padding(20)
                }
                .background(Palette.ground)
                .navigationTitle("安全についての注意")
            }
            NavigationLink("天気データについて") {
                ScrollView {
                    WeatherDataNote()
                        .padding(20)
                }
                .background(Palette.ground)
                .navigationTitle("天気データについて")
            }
            Button("データをすべて消す", role: .destructive) {
                confirmsErase = true
            }
            .confirmationDialog("設定と記録をすべて消します。元に戻せません。", isPresented: $confirmsErase, titleVisibility: .visible) {
                Button("すべて消す", role: .destructive) {
                    model.eraseAll()
                }
            }
        } header: {
            Text("このアプリについて")
        } footer: {
            Text("予定の題名・メモ・参加者は、この端末から出ません。場所の名前と位置だけを、天気と地図を調べるために Apple に送ります。")
        }
    }
}

/// 安全についての注意（仕様書 §4-1）。初回と設定の両方で出す
struct SafetyNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ひとあしの提案は、天気予報にもとづく目安です。医学的な助言ではありません。")
            Text("予報は外れることがあります。出かける前に空と体調を確かめ、無理をしないでください。")
            Text("持病のある方、妊娠中の方、体調に不安のある方は、運動を始める前に医師に相談してください。")
            Text("歩くときは交通ルールを守り、画面を見ながら歩かないでください。")
        }
        .type(.body)
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 天気データについて（帰属表示と、加工したデータであること）
struct WeatherDataNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WeatherAttributionView()
                .type(.body)
            Text("天気は Apple Weather のデータです。ひとあしは、そのデータをもとに「外がおすすめ」「屋内」などを判定しています（加工したデータです）。")
            Text("大気の状態（煙・PM2.5・花粉）は見ていません。この地域で警報の情報を取得できないときは、警報による「休む日」は働きません。")
            Text("予報は最長 24時間で端末から消します。記録には、気温や天気を残しません。")
        }
        .type(.body)
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
