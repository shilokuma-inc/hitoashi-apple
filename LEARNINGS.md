# LEARNINGS — hitoashi-apple

このリポジトリで分かった、ツールや環境の癖。どのリポジトリでも通じるものは `~/.agents/LEARNINGS.md` に書く。

## ビルド・プロジェクト

- テンプレート（template-app-ios）を 1 ターゲットのまま iOS / macOS / visionOS に対応させるには、pbxproj の `SDKROOT = auto` と `TARGETED_DEVICE_FAMILY = "1,2,7"`、xcconfig の `SUPPORTED_PLATFORMS` を足す。`SUPPORTED_PLATFORMS` は pbxproj に無いので xcconfig（プロジェクトの階層）で効く。`TARGETED_DEVICE_FAMILY` はターゲットの階層に書いてあるので、xcconfig では上書きできない（2026-11-12）
- ローカルパッケージの `platforms` に `.iOS(.v26)` を書くには `swift-tools-version: 6.2` 以上が要る（6.0 だと `'v26' was introduced in PackageDescription 6.2`）（2026-11-12）
- WeatherKit の entitlement を付けたまま、Simulator 向け（iOS / visionOS）はプロビジョニングなしでビルドできる。Mac 版は実際の署名が要るので、手元では `-allowProvisioningUpdates` を付ける（Xcode にサインイン済みなら App ID とプロファイルが自動で作られる）。CI は `CODE_SIGNING_ALLOWED=NO` でコンパイルだけ確かめる（2026-11-12）
