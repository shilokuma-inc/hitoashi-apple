# LEARNINGS — hitoashi-apple

このリポジトリで分かった、ツールや環境の癖。どのリポジトリでも通じるものは `~/.agents/LEARNINGS.md` に書く。

## ビルド・プロジェクト

- テンプレート（template-app-ios）を 1 ターゲットのまま iOS / macOS / visionOS に対応させるには、pbxproj の `SDKROOT = auto` と `TARGETED_DEVICE_FAMILY = "1,2,7"`、xcconfig の `SUPPORTED_PLATFORMS` を足す。`SUPPORTED_PLATFORMS` は pbxproj に無いので xcconfig（プロジェクトの階層）で効く。`TARGETED_DEVICE_FAMILY` はターゲットの階層に書いてあるので、xcconfig では上書きできない（2026-11-12）
- ローカルパッケージの `platforms` に `.iOS(.v26)` を書くには `swift-tools-version: 6.2` 以上が要る（6.0 だと `'v26' was introduced in PackageDescription 6.2`）（2026-11-12）
- WeatherKit の entitlement を付けたまま、Simulator 向け（iOS / visionOS）はプロビジョニングなしでビルドできる。Mac 版は実際の署名が要るので、手元では `-allowProvisioningUpdates` を付ける（Xcode にサインイン済みなら App ID とプロファイルが自動で作られる）。CI は `CODE_SIGNING_ALLOWED=NO` でコンパイルだけ確かめる（2026-11-12）
- 日本語を基本の言語にするには、pbxproj の `developmentRegion` を `ja`（`knownRegions` に `ja`）にする。`en` のままだと、端末が日本語でも `Locale.current` が英語になり、日付や曜日が英語で出る（2026-11-12）

## 起動・テスト・画面の確認

- Mac 版に起動引数を渡すときは、必ず「-キー 値」の組にする（`-screenshot-demo YES -screenshot-scene home`）。組になっていない引数（`-screenshot-demo -screenshot-scene home` の `home`）があると、AppKit がファイルを開く要求として扱い、SwiftUI の `WindowGroup` が最初のウインドウを開かない。プロセスは動いているのに画面が出ない（2026-11-12）
- 画面収録の許可が無い環境（`screencapture -l` が `could not create image from window` になる）では、Mac 版の画面を外から撮れない。サンドボックスのコンテナも、ほかのプロセスからは読めない（`Operation not permitted`）。DEBUG のビルドには、ウインドウを PNG にして標準出力へ書き出す仕組みがある（`Hitoashi/Screenshot/WindowSnapshot.swift`。`-window-snapshot YES`）。地図（MapKit）は写らない（2026-11-12）
- 手元の `xcodebuild test`（iOS Simulator）が `DTServiceHubClient failed to bless service hub for simulator` や `The test runner hung before establishing connection` で進まないことがある。Unit テストは Mac で流せる（`-destination 'platform=macOS,arch=arm64' -skip-testing:HitoashiUITests -allowProvisioningUpdates`）。UI テストは CI で確かめる（2026-11-12）
- CI の `swiftlint lint --strict` は、ビルド時のプラグインでは警告どまりの違反（`cyclomatic_complexity` が 10 超、`line_length` が 140 超、`function_body_length` が 50 行超、`function_parameter_count` が 5 超）もエラーにする。case の多い `switch` は辞書に、引数の多い関数は入力の構造体にまとめる。push の前に手元で `--strict` を流す（2026-11-12）

## デザイン・実装

- 天気の帯の斜線を行をまたいでつなげるには、各行の `Canvas` の上端がタイムライン全体の座標（`coordinateSpace(name:)`）でどこにあるかを `GeometryReader` で取り、線の位相をそろえる。`Canvas` の中の座標だけで引くと、行の境目で斜線がずれる（2026-11-12）
- Vision Pro はウインドウがガラスなので、地を不透明に塗らず（`Palette.ground` は透明）、文字は `Color.primary` / `Color.secondary` に任せる。アセットの色（ダークの値）をそのまま使うと、明るい部屋の上で補助の文字が読めない（2026-11-12）
