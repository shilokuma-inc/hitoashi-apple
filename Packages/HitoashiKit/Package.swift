// swift-tools-version: 6.2
import PackageDescription

// ひとあし / Hitoashi の判定と計画のロジック（空き時間の検出・そと判定・ひと足の決定・通知の計画）。
// EventKit・WeatherKit・MapKit などには依存させず、値の型だけで書く。
// macOS も対象にしているのは、Simulator を起動せずに `swift test` でテストを回すため。
let package = Package(
    name: "HitoashiKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "HitoashiKit", targets: ["HitoashiKit"])
    ],
    targets: [
        .target(name: "HitoashiKit"),
        .testTarget(name: "HitoashiKitTests", dependencies: ["HitoashiKit"])
    ],
    swiftLanguageModes: [.v6]
)
