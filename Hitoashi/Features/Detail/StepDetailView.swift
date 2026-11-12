//
//  StepDetailView.swift
//  Hitoashi
//
//  ひと足の詳細（仕様書 §4-3）。何を・いつから・何分、地図、決め手、代わりの案。主ボタンは 1 つ。
//

import HitoashiKit
import MapKit
import SwiftUI

struct StepDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var suggestionID: String

    var body: some View {
        if let suggestion = model.suggestion(id: suggestionID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(suggestion)
                    StepMap(suggestion: suggestion)
                    ReasonSection(suggestion: suggestion)
                    AlternativesSection(suggestion: suggestion)
                    ReasonDetails(suggestion: suggestion)
                }
                .padding(.bottom, 16)
            }
            .background(Palette.ground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StepActions(suggestion: suggestion) {
                    dismiss()
                }
            }
            .accessibilityIdentifier("detail")
        } else {
            ContentUnavailableView("このひと足は、もうありません", systemImage: "clock")
        }
    }

    private func header(_ suggestion: Suggestion) -> some View {
        let book = model.book
        return VStack(alignment: .leading, spacing: 6) {
            Text(book.slotLabel(suggestion.slot))
                .type(.captionStrong)
                .foregroundStyle(Palette.shu)
            Text(book.title(for: suggestion.plan))
                .type(.heading)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text(summary(suggestion, book: book))
                .type(.body)
                .monospacedDigit()
                .foregroundStyle(Palette.ink2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// 「15:10から20分・往復1.2km」
    private func summary(_ suggestion: Suggestion, book: Phrasebook) -> String {
        var text = String(localized: "\(book.time(suggestion.window.start))から\(book.minutes(suggestion.plan.minutes))")
        let plan = suggestion.plan
        if plan.spot != nil, plan.activity == .walk {
            let meters = plan.distanceMeters * 1.3 * (plan.route == .roundTrip ? 2 : 1)
            let label = plan.route == .roundTrip ? String(localized: "往復") : String(localized: "片道")
            text += "・\(label)\(book.distance(meters: meters))"
        }
        return text
    }
}

/// 地図。起点（予定の場所）とスポット。左右いっぱい・角丸なし
struct StepMap: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion

    var body: some View {
        let origin = suggestion.slot.place.coordinate.clLocation
        Map(initialPosition: .region(region), interactionModes: []) {
            Annotation(suggestion.slot.place.name, coordinate: origin) {
                Circle()
                    .fill(Palette.ink)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().fill(Palette.onInk).frame(width: 5, height: 5))
            }
            if let spot = suggestion.plan.spot {
                Marker(spot.name, coordinate: spot.coordinate.clLocation)
                    .tint(Palette.shu)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .overlay(alignment: .bottomLeading) {
            if let caption {
                Text(caption)
                    .type(.captionStrong)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.onInk)
                    .padding(10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? String(localized: "地図"))
        // 同じ提案でも場所を選び直したら、地図の範囲を取り直す
        .id(suggestion.plan.spot?.id ?? "none")
    }

    private var caption: String? {
        guard suggestion.plan.spot != nil else {
            return nil
        }
        let book = model.book
        let minutes = book.minutes(suggestion.plan.walkMinutesToSpot)
        let distance = book.distance(meters: suggestion.plan.distanceMeters * 1.3)
        return String(localized: "徒歩\(minutes)・\(distance)")
    }

    private var region: MKCoordinateRegion {
        let origin = suggestion.slot.place.coordinate
        let target = suggestion.plan.spot?.coordinate ?? origin
        let center = CLLocationCoordinate2D(
            latitude: (origin.latitude + target.latitude) / 2,
            longitude: (origin.longitude + target.longitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.006, abs(origin.latitude - target.latitude) * 2.2),
            longitudeDelta: max(0.006, abs(origin.longitude - target.longitude) * 2.2)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// 代わりの案（雨なら / 晴れたら）と、ほかの場所。右端はどちらも「これにする」
struct AlternativesSection: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion

    var body: some View {
        let book = model.book
        VStack(spacing: 0) {
            if let alternate = suggestion.alternate {
                row(label: book.alternateLabel(alternate.label), text: book.alternateText(alternate)) {
                    model.choose(alternate.plan, for: suggestion)
                }
                .accessibilityIdentifier("detail.alternate")
            }
            ForEach(Array(suggestion.otherSpots.enumerated()), id: \.element.id) { index, spot in
                let minutes = suggestion.slot.place.coordinate.walkingMinutes(to: spot.coordinate)
                row(
                    label: index == 0 ? String(localized: "ほかに") : "",
                    text: String(localized: "\(spot.name) 徒歩\(book.minutes(minutes))")
                ) {
                    model.choose(spot: spot, for: suggestion)
                }
                .contextMenu {
                    Button("この場所は出さない", systemImage: "hand.raised") {
                        model.reject(spot: spot)
                    }
                }
            }
            if suggestion.plan.activity == .coveredWalk || suggestion.plan.activity == .gym {
                Text("営業時間はマップで確認してください。")
                    .type(.note)
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func row(label: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .type(.captionStrong)
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 54, alignment: .leading)
                Text(text)
                    .type(.body)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("これにする")
                    .type(.captionStrong)
                    .foregroundStyle(Palette.ink)
            }
            .ruledRow()
        }
        .buttonStyle(.plain)
    }
}

/// 主ボタンと副ボタン。iPhone・iPad は「行く」（マップで経路を開く）。Mac・Vision Pro は持ち歩かないので「行ってくる」（記録だけ）
struct StepActions: View {
    @Environment(AppModel.self) private var model
    var suggestion: Suggestion
    var onClose: () -> Void

    var body: some View {
        let log = model.log(for: suggestion)
        VStack(spacing: 8) {
            if log?.outcome == .started {
                Text("行く、と記録しました。どうでしたか。")
                    .type(.note)
                    .foregroundStyle(Palette.ink2)
                Button("やった") {
                    model.record(suggestion, outcome: .done)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("detail.done")
                Button("やらなかった") {
                    model.record(suggestion, outcome: .skipped)
                }
                .buttonStyle(PlainRowButtonStyle())
            } else if let log, log.outcome != .started {
                Text(log.outcome == .done ? "やった、と記録しました。" : "きょうはやめておく、と記録しました。")
                    .type(.sub)
                    .foregroundStyle(Palette.ink2)
                    .frame(minHeight: 44)
            } else {
                goButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .barBackground()
    }

    @ViewBuilder private var goButtons: some View {
        #if os(iOS)
        if let spot = suggestion.plan.spot {
            Text("マップで経路を開きます")
                .type(.note)
                .foregroundStyle(Palette.ink2)
            Button {
                model.record(suggestion, outcome: .started)
                MapsLauncher.openWalkingDirections(to: spot)
            } label: {
                Label("行く", systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("detail.go")
        } else {
            Button("はじめる") {
                model.record(suggestion, outcome: .started)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("detail.go")
        }
        #else
        Button("行ってくる") {
            model.record(suggestion, outcome: .started)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("detail.go")
        if let spot = suggestion.plan.spot {
            Button("マップで見る") {
                MapsLauncher.openWalkingDirections(to: spot)
            }
            .buttonStyle(PlainRowButtonStyle(color: Palette.ink))
        }
        #endif
        Button("きょうはやめておく") {
            model.record(suggestion, outcome: .skipped)
            onClose()
        }
        .type(.body)
        .buttonStyle(PlainRowButtonStyle())
        .accessibilityIdentifier("detail.skip")
    }
}

/// 文字のあとにアイコンを置くラベル
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .font(.subheadline.weight(.semibold))
        }
    }
}
