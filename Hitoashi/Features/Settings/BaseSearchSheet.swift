//
//  BaseSearchSheet.swift
//  Hitoashi
//
//  拠点（自宅・職場）を登録する。住所・駅名・建物の名前で探すか、現在地を使う（仕様書 §4-1、§5-3）。
//

import HitoashiKit
import SwiftUI

struct BaseSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: BaseKind

    @State private var query = ""
    @State private var results: [GeocodeHit] = []
    @State private var isLocating = false
    @State private var locationFailed = false
    /// 「現在地を使う」を押した回数（0 は、まだ押していない）。画面を閉じたら、待っている取得を止める
    @State private var locateRequest = 0
    /// すでに場所を選んだ（あとから届いた現在地で上書きしない）
    @State private var hasChosen = false

    var body: some View {
        NavigationStack {
            List {
                #if os(macOS)
                // Mac のシートにはツールバーの検索欄が出ないので、欄を中に置く
                Section {
                    TextField("住所・駅名・建物の名前", text: $query)
                        .textFieldStyle(.roundedBorder)
                }
                #endif
                Section {
                    Button {
                        locateRequest += 1
                    } label: {
                        HStack {
                            Label("現在地を使う", systemImage: "location")
                            Spacer()
                            if isLocating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLocating)
                    .accessibilityIdentifier("base.current")
                } footer: {
                    if locationFailed {
                        Text("現在地を取得できませんでした。住所や駅名で探してください。")
                    } else {
                        Text("現在地は、拠点を登録するためだけに使います。")
                    }
                }
                if !results.isEmpty {
                    Section("見つかった場所") {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, hit in
                            Button {
                                choose(hit)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name)
                                        .foregroundStyle(Palette.ink)
                                    if !hit.placeNames.isEmpty {
                                        Text(hit.placeNames.joined(separator: " "))
                                            .type(.caption)
                                            .foregroundStyle(Palette.ink2)
                                    }
                                }
                            }
                        }
                    }
                }
                if model.base(kind) != nil {
                    Section {
                        Button("登録を消す", role: .destructive) {
                            model.removeBase(kind)
                            dismiss()
                        }
                    }
                }
            }
            #if !os(macOS)
            .searchable(text: $query, prompt: Text("住所・駅名・建物の名前"))
            #endif
            .task(id: query) {
                await search()
            }
            .task(id: locateRequest) {
                if locateRequest > 0 {
                    await useCurrentLocation()
                }
            }
            .navigationTitle(kind == .home ? Text("自宅") : Text("職場"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .tint(Palette.ink)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    /// 入力が落ち着いてから探す
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else {
            return
        }
        results = await model.searchPlaces(text)
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        let hit = await model.currentPlace()
        // 待っているあいだに画面を閉じた・ほかの場所を選んだときは、登録しない
        guard !Task.isCancelled, !hasChosen else {
            return
        }
        guard let hit else {
            locationFailed = true
            return
        }
        choose(hit)
    }

    private func choose(_ hit: GeocodeHit) {
        hasChosen = true
        model.setBase(kind, name: hit.name, coordinate: hit.coordinate)
        dismiss()
    }
}

/// 拠点の 2 行（自宅・職場）。押すと登録の画面が開く。設定と「はじめに」で使う
struct BaseRows: View {
    @Environment(AppModel.self) private var model
    @State private var editing: BaseKind?

    var body: some View {
        ForEach([BaseKind.home, .work], id: \.self) { kind in
            Button {
                editing = kind
            } label: {
                HStack {
                    Text(kind == .home ? "自宅" : "職場")
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(model.base(kind)?.name ?? String(localized: "登録する"))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("base.\(kind.rawValue)")
        }
        .sheet(item: $editing) { kind in
            BaseSearchSheet(kind: kind)
        }
    }
}

extension BaseKind: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// 対象のカレンダー（仕様書 §4-1）。既定は、自分で編集できるカレンダーだけオン
struct CalendarsForm: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let groups = Dictionary(grouping: model.calendars, by: \.sourceTitle)
        Form {
            if model.calendars.isEmpty {
                Section {
                    Text("読めるカレンダーがありません。")
                } footer: {
                    Text("Google などのカレンダーは、端末の設定でアカウントを追加すると読めます。")
                }
            }
            ForEach(groups.keys.sorted(), id: \.self) { source in
                Section(source) {
                    ForEach(groups[source] ?? []) { info in
                        Toggle(info.title, isOn: binding(for: info))
                    }
                }
            }
        }
        .tint(Palette.ink2)
        .navigationTitle("対象のカレンダー")
    }

    private func binding(for info: CalendarInfo) -> Binding<Bool> {
        Binding {
            model.isCalendarOn(info)
        } set: { isOn in
            model.setCalendar(info, isOn: isOn)
        }
    }
}
