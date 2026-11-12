# LEARNINGS — hitoashi-apple

このリポジトリで分かった、ツールや環境の癖。どのリポジトリでも通じるものは `~/.agents/LEARNINGS.md` に書く。

## ビルド・プロジェクト

- テンプレート（template-app-ios）を 1 ターゲットのまま iOS / macOS / visionOS に対応させるには、pbxproj の `SDKROOT = auto` と `TARGETED_DEVICE_FAMILY = "1,2,7"`、xcconfig の `SUPPORTED_PLATFORMS` を足す。`SUPPORTED_PLATFORMS` は pbxproj に無いので xcconfig（プロジェクトの階層）で効く。`TARGETED_DEVICE_FAMILY` はターゲットの階層に書いてあるので、xcconfig では上書きできない（2026-11-12）
- ローカルパッケージの `platforms` に `.iOS(.v26)` を書くには `swift-tools-version: 6.2` 以上が要る（6.0 だと `'v26' was introduced in PackageDescription 6.2`）（2026-11-12）
- WeatherKit の entitlement を付けたまま、Simulator 向け（iOS / visionOS）はプロビジョニングなしでビルドできる。Mac 版は実際の署名が要るので、手元では `-allowProvisioningUpdates` を付ける（Xcode にサインイン済みなら App ID とプロファイルが自動で作られる）。CI は `CODE_SIGNING_ALLOWED=NO` でコンパイルだけ確かめる（2026-11-12）
- WeatherKit は、App ID の Capabilities に付いているだけでは動かない。自動署名が付けるのは Capabilities の側だけで、Certificates, Identifiers & Profiles → Identifiers → 対象の App ID → **App Services** タブの WeatherKit は手で有効にする。無いと、署名した Mac 版でも Simulator でも `WDSJWTAuthenticatorServiceListener.Errors Code=2`（`WeatherKit App Service is not enabled for this App ID`）で予報を取れない。有効にしてから反映まで少し時間がかかることがある（2026-11-12）
- 日本語を基本の言語にするには、pbxproj の `developmentRegion` を `ja`（`knownRegions` に `ja`）にする。`en` のままだと、端末が日本語でも `Locale.current` が英語になり、日付や曜日が英語で出る（2026-11-12）

## 起動・テスト・画面の確認

- Mac 版に起動引数を渡すときは、必ず「-キー 値」の組にする（`-screenshot-demo YES -screenshot-scene home`）。組になっていない引数（`-screenshot-demo -screenshot-scene home` の `home`）があると、AppKit がファイルを開く要求として扱い、SwiftUI の `WindowGroup` が最初のウインドウを開かない。プロセスは動いているのに画面が出ない（2026-11-12）
- 画面収録の許可が無い環境（`screencapture -l` が `could not create image from window` になる）では、Mac 版の画面を外から撮れない。サンドボックスのコンテナも、ほかのプロセスからは読めない（`Operation not permitted`）。DEBUG のビルドには、ウインドウを PNG にして標準出力へ書き出す仕組みがある（`Hitoashi/Screenshot/WindowSnapshot.swift`。`-window-snapshot YES`）。地図（MapKit）は写らない（2026-11-12）
- 手元の `xcodebuild test`（iOS Simulator）が `DTServiceHubClient failed to bless service hub for simulator` や `The test runner hung before establishing connection` で進まないことがある。Unit テストは Mac で流せる（`-destination 'platform=macOS,arch=arm64' -skip-testing:HitoashiUITests -allowProvisioningUpdates`）。UI テストは CI で確かめる（2026-11-12）
- CI の `swiftlint lint --strict` は、ビルド時のプラグインでは警告どまりの違反（`cyclomatic_complexity` が 10 超、`line_length` が 140 超、`function_body_length` が 50 行超、`function_parameter_count` が 5 超）もエラーにする。case の多い `switch` は辞書に、引数の多い関数は入力の構造体にまとめる。push の前に手元で `--strict` を流す（2026-11-12）
- WeatherKit が使えない環境でも、DEBUG のビルドは `-debug-sample-weather YES` で、予報だけを見本の値にして残り（カレンダー・場所の解決・スポット・通知）を実データで確かめられる。疎通だけを見るなら `-weather-probe YES`（結果を標準出力に出す）。Simulator のカレンダーに確認用の予定を入れるのは `-seed-calendar YES`（2026-11-12）
- `.storekit` を手で書くときは、`settings` を Xcode が書き出す形（`_failTransactionsEnabled`・`_locale`・`_storefront`・`_storeKitErrors` の一覧）にそろえる。欠けていると、エラーも出ずに `Product.products(for:)` が空を返す。Mac の `SKTestSession.buyProduct` は `.unknown` で失敗するので、テストは商品の取得と価格・無料体験の設定だけを確かめている（2026-11-12）
- アプリを親にして走るテスト（HitoashiTests の Swift Testing）は、`xcodebuild test` の標準出力に結果が出ない（出るのはパッケージのテストだけ）。走った数は `xcrun xcresulttool get test-results summary --path <xcresult>` で確かめる（2026-11-12）
- `Logger` の `info` は、`log show` に `--info` を付けないと出ない。通知を予約した件数は `xcrun simctl spawn <udid> log show --last 5m --info --predicate 'subsystem == "jp.shilokuma.Hitoashi" AND category == "notices"'` で見られる（2026-11-12）
- 子のボタンに付けた `accessibilityIdentifier` は、親のコンテナ（`ScrollView` や `VStack`）にも識別子を付けると上書きされ、UI テストから見つからなくなる。画面全体には識別子を付けない（2026-11-12）
- MapKit の種類だけの検索（`MKLocalPointsOfInterestRequest` に `.publicTransport`）は 36 件ほどで打ち切られ、街なかではバス停とタクシー乗り場で埋まって駅が 1 件も返らない。駅は `MKLocalSearch.Request` の `naturalLanguageQuery = "駅"` に `pointOfInterestFilter`（`.publicTransport`）を足して探し、名前で「のりば・乗り場・タクシー・バス」を外す。保存の中身（Simulator のアプリのコンテナの `Library/Caches/spots.json`）を見ると、種類ごとの件数を確かめられる（2026-11-12）
- MapKit の検索は、1 件も無いときに `MKError.placemarkNotFound` を投げる。`try?` でまとめて握りつぶすと、通信の失敗と区別できず、「見つからなかった」として保存してしまう。保存する前に分ける（2026-11-12）
- CI の iOS Simulator では、`SKTestSession` が設定ファイルを保存できず（ログに `[SKTestSession] Error saving configuration file: Error Domain=SKInternalErrorDomain Code=3`）、`Product.products(for:)` が空で返る。原因は分かっていない（手元の Mac では通る）。`StoreTests` は `#if os(macOS)` で Mac だけにしてあり、CI では走らない。手元で Mac を宛先にして確かめる（2026-11-12）
- `UNUserNotificationCenterDelegate` の async のメソッドは、`nonisolated` を付けずに書ける（型が MainActor なら、OS への完了の合図もメインから返る）。`nonisolated` にすると完了がメイン以外から返り、通知を押したときに落ちることがある。Simulator では `xcrun simctl push <udid> <bundle id> payload.json` で通知を届けて、押したときの動きを確かめられる（2026-11-12）

## デザイン・実装

- 天気の帯の斜線を行をまたいでつなげるには、各行の `Canvas` の上端がタイムライン全体の座標（`coordinateSpace(name:)`）でどこにあるかを `GeometryReader` で取り、線の位相をそろえる。`Canvas` の中の座標だけで引くと、行の境目で斜線がずれる（2026-11-12）
- Vision Pro はウインドウがガラスなので、地を不透明に塗らず（`Palette.ground` は透明）、文字は `Color.primary` / `Color.secondary` に任せる。アセットの色（ダークの値）をそのまま使うと、明るい部屋の上で補助の文字が読めない（2026-11-12）
